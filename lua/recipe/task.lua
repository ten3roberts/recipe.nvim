local logger = require("recipe.logger")
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

		-- vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
		-- 	callback = function()
		-- 		vim.defer_fn(close, 100)
		-- 	end,
		-- 	buffer = bufnr,
		-- })

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
---@field bufnr number|nil The buffer containing the process output
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
	require("recipe.logger").info("state: ", self.state)
	if self.state == TaskState.STOPPED then
		require("recipe.logger").info("attach_callback ready")
		vim.schedule(function()
			cb(self, self.code)
		end)
	else
		table.insert(self.on_exit, cb)
	end
end
function Task:stop_async()
	local t = {}
	for _, dep in ipairs(self.deps) do
		table.insert(t, function()
			dep:stop_async()
		end)
	end

	if #t > 0 then
		async.util.join(t)
	end

	if self.jobnr then
		fn.jobstop(self.jobnr)
	end

	self:join()
end

---@async
function Task:stop()
	async.run(function()
		self:stop_async()
	end)
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

	for _, window in ipairs(windows or {}) do
		api.nvim_win_close(window, true)
	end
end

---@return number|nil
---@param mode TermConfig
function Task:find_window(mode)
	for _, winid in pairs(vim.api.nvim_list_wins()) do
		local bufnr = api.nvim_win_get_buf(winid)
		logger.fmt_info("win: %d buf: %d", winid, bufnr or "-1")
		local task_info = vim.b[bufnr].recipe_task_info

		if task_info then
			if task_info.key == self.key or mode.global_terminal then
				logger.fmt_info(
					"[%s == %s] %s Found open terminal with buffer %d",
					self.key,
					task_info.key,
					vim.inspect(mode),
					bufnr or -1
				)
				return winid
			end
		end
	end

	logger.fmt_info("No open terminal found for %s", self.recipe.label)
end

function Task:acquire_focused_win(config)
	logger.fmt_info("acquire_focused_win %s", self.key)
	local win = self:find_window(config)

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
	local content = vim.json.encode(self.recipe:to_json())

	vim.fn.setreg('"', content)
	vim.notify('Recipe copied to register @"\n\n' .. content)
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
		item[2](self)
	end)
end

---@param mode TermConfig|nil
function Task:focus(mode)
	local function f()
		if not self.recipe.cmd then
			return
		end

		logger.fmt_info("Focusing %s", self.key)
		mode = vim.tbl_extend("keep", mode or {}, require("recipe.config").opts.term)

		local win = self:acquire_focused_win(mode)

		if config.opts.scroll_to_end then
			util.scroll_to_end(win)
		end
	end

	if #self.deps > 0 then
		for _, dep in ipairs(self.deps) do
			dep:focus(mode)
		end

		self.deferred_focus = f
	elseif self.bufnr and self.state ~= TaskState.PENDING then
		-- Focus immediately
		f()
	else
		self.deferred_focus = f
	end
end

Task._tostring = Task.format

---@type fun(): Task, number
Task.join = async.wrap(Task.attach_callback, 2)

