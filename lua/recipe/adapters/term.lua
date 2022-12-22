local async = require("plenary.async")
local config = require("recipe.config")
local util = require("recipe.util")
local api = vim.api
local fn = vim.fn
local M = {}

local components = require("recipe.components")

---Opens a new terminal
---@param config TermConfig
function M.open_win(config, bufnr)
	local function open_split(split)
		vim.cmd(split)
		local win = vim.api.nvim_get_current_win()
		api.nvim_win_set_buf(win, bufnr)
		return win
	end

	if config.kind == "float" then
		local lines = vim.o.lines
		local cols = vim.o.columns
		local cmdheight = vim.o.cmdheight

		local height = math.ceil(config.height < 1 and config.height * lines or config.height)
		local width = math.ceil(config.width < 1 and config.width * cols or config.width)

		local row = math.ceil((lines - height) / 2 - cmdheight)
		local col = math.ceil((cols - width) / 2)

		local win = api.nvim_open_win(bufnr, true, {
			relative = "editor",
			row = row,
			col = col,
			height = height,
			width = width,
			border = config.border,
		})

		local function close()
			if api.nvim_win_is_valid(win) and api.nvim_get_current_win() ~= win then
				api.nvim_win_close(win, false)
			end
		end

		vim.api.nvim_create_autocmd("WinLeave", {
			callback = function()
				vim.defer_fn(close, 100)
			end,
			buffer = bufnr,
		})

		return win
	elseif config.kind == "split" then
		return open_split("split")
	elseif config.kind == "vsplit" then
		return open_split("vsplit")
	elseif config.kind == "smart" then
		local font_lh_ratio = 0.3
		local w, h = api.nvim_win_get_width(0) * font_lh_ratio, api.nvim_win_get_height(0)
		local cmd = (w > h) and "vsplit" or "split"
		return open_split(cmd)
	else
		api.nvim_err_writeln("Recipe: Unknown terminal mode " .. config.kind)
	end
end

local terminals = {}

local function find_win(bufnr)
	local win = fn.bufwinid(bufnr)
	if win == -1 then
		return nil
	else
		return win
	end
end

function M.acquire_focused_win(key, config, bufnr)
	local existing = terminals[key]
	local win

	if existing then
		win = find_win(existing)
	end

	if win then
		-- Focus the window and buffer
		api.nvim_set_current_win(win)
		api.nvim_win_set_buf(win, bufnr)
		return win
	else
		return M.open_win(config, bufnr)
	end
end

---@enum TaskState
local TaskState = {
	PENDING = "pending",
	RUNNING = "running",
	STOPPED = "stopped",
}

---Represents a running task
---@class Task
---@field bufnr number The buffer containing the process output
---@field jobnr number|nil
---@field restart fun(on_exit: fun(code: number): Task|nil): Task
---@field recipe Recipe
---@field data table<string, any>
---@field env table<string, string>
---@field on_exit fun(task: Task, code: number)[]
---@field deferred_focus fun(task: Task)
---@field deps Task[]
---@field state TaskState
---@field code number|nil
---@field open_mode TermConfig
local Task = {}
Task.__index = Task

function Task:attach_callback(cb)
	if self.state == TaskState.STOPPED then
		vim.schedule(function()
			cb(self, self.code)
		end)
	else
		table.insert(self.on_exit, cb)
	end
end

function Task:stop()
	for _, dep in ipairs(self.deps) do
		dep:stop()
	end

	if self.jobnr then
		fn.jobstop(self.jobnr)
	end
end

---@param mode TermConfig
function Task:focus(mode)
	local function f()
		local win = M.acquire_focused_win(
			self.recipe.name,
			vim.tbl_extend("keep", mode, require("recipe.config").opts.term),
			self.bufnr
		)

		-- Do this afterwards to be able to look up the old buffer
		terminals[self.recipe.name] = self.bufnr

		if config.opts.scroll_to_end then
			util.scroll_to_end(win)
		end
	end

	if self.state ~= TaskState.PENDING then
		f()
	else
		self.deferred_focus = f
	end
end

function Task:restart()
	return self
end

---@type fun(): Task, number
Task.join = async.wrap(Task.attach_callback, 2)

---@param recipe Recipe
---@return Task
---Starts executing the task
function M.execute(recipe)
	---@type TermConfig
	-- local term_config = vim.tbl_deep_extend("force", require("recipe.config").opts.term, {})

	local key = recipe.name

	-- Create a blank buffer for the terminal
	local bufnr = api.nvim_create_buf(false, false)

	local env = vim.deepcopy(recipe.env) or {}
	env.__type = "table"

	local task = setmetatable({
		bufnr = bufnr,
		jobnr = nil,
		recipe = recipe,
		state = TaskState.PENDING,
		data = {},
		deps = {},
		on_exit = {},
		env = env,
	}, Task)

	async.run(function()
		--- Run dependencies

		local deps = {}
		local ok = true
		local lib = require("recipe.lib")
		for _, v in ipairs(recipe.depends_on or {}) do
			vim.notify("Executing dependency: " .. v:fmt_cmd())

			local child = lib.spawn(v)
			table.insert(task.deps, child)
			table.insert(deps, function()
				local _, code = child:join()
				if code ~= 0 then
					ok = false
				end
			end)
		end

		-- Await all dependencies
		if #deps > 0 then
			async.util.join(deps)
		end

		if not ok then
			task.state = TaskState.STOPPED
			task.code = -1
			return
		end

		task.deps = {}

		if config.opts.dotenv then
			local denv = require("recipe.dotenv").load(config.opts.dotenv)
			env = vim.tbl_extend("keep", env, denv)
		end

		local on_stdout, stdout_cleanup = util.curry_output("on_output", task)
		local on_stderr, stderr_cleanup = util.curry_output("on_output", task)

		local function on_exit(_, code)
			task.jobnr = nil
			task.code = code
			task.state = TaskState.STOPPED

			stdout_cleanup()
			stderr_cleanup()

			components.execute(recipe, "on_exit", task)

			if code == 0 and config.auto_close and fn.bufloaded(bufnr) == 1 then
				local win = find_win(bufnr)
				if win and api.nvim_win_is_valid(win) then
					api.nvim_win_close(win, {})
				end
			end

			for _, cb in ipairs(task.on_exit) do
				cb(task, code)
			end
		end

		if vim.fn.isdirectory(recipe.cwd) ~= 1 then
			util.error("No such directory: " .. vim.inspect(recipe.cwd))
			task.state = TaskState.STOPPED
			task.code = -1
			return
		end

		local jobnr
		vim.api.nvim_buf_call(task.bufnr, function()
			jobnr = fn.termopen(recipe.cmd, {
				cwd = recipe.cwd,
				on_exit = vim.schedule_wrap(on_exit),
				env = env,
				on_stdout = on_stdout,
				on_stderr = on_stderr,
			})
		end)

		if jobnr <= 0 then
			util.error("Failed to run command: " .. recipe:fmt_cmd())
			task.state = TaskState.STOPPED
			task.code = -1
			return
		end

		task.state = TaskState.RUNNING
		task.jobnr = jobnr

		components.execute(recipe, "on_start", task)

		if task.deferred_focus then
			task.deferred_focus(task)
		end
	end, function() end)

	return task
end

return M
