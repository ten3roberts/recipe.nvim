local async = require("plenary.async")
local config = require("recipe.config")
local util = require("recipe.util")
local api = vim.api
local fn = vim.fn
local M = {}
local components = require("recipe.components")

local function resolve_size(size, parent_size)
	if type(size) == "number" then
		size = { size }
	end

	local min = parent_size
	for _, v in ipairs(size) do
		local v = v <= 1 and (v * parent_size) or v
		min = math.min(min, v)
	end

	return math.ceil(min)
end

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

		local height = math.ceil(resolve_size(config.height, lines))
		local width = math.ceil(resolve_size(config.width, cols))

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

		vim.keymap.set("n", "q", function()
			if api.nvim_win_is_valid(win) then
				api.nvim_win_close(win, false)
			end
		end, { buffer = bufnr })

		local function close()
			if api.nvim_win_is_valid(win) and api.nvim_get_current_win() ~= win then
				api.nvim_win_close(win, false)
			end
		end

		vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
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

local active_buffers = {}

local function find_win(bufnr)
	local win = fn.bufwinid(bufnr)
	if win == -1 then
		return nil
	else
		return win
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
---@field on_output fun(task: Task)[]
---@field deferred_focus fun(task: Task)
---@field deps Task[]
---@field state TaskState
---@field code number|nil
---@field open_mode TermConfig
---@field last_use number|nil
---@field stdout string[]
---@field stderr string[]
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

function Task:restart()
	self:attach_callback(function()
		self:spawn()
	end)

	self:stop()
end

---@param start integer|nil
---@param endl integer|nil
---@return string[]
function Task:get_output(start, endl)
	if self.bufnr and api.nvim_buf_is_valid(self.bufnr) then
		return api.nvim_buf_get_lines(self.bufnr, start or 0, endl or -1, false)
	else
		return {}
	end
end

