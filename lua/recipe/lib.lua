local config = require("recipe.config")
local uv = vim.loop
local fn = vim.fn

local util = require("recipe.util")

local M = {}

function M.format_time(ms)
	local d, h, m, s = 0, 0, 0, 0
	d = math.floor(ms / 86400000)
	ms = ms % 86400000

	h = math.floor(ms / 3600000)
	ms = ms % 3600000

	m = math.floor(ms / 60000)
	ms = ms % 60000

	s = math.floor(ms / 1000)
	ms = math.floor(ms % 1000)

	local t = {}
	if d > 0 then
		t[#t + 1] = d .. "d"
	end
	if h > 0 then
		t[#t + 1] = h .. "h"
	end
	if m > 0 then
		t[#t + 1] = m .. "m"
	end
	if s > 0 then
		t[#t + 1] = s .. "s"
	end

	return table.concat(t, " ")
end

---@type { [string]: Task }
local tasks = {}

--- Spawns a recipe
---@param key string
---@param recipe Recipe
---@param callback fun(code: number)|nil
function M.spawn(key, recipe, callback)
	local adapters = config.opts.adapters
	recipe.cmd = recipe.plain and recipe.cmd
		or recipe.cmd:gsub("([%%#][:phtre]*)", fn.expand):gsub("(<%a+>[:phtre]*)", fn.expand)

	local start_time = uv.hrtime()

	local function on_exit(code)
		local task = tasks[key]
		tasks[key] = nil

		local duration = (uv.hrtime() - start_time) / 1000000

		local level = code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR

		local state = code == 0 and "Success" or string.format("Failure %d", code)

		vim.notify(string.format("%s: %q %s", state, recipe.cmd:sub(1, 32), M.format_time(duration)), level)
		for _, cb in ipairs(task.callbacks) do
			cb(code)
		end
	end

	for _, hook in ipairs(config.opts.hooks.pre) do
		hook(recipe)
	end

	local adapter = adapters[recipe.kind]
	if adapter == nil then
		vim.notify(string.format("Invalid adapter: %s", recipe.kind), vim.log.levels.ERROR)
		return
	end

	local function on_start(task)
		task.recipe = recipe
		tasks[key] = task

		if task == nil then
			util.error("Failed to launch : " .. vim.inspect(recipe))
			return
		end

		task.callbacks = { callback or function(_) end }
	end

	-- Check if task is already running
	if tasks[key] then
		local task = tasks[key]
		if recipe.restart then
			vim.notify("Restarting " .. key)
			tasks[key] = task.restart(on_start, on_exit)
			return
		else
			vim.notify("Focusing " .. key)
			table.insert(task.callbacks, callback or function(_) end)
			task.focus()
			return
		end
	end

	if config.opts.dotenv then
		require("recipe.dotenv").load(config.opts.dotenv, function(env)
			recipe.env = vim.tbl_extend("keep", recipe.env or {}, env)
			vim.notify("Spawning: " .. recipe.cmd)
			adapter.execute(key, recipe, on_start, on_exit)
		end)
	else
		vim.notify("Spawning: " .. recipe.cmd)
		adapter.execute(key, recipe, on_start, on_exit)
	end
end

local success_codes = {
	[0] = true,
	[130] = true, -- SIGINT
	[129] = true, -- SIGTERM
}

M.success_codes = success_codes

---@return Task|nil
function M.get_task(name)
	return tasks[name]
end

---@return { [string]: Task }
function M.get_tasks()
	return tasks
end

function M.stop_all()
	for k, v in pairs(tasks) do
		vim.notify("Stopping: " .. k)
		v.stop()
	end
end

local trusted_paths = nil
local trusted_paths_dir = fn.stdpath("cache") .. "/recipe"
local trusted_path = trusted_paths_dir .. "/trusted_paths.json"

function M.trusted_paths(callback)
	if trusted_paths then
		return callback(trusted_paths)
	end

	util.read_file(
		trusted_path,
		vim.schedule_wrap(function(data)
			trusted_paths = data and fn.json_decode(data) or {}
			callback(trusted_paths)
		end)
	)
end

function M.is_trusted(path, callback)
	path = fn.fnamemodify(path, ":p")
	M.trusted_paths(function(paths)
		callback(paths[path] == fn.getftime(path))
	end)
end

function M.trust_path(path, callback)
	path = fn.fnamemodify(path, ":p")

	M.trusted_paths(function(paths)
		local mtime = fn.getftime(path)

		paths[path] = mtime
		fn.mkdir(trusted_paths_dir, "p")
		local data = fn.json_encode(trusted_paths)
		util.write_file(trusted_path, data, callback)
		if callback then
			callback()
		end
	end)
end

return M