---Starts executing the task
function Task:spawn(opts)
	opts = opts or {}
	if self.state ~= TaskState.STOPPED then
		return self
	end

	local logger = require("recipe.logger")
	logger.info("Spawning task " .. self.key)

	self.data = {}
	self.deps = {}
	self.state = TaskState.PENDING

	---@type TermConfig
	-- local term_config = vim.tbl_deep_extend("force", require("recipe.config").opts.term, {})

	local key = self.recipe.label

	-- Create a blank buffer for the terminal
	local recipe = self.recipe

	local env = vim.deepcopy(self.recipe.env or {})
	if vim.tbl_count(env) == 0 then
		env.__type = "table"
	end

	local uv = vim.loop

	local instances = components.instantiate(self)

	async.run(function()
		--- Run dependencies
		local deps = {}
		local err
		local lib = require("recipe.lib")

		for _, v in ipairs(recipe.depends_on or {}) do
			local child_task = lib.get_task(v)
			if not child_task then
				err = string.format("No such task: %s", v)
				break
			end

			logger.fmt_info("Running dependency %s", child_task:format())
			local child = child_task:spawn({ call_hidden = true })

			table.insert(self.deps, child)
			table.insert(deps, function()
				local _, code = child:join()
				if code ~= 0 then
					err = string.format("%s exited with code: %s", v, code)
				end
			end)
		end

		-- Await all dependencies
		if #deps > 0 then
			logger.fmt_info("Waiting for %d dependencies to finish", #deps)
			async.util.join(deps)
		end

		self.deps = {}

		local bufnr

		if recipe.cmd then
			bufnr = api.nvim_create_buf(false, false)

			logger.fmt_info("Opened buffer for task %s %d", self.key, bufnr)
			vim.b[bufnr].recipe_task_info = {
				recipe = self.recipe,
				key = self.key,
				label = self.recipe.label,
			}

			self.bufnr = bufnr
		end

		local start_time = uv.now()
		local function on_exit(_, code)
			logger.fmt_info("Task %s exited", self.key)
			self.jobnr = nil
			self.code = code
			self.state = TaskState.STOPPED

			if code == 0 and config.auto_close and bufnr and fn.bufloaded(bufnr) == 1 then
				local win = find_win(bufnr)
				if win and api.nvim_win_is_valid(win) then
					api.nvim_win_close(win, false)
				end
			end

			local duration = (uv.now() - start_time)

			local level = (code == 0 and vim.log.levels.INFO)
				or (code == 128 and vim.log.levels.INFO)
				or vim.log.levels.ERROR

			if code == 129 then
				local state = code == 0 and "Success" or string.format("Failure %d", code)

				local msg = string.format("%s: %q %s", state, key, util.format_time(duration))
				if not self:find_window({ global_terminal = false }) then
					vim.notify(msg, level)
				end
			end

			for i, cb in ipairs(self.on_exit) do
				logger.fmt_info("Running on_exit callback %d", i)
				cb(self, code)
			end

			self.on_exit = {}
		end

		if err then
			util.log_error("Failed to execute dependency: " .. err)
			on_exit(nil, -1)
			return
		end

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

		for i, hook in ipairs(config.opts.hooks.pre) do
			logger.fmt_info("Running pre hook %d", i)
			pcall(hook, recipe)
		end

		local cmd = self.recipe.cmd

		local function replace_expand(s)
			return s:gsub("([%%#][:phtre]*)", fn.expand):gsub("(<%a+>[:phtre]*)", fn.expand)
		end

		-- logger.fmt_info("Running command: %q\nenv: %s", vim.inspect(cmd), vim.inspect(env))
		if not recipe.components.plain then
			if type(cmd) == "string" then
				cmd = replace_expand(cmd)
			elseif type(cmd) == "table" then
				cmd = vim.tbl_map(replace_expand, cmd)
			end
		end

		local err = ""

		local jobnr = nil

		if cmd then
			local on_output = components.collect_method(instances, "on_output")
			local on_stdout = components.collect_method(instances, "on_stdout")
			local on_stderr = components.collect_method(instances, "on_stderr")

			local on_stdout = function(_, lines)
				on_stdout(self, lines)
				on_output(self)
			end

			local on_stderr = function(_, lines)
				on_stderr(self, lines)
				on_output(self)
			end

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

			local prev_win = self:find_window({ global_terminal = false })
			if prev_win then
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

			if self.deferred_focus then
				vim.schedule(function()
					self.deferred_focus(self)
					self.deferred_focus = nil
				end)
			end
		else
			vim.schedule(function()
				on_exit(nil, 0)
			end)
		end

		if not opts.call_hidden then
			self.last_use = start_time
		end

		self.state = TaskState.RUNNING
		self.jobnr = jobnr

		lib.push_recent(self)
		components.execute(instances, "on_start", self)
		self:attach_callback(function()
			components.execute(instances, "on_exit", self)
		end)
	end, function() end)

	return self
end

return Task
