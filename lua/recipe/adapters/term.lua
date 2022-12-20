local async = require("plenary.async")
local api = vim.api
local fn = vim.fn
local M = {}

local components = require("recipe.components")

---@class term
---@field bufnr number
---@field win number
local term = {}

---Opens a new terminal
---@param config TermConfig
function M.open_win(config, bufnr)
	local lines = vim.o.lines
	local cols = vim.o.columns
	local cmdheight = vim.o.cmdheight

	print("Config: ", vim.inspect(config))
	local height = math.ceil(config.height < 1 and config.height * lines or config.height)
	local width = math.ceil(config.width < 1 and config.width * cols or config.width)

	local row = math.ceil((lines - height) / 2 - cmdheight)
	local col = math.ceil((cols - width) / 2)

	local function open_split(split)
		vim.cmd(split)
		local win = vim.api.nvim_get_current_win()
		api.nvim_win_set_buf(win, bufnr)
		return win
	end

	if config.kind == "float" then
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

local function acquire_win(key, config, bufnr)
	local existing = terminals[key]
	local win

	if existing then
		vim.notify("Existing terminal buffer")
		win = find_win(existing)
	end

	if win then
		vim.notify("Found open terminal window for " .. key)
		-- Focus the window and buffer
		api.nvim_set_current_win(win)
		api.nvim_win_set_buf(win, bufnr)
		return win
	else
		vim.notify("Opening new window for " .. key)
		return M.open_win(config, bufnr)
	end
end

---@param recipe Recipe
---@return Task|nil
function M.execute(recipe)
	local util = require("recipe.util")

	local config = require("recipe.config")

	---@type TermConfig
	local term_config = vim.tbl_deep_extend("force", require("recipe.config").opts.term, {})

	local key = recipe.name

	-- Create a blank buffer for the terminal
	local bufnr = api.nvim_create_buf(false, true)

	local task = { recipe = recipe, data = {}, bufnr = bufnr, callbacks = {} }

	-- Attempt to reuse window or open a new one
	local win = acquire_win(key, term_config, bufnr)

	-- Do this afterwards to be able to look up the old buffer
	terminals[key] = bufnr
	assert(api.nvim_win_get_buf(win) == bufnr, "Returned window does not display the terminal buffer")
	local env = vim.deepcopy(recipe.env) or {}
	env.__type = "table"

	async.run(function()
		if config.opts.dotenv then
			local denv = require("recipe.dotenv").load(config.opts.dotenv)
			env = vim.tbl_extend("keep", env, denv)
		end

		async.util.scheduler()

		local on_stdout, stdout_cleanup = util.curry_output("on_output", task)
		local on_stderr, stderr_cleanup = util.curry_output("on_output", task)

		local function on_exit(_, code)
			stdout_cleanup()
			stderr_cleanup()

			components.execute(recipe.components, "on_exit", task)
			if code == 0 and config.auto_close and fn.bufloaded(bufnr) == 1 then
				local win = find_win(bufnr)
				if win and api.nvim_win_is_valid(win) then
					api.nvim_win_close(win, {})
				end
			end

			for _, cb in ipairs(task.callbacks) do
				cb(task, code)
			end
		end

		local jobnr = fn.termopen(recipe.cmd, {
			cwd = recipe.cwd,
			on_exit = vim.schedule_wrap(on_exit),
			env = env,
			on_stdout = on_stdout,
			on_stderr = on_stderr,
		})

		if jobnr <= 0 then
			util.error("Failed to start job")
			return
		end

		components.execute(recipe.components, "on_start", task)

		-- Update the task
		task.running = true
		task.stop = function()
			fn.jobstop(jobnr)
			fn.jobwait({ jobnr }, 1000)
		end

		task.restart = function()
			fn.jobstop(jobnr)
			fn.jobwait({ jobnr }, 1000)

			return M.execute(recipe)
		end

		task.focus = function()
			local win = fn.bufwinid(bufnr)
			if win ~= -1 then
				api.nvim_set_current_win(win)
			elseif fn.bufloaded(bufnr) == 1 then
				win = M.open_win(term_config, bufnr)
				api.nvim_win_set_buf(win, bufnr)
			end
		end

		if term_config.jump_to_end then
			vim.schedule(function()
				util.scroll_to_end(win)
			end)
		end
	end, function() end)

	return task
end

function M.on_exit() end

return M
