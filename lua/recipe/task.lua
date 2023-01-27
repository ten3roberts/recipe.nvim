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

---@alias Tasks { [string]: Task }

---Represents a task
---@class Task
---@field key string
---@field bufnr number The buffer containing the process output
---@field jobnr number|nil
---@field recipe Recipe
---@field data table<string, any>
---@field env table<string, string>
---@field on_exit fun(task: Task, code: number)[]
---@field deferred_focus fun(task: Task)
---@field deps Task[]
---@field state TaskState
---@field code number|nil
---@field open_mode TermConfig
---@field last_use number|nil
local Task = {}
Task.__index = Task

function Task:attach_callback(cb)
	if self.state == TaskState.STOPPED then
		vim.notify("attach_callback ready")
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

function Task:get_output()
	if self.bufnr and api.nvim_buf_is_valid(self.bufnr) then
		return api.nvim_buf_get_lines(self.bufnr, 0, -1, true)
	else
		return {}
	end
end

--- Creates a new task without running it
function Task:new(key, recipe)
	return setmetatable({
		key = key,
		recipe = recipe,
		state = TaskState.STOPPED,
		data = {},
		deps = {},
		on_exit = {},
		env = {},
	}, self)
end

function Task:format()
	local t = {}

	local task_state_map = {
		pending = "-",
		running = "*",
		stopped = " ",
	}

	table.insert(t, task_state_map[self.state] or "?")

	table.insert(t, self.recipe:format(self.key, 50))

	return table.concat(t, " ")
end

function Task:close()
	if not self.bufnr then
		return
	end

	local windows = vim.fn.win_findbuf(self.bufnr)

	for _, window in ipairs(windows) do
		api.nvim_win_close(window, true)
	end
end

function Task:open()
	self:spawn():focus({})
end

function Task:open_smart()
	self:spawn():focus({ kind = "smart" })
end

function Task:open_float()
	self:spawn():focus({ kind = "float" })
end

function Task:open_split()
	self:spawn():focus({ kind = "split" })
end

function Task:open_vsplit()
	self:spawn():focus({ kind = "vsplit" })
end

---@param mode TermConfig|nil
function Task:focus(mode)
	local function f()
		mode = vim.tbl_extend("keep", mode or {}, require("recipe.config").opts.term)

		local win = M.acquire_focused_win(self.recipe.key, mode, self.bufnr)

		-- Do this afterwards to be able to look up the old buffer
		terminals[self.recipe.key] = self.bufnr

		if config.opts.scroll_to_end then
			util.scroll_to_end(win)
		end
	end

	if self.bufnr and self.state ~= TaskState.PENDING then
		f()
	else
		self.deferred_focus = f
	end
end

function Task:restart()
	return self
end

Task._tostring = Task.format

---@type fun(): Task, number
Task.join = async.wrap(Task.attach_callback, 2)

---Starts executing the task
function Task:spawn()
	if self.state ~= TaskState.STOPPED then
		return self
	end

	self.data = {}
	self.deps = {}
	self.state = TaskState.PENDING
	---@type TermConfig
	-- local term_config = vim.tbl_deep_extend("force", require("recipe.config").opts.term, {})

	local key = self.recipe.key

	-- Create a blank buffer for the terminal
	local bufnr = api.nvim_create_buf(false, false)
	self.bufnr = bufnr
	local recipe = self.recipe

	local env = vim.deepcopy(self.recipe.env) or {}
	if vim.tbl_count(env) == 0 then
		env.__type = "table"
	end

	local uv = vim.loop
	async.run(function()
		--- Run dependencies

		local deps = {}
		local err
		local lib = require("recipe.lib")
		for _, v in ipairs(recipe.depends_on or {}) do
			local child = lib.insert_task(v.key, v):spawn()

			table.insert(self.deps, child)
			table.insert(deps, function()
				local _, code = child:join()
				if code ~= 0 then
					err = string.format("%s exited with code: %s", v.key, code)
				end
			end)
		end

		-- Await all dependencies
		if #deps > 0 then
			async.util.join(deps)
		end

		local on_stdout, stdout_cleanup = util.curry_output("on_output", self)
		local on_stderr, stderr_cleanup = util.curry_output("on_output", self)

		local start_time = uv.now()
		local function on_exit(_, code)
			self.jobnr = nil
			self.code = code
			self.state = TaskState.STOPPED

			stdout_cleanup()
			stderr_cleanup()

			if code == 0 and config.auto_close and fn.bufloaded(bufnr) == 1 then
				local win = find_win(bufnr)
				if win and api.nvim_win_is_valid(win) then
					api.nvim_win_close(win, {})
				end
			end

			local duration = (uv.now() - start_time)

			local level = (code == 0 and vim.log.levels.INFO) or vim.log.levels.ERROR

			local state = code == 0 and "Success" or string.format("Failure %d", code)

			local msg = string.format("%s: %q %s", state, key, util.format_time(duration))
			vim.notify(msg, level)

			for _, cb in ipairs(self.on_exit) do
				cb(self, code)
			end

			self.on_exit = {}
		end

		if err then
			util.error("Failed to execute dependency: " .. err)
			on_exit(nil, -1)
			return
		end

		self.deps = {}

		if config.opts.dotenv then
			local denv = require("recipe.dotenv").load(config.opts.dotenv)
			env = vim.tbl_extend("keep", env, denv)
		end

		self.env = env

		if vim.fn.isdirectory(recipe.cwd) ~= 1 then
			util.error("No such directory: " .. vim.inspect(recipe.cwd))
			on_exit(nil, -1)
			return
		end

		for _, hook in ipairs(config.opts.hooks.pre) do
			hook(recipe)
		end

		local cmd = self.recipe.cmd
		if not recipe.components.plain and type(recipe.cmd) == "string" then
			cmd = cmd:gsub("([%%#][:phtre]*)", fn.expand):gsub("(<%a+>[:phtre]*)", fn.expand)
		end

		local jobnr
		vim.api.nvim_buf_call(self.bufnr, function()
			jobnr = fn.termopen(cmd, {
				cwd = recipe.cwd,
				on_exit = vim.schedule_wrap(on_exit),
				env = env,
				on_stdout = on_stdout,
				on_stderr = on_stderr,
			})
		end)

		if jobnr <= 0 then
			util.error("Failed to run command: " .. recipe:fmt_cmd())
			on_exit(nil, -1)
			return
		end

		self.last_use = start_time
		self.state = TaskState.RUNNING
		self.jobnr = jobnr

		components.execute(recipe, "on_start", self)
		self:attach_callback(function()
			components.execute(recipe, "on_exit", self)
		end)

		if self.deferred_focus then
			self.deferred_focus(self)
			self.deferred_focus = nil
		end
	end, function() end)

	return self
end

return Task