function Task:get_tail_output(count)
	if not self.bufnr or not api.nvim_buf_is_valid(self.bufnr) then
		return {}
	end

	local endl = api.nvim_buf_line_count(self.bufnr)
	local count = math.min(count, endl)

	local lines = {}

	-- Get last `count` lines and filter blank lines
	while #lines < count and endl > 0 do
		local remaining = count - #lines
		local req = api.nvim_buf_get_lines(self.bufnr, math.max(0, endl - remaining), endl, false)

		-- Move back the cursor
		endl = endl - remaining

		local idx = 1
		for _, line in ipairs(req) do
			if line:match("%S+") then
				table.insert(lines, idx, line)
				-- Only increment for matched lines
				idx = idx + 1
			end
		end
	end
	print("Got " .. #lines .. " lines")

	return lines
end

--- Creates a new task without running it
---
--- A key uniquely identifies a task
function Task:new(key, recipe)
	return setmetatable({
		key = key,
		recipe = recipe,
		state = TaskState.STOPPED,
		data = {},
		deps = {},
		on_exit = {},
		env = {},
		stdout = {},
		stderr = {},
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

---@return number|nil
---@param mode TermConfig
function Task:get_window(mode)
	local win = find_win(self.bufnr)
	if win then
		return win
	end

	if mode.global_terminal then
		for _, bufnr in pairs(active_buffers) do
			local win = find_win(bufnr)
			if win then
				vim.notify("Found open terminal with buffer: " .. bufnr)
				return win
			end
		end
	end
end

function Task:acquire_focused_win(config)
	local win = self:get_window(config)

	if win then
		-- Focus the window and buffer
		api.nvim_set_current_win(win)
		api.nvim_win_set_buf(win, self.bufnr)
		return win
	else
		return M.open_win(config, self.bufnr)
	end
end

function Task:open()
	self:spawn():focus({})
end

function Task:open_smart()
	self:spawn():focus({ kind = "smart", global_terminal = false })
end

function Task:open_float()
	self:spawn():focus({ kind = "float", global_terminal = false })
end

function Task:open_split()
	self:spawn():focus({ kind = "split", global_terminal = false })
end

function Task:open_vsplit()
	self:spawn():focus({ kind = "vsplit", global_terminal = false })
end

function Task:to_json()
	local json = self.recipe:to_json()

	vim.fn.setreg('"', json)
	vim.notify('Recipe copied to register @"\n\n' .. json)
end

function Task:menu()
	local func_map = {
		{ "Spawn", self.spawn },
		{ "Restart", self.restart },
		{ "Stop", self.stop },
		{ "Open", self.open },
		{ "Open Smart", self.open_smart },
		{ "Open Split", self.open_split },
		{ "Open Float", self.open_float },
		{ "Copy to json", self.to_json },
	}

	vim.ui.select(func_map, {
		format_item = function(item)
			return item[1]
		end,
	}, function(item)
		vim.notify("Selected: " .. item[1])
		item[2](self)
	end)
end

---@param mode TermConfig|nil
function Task:focus(mode)
	local function f()
		mode = vim.tbl_extend("keep", mode or {}, require("recipe.config").opts.term)

		local win = self:acquire_focused_win(mode)

		if config.opts.scroll_to_end then
			util.scroll_to_end(win)
		end

		active_buffers[self.bufnr] = self.bufnr
	end

	if self.bufnr and self.state ~= TaskState.PENDING then
		f()
	else
		self.deferred_focus = f
	end
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

	local prev_buf = self.bufnr
	local prev_win = prev_buf and find_win(prev_buf)

	-- Create a blank buffer for the terminal
	local bufnr = api.nvim_create_buf(false, false)
	api.nvim_create_autocmd({ "BufDelete" }, {
		buffer = bufnr,
		callback = function()
			vim.notify(string.format("Terminal buffer for %s closed", key))
			active_buffers[bufnr] = nil
		end,
	})
	self.bufnr = bufnr
	local recipe = self.recipe

	local env = vim.deepcopy(self.recipe.env or {})
	if vim.tbl_count(env) == 0 then
		env.__type = "table"
	end

	local uv = vim.loop

	local instances = components.instantiate(recipe)

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

		local on_output = components.collect_method(instances, "on_output")

		self.stdout = {}
		self.stderr = {}
		local handle_stdout, stdout_cleanup = util.handle_output(self.stdout, 10000)
		local handle_stderr, stderr_cleanup = util.handle_output(self.stderr, 10000)

		local on_stdout = function(_, lines)
			handle_stdout(lines)
			on_output(self)
		end
		local on_stderr = function(_, lines)
			handle_stderr(lines)
			on_output(self)
		end

		local start_time = uv.now()

		local function on_exit(_, code)
			self.jobnr = nil
			self.code = code
			self.state = TaskState.STOPPED

			stderr_cleanup()
			stdout_cleanup()

			if code == 0 and config.auto_close and fn.bufloaded(bufnr) == 1 then
				local win = find_win(bufnr)
				if win and api.nvim_win_is_valid(win) then
					api.nvim_win_close(win, false)
				end
			end

			local duration = (uv.now() - start_time)

			local level = (code == 0 and vim.log.levels.INFO) or vim.log.levels.ERROR

			local state = code == 0 and "Success" or string.format("Failure %d", code)

			local msg = string.format("%s: %q %s", state, key, util.format_time(duration))
			if not self:get_window({ global_terminal = false }) then
				vim.notify(msg, level)
			end

			for _, cb in ipairs(self.on_exit) do
				cb(self, code)
			end

			self.on_exit = {}
		end

		if err then
			util.log_error("Failed to execute dependency: " .. err)
			on_exit(nil, -1)
			return
		end

		self.deps = {}

		if config.opts.dotenv then
			local denv = require("recipe.dotenv").load(config.opts.dotenv)
			env = vim.tbl_extend("keep", env, denv)
		end

		self.env = env

		local cwd = vim.fn.fnamemodify(recipe.cwd, ":p")
		if vim.fn.isdirectory(cwd) ~= 1 then
			util.log_error("No such directory: " .. vim.inspect(cwd))
			on_exit(nil, -1)
			return
		end

		for _, hook in ipairs(config.opts.hooks.pre) do
			hook(recipe)
		end

		local cmd = self.recipe.cmd
		vim.notify("Running command: " .. vim.inspect(cmd) .. "\nEnv: " .. vim.inspect(env))
		if not recipe.components.plain then
			if type(cmd) == "string" then
				cmd = cmd:gsub("([%%#][:phtre]*)", fn.expand):gsub("(<%a+>[:phtre]*)", fn.expand)
			end
		end

		local err = ""

		local jobnr = -1
		vim.api.nvim_buf_call(self.bufnr, function()
			local success, j = pcall(fn.termopen, cmd, {
				cwd = cwd,
				on_exit = vim.schedule_wrap(on_exit),
				env = env,
				width = 80,
				height = 24,
				on_stdout = on_stdout,
				on_stderr = on_stderr,
			})

			if success then
				assert(j and j > 0, "Invalid job number")
				jobnr = j
			else
				assert(j, "Invalid error")
				err = j
			end
		end)

		if prev_win then
			vim.notify("Replacing previous terminal for task")
			api.nvim_win_set_buf(prev_win, self.bufnr)

			if config.opts.scroll_to_end then
				util.scroll_to_end(prev_win)
			end
		end

		if jobnr <= 0 then
			util.log_error(string.format("Failed to run command: %q\n\n%s", recipe:fmt_cmd(), err))
			on_exit(nil, -1)
			return
		end

		self.last_use = start_time
		self.state = TaskState.RUNNING
		self.jobnr = jobnr

		lib.push_recent(self)
		components.execute(instances, "on_start", self)
		self:attach_callback(function()
			components.execute(instances, "on_exit", self)
		end)

		if self.deferred_focus then
			self.deferred_focus(self)
			self.deferred_focus = nil
		end
	end, function() end)

	return self
end

return Task
