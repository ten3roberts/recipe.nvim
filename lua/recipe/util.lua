local M = {}
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
---@return fun(cb: fun()|nil)
function M.memoize_file(path, parse)
	path = uv.fs_realpath(path)

	local cache = nil
	return function(callback)
		if cache then
			callback(cache)
			return
		end

		if path == nil then
			callback(cache)
			return
		end

		util.read_file(path, function(data)
			M.watch_file(path, function()
				cache = nil
			end)

			local value = parse(data)

			cache = value
			callback(value)
		end)
	end
end

---comment
---@return fun(path: string, parse: fun(data: string|nil), callback: fun(value: any))
function M.memoize_files()
	local cache = {}

	return function(path, parse, callback)
		path = uv.fs_realpath(path)

		local cached = cache[path]
		if cached then
			callback(cached)
			return
		end

		if path == nil then
			local value = parse()

			callback(value)
			return
		end

		-- Load and parse the file

		M.read_file(
			path,
			vim.schedule_wrap(function(data)
				M.watch_file(path, function()
					vim.notify(path .. " changed")
					cache[path] = nil
				end)

				local value = parse(data)

				cache[path] = value
				callback(value)
			end)
		)
	end
end

return M
