local api = vim.api
local fn = vim.fn
local M = {}

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

	local height = math.ceil(config.height < 1 and config.height * lines or config.height)
	local width = math.ceil(config.width < 1 and config.width * cols or config.width)

	local row = math.ceil((lines - height) / 2 - cmdheight)
	local col = math.ceil((cols - width) / 2)

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
		vim.cmd("split")
		return vim.api.nvim_get_current_win()
	elseif config.kind == "vsplit" then
		vim.cmd("vsplit")
		return vim.api.nvim_get_current_win()
	elseif config.kind == "smart" then
		local font_lh_ratio = 0.3
		local w, h = api.nvim_win_get_width(0) * font_lh_ratio, api.nvim_win_get_height(0)
		local cmd = (w > h) and "vsplit" or "split"
		vim.cmd(cmd)
		return vim.api.nvim_get_current_win()
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

---@param key string
---@param recipe Recipe
---@param on_exit fun(code: number)
---@return Task
function M.execute(key, recipe, on_exit, win)
	local util = require("recipe.util")

	local bufnr = api.nvim_create_buf(false, true)

	---@type TermConfig
	local config = vim.tbl_deep_extend("force", require("recipe.config").opts.term, {})

	local info = {
		restarted = false,
		code = nil,
	}

	local last_term = terminals[key]
	if win == nil and last_term then
		win = find_win(last_term)
	end

	win = win or M.open_win(config, bufnr)

	api.nvim_set_current_win(win)
	api.nvim_win_set_buf(win, bufnr)

	terminals[key] = bufnr

	local function exit(_, code)
		if info.restarted then
			return
		end

		info.code = code

		if code == 0 and config.auto_close and fn.bufloaded(bufnr) == 1 then
			win = find_win(bufnr)
			if win and api.nvim_win_is_valid(win) then
				api.nvim_win_close(win, {})
			end
		end

		on_exit(code)
	end

	local oldbuf = api.nvim_get_current_buf()
	api.nvim_set_current_buf(bufnr)

	print("Opening term: ", vim.inspect(recipe))
	local id = fn.termopen(recipe.cmd, {
		cwd = recipe.cwd,
		on_exit = exit,
		env = recipe.env,
	})

	api.nvim_set_current_buf(oldbuf)

	if id <= 0 then
		util.error("Failed to start job")
		return on_start(nil)
	end

	info.running = true

	return {
		stop = function()
			fn.jobstop(id)
			fn.jobwait({ id }, 1000)
		end,
		restart = function(start, cb)
			info.restarted = true

			win = fn.bufwinid(bufnr)
			if win == -1 then
				win = nil
			end

			return M.execute(key, recipe, start, cb, win)
		end,
		focus = function()
			win = fn.bufwinid(bufnr)
			if win ~= -1 then
				api.nvim_set_current_win(win)
			elseif fn.bufloaded(bufnr) == 1 then
				win = M.open_win(config, bufnr)
				api.nvim_win_set_buf(win, bufnr)
			end
		end,
		recipe = recipe,
	}
end

function M.on_exit() end

return M
