local M = {}
local async = require("plenary.async")
local fn = vim.fn

function M.get_compiler(cmd)
	local rtp = vim.o.rtp
	for part in cmd:gmatch("%w*") do
		local compiler = fn.findfile("compiler/" .. part .. ".vim", rtp)
		if compiler ~= "" then
			return part
		end
	end
end

---@param title string
---@param compiler string|nil
---@param data string[]
---@param open boolean|nil
function M.vim_qf(title, compiler, data, open)
	if not open then
		vim.fn.setqflist({}, "r", {})
		vim.cmd("cclose")
		return
	end

	local old_c = vim.b.current_compiler

	local old_efm = vim.opt.efm

	local old_makeprg = vim.o.makeprg

	if compiler ~= nil then
		vim.cmd("compiler! " .. compiler)
	end

	if #data == 1 and data[1] == "" then
		return
	end

	vim.fn.setqflist({}, "r", { title = title, lines = data })
	vim.cmd("copen | wincmd p")

	vim.b.current_compiler = old_c
	vim.opt.efm = old_efm
	vim.o.makeprg = old_makeprg
	if old_c ~= nil then
		vim.cmd("compiler " .. old_c)
	end
end

---@param title string
---@param compiler string|nil
---@param data string[]
---@param open boolean|nil
function M.nvim_qf(title, compiler, data, open)
	if compiler ~= nil then
		vim.cmd("compiler! " .. compiler)
	end

	if #data == 1 and data[1] == "" then
		return
	end

	require("qf").set("c", {
		title = title,
		compiler = compiler,
		lines = data,
		tally = true,
		open = open,
	})
end

local has_qf = pcall(require, "qf")

if has_qf then
	M.qf = M.nvim_qf
else
	M.qf = M.vim_qf
end

function M.notify(data, cmd)
	local s = table.concat(data, "\n")
	vim.notify(string.format("%q:\n%s", cmd, s))
end

local uv = vim.loop

function M.error(msg)
	vim.notify(msg, vim.log.levels.ERROR)
end

---@param path string
---@param callback fun(data: string|nil)
function M.read_file(path, callback)
	uv.fs_open(path, "r", 438, function(err, fd)
		if err then
			return callback()
		end
		uv.fs_fstat(fd, function(err, stat)
			assert(not err, err)
			uv.fs_read(fd, stat.size, 0, function(err, data)
				assert(not err, err)
				uv.fs_close(fd, function(err)
					assert(not err, err)
					return callback(data)
				end)
			end)
		end)
	end)
end

---@async
---@param path string
---@return string|nil, string|nil
function M.read_file_async(path)
	local err, fd = async.uv.fs_open(path, "r", 438)
	assert(not err, err)
	if err then
		return nil, err
	end

	local err, stat = async.uv.fs_fstat(fd)
	if err then
		return nil, err
	end

	local err, data = async.uv.fs_read(fd, stat.size, 0)
	if err then
		return nil, err
	end

	local err = async.uv.fs_close(fd)
	if err then
		return nil, err
	end

	return data, nil
end

--- @diagnostic disable
function M.write_file(path, data, callback)
	uv.fs_open(path, "w", 438, function(err, fd)
		assert(not err, err)
		uv.fs_write(fd, data, 0, function(err)
			assert(not err, err)
			uv.fs_close(fd, function(err)
				assert(not err, err)
				return callback()
			end)
		end)
	end)
end

---Execute `callback` when path changes.
---If callback return `false` the watch is stopped
---@param path string
---@param callback fun(err, filename, event)
function M.watch_file(path, callback)
	local w = uv.new_fs_event()
	path = uv.fs_realpath(path)
	w:start(path, {}, function(...)
		if callback(...) ~= true then
			w:stop()
		end
	end)
end

---@param path string
---@param parse fun(string): any
---@return async fun(): string|nil
function M.memoize_file(path, parse)
	path = async.uv.fs_realpath(path)

	local cache = nil
	return function()
		if cache then
			return cache
		end

		if path == nil then
			return nil
		end

		local data, err = M.read_file_async(path)

		M.watch_file(path, function()
			cache = nil
		end)

		local value = parse(data)

		cache = value
		return value
	end
end

---@generic T
---@return fun(path: string, parse: fun(data: string|nil, path: string|nil): T): T, boolean
function M.memoize_files()
	local cache = {}

	---@async
	return function(path, parse)
		async.util.scheduler()
		local path = vim.loop.fs_realpath(path)
		-- local path = async.wrap(function(cb)
		-- 	vim.loop.fs_realpath(path, cb)
		-- end, 1)()

		local cached = cache[path]
		if cached then
			return cached, false
		end

		if path == nil then
			return parse(), true
		end

		-- Load and parse the file

		local data, _ = M.read_file_async(path)

		M.watch_file(path, function()
			vim.notify(path .. " changed")
			cache[path] = nil
		end)

		async.util.scheduler()
		local value = parse(data, path)

		cache[path] = value
		return value, true
	end
end

local charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890"
function M.random_name()
	local s = ""
	for _ = 1, 16 do
		local i = math.random(1, #charset)
		local c = charset:sub(i, i)
		s = s .. c
	end
	return s
end

function M.remove_escape_codes(s)
	-- from: https://stackoverflow.com/questions/48948630/lua-ansi-escapes-pattern
	local ansi_escape_sequence_pattern = "[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]"

	return s:gsub(ansi_escape_sequence_pattern, ""):gsub("\r", "")
end

local remove_escape_codes = M.remove_escape_codes

function M.curry_output(method, task)
	local components = require("recipe.components")
	local prev_line = ""
	local on_output = components.collect_method(task.recipe, method)

	return function(_, lines)
		on_output(task)
	end, function() end
end

--from https://github.com/stevearc/overseer.nvim/blob/82ed207195b58a73b9f7d013d6eb3c7d78674ac9/lua/overseer/util.lua#L119
---@param win number
function M.scroll_to_end(win)
	local bufnr = vim.api.nvim_win_get_buf(win)
	local lnum = vim.api.nvim_buf_line_count(bufnr)
	local last_line = vim.api.nvim_buf_get_lines(bufnr, -2, -1, true)[1]
	-- Hack: terminal buffers add a bunch of empty lines at the end. We need to ignore them so that
	-- we don't end up scrolling off the end of the useful output.
	-- This has the unfortunate effect that we may not end up tailing the output as more arrives
	if vim.bo[bufnr].buftype == "terminal" then
		local half_height = math.floor(vim.api.nvim_win_get_height(win) / 2)
		for i = lnum, 1, -1 do
			local prev_line = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, true)[1]
			if prev_line ~= "" then
				-- Only scroll back if we detect a lot of padding lines, and the total real output is
				-- small. Otherwise the padding may be legit
				if lnum - i >= half_height and i < half_height then
					lnum = i
					last_line = prev_line
				end
				break
			end
		end
	end
	vim.api.nvim_win_set_cursor(win, { lnum, vim.api.nvim_strwidth(last_line) })
end

return M
