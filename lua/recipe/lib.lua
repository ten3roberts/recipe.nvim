local config = require("recipe.config")
local term = require("recipe.adapters.term")
local uv = vim.loop
local fn = vim.fn

local util = require("recipe.util")

local M = {}

local async = require("plenary.async")
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

local last_used = {}
M.last_used = last_used

---Spawn a new task using the provided recipe
---This executes the task directly without regard for dependencies
---@param recipe Recipe
---@return Task
function M.spawn(recipe)
	if not recipe.components.plain and type(recipe.cmd) == "string" then
		recipe.cmd = recipe.cmd:gsub("([%%#][:phtre]*)", fn.expand):gsub("(<%a+>[:phtre]*)", fn.expand)
	end

	local key = recipe.name
	assert(type(key) == "string")
	local start_time = uv.hrtime()

	local function on_exit(_, code)
		tasks[key] = nil

		local duration = (uv.hrtime() - start_time) / 1000000

		local level = (code == 0 and vim.log.levels.INFO) or vim.log.levels.ERROR

		local state = code == 0 and "Success" or string.format("Failure %d", code)

		local msg = string.format("%s: %q %s", state, key, M.format_time(duration))
		vim.notify(msg, level)
	end

	for _, hook in ipairs(config.opts.hooks.pre) do
		hook(recipe)
	end

	-- Check if task is already running
	local task = tasks[key]
	-- Update env
	if task then
		vim.inspect("Found running task")
		return task
		-- local task = tasks[recipe.name]
		-- if recipe.components.restart then
		-- 	task = task.restart(on_exit)
		-- else
		-- 	table.insert(task.callbacks, callback or function(_) end)
		-- 	task.focus()
		-- 	return
		-- end
		-- Run the task as normal
	end
	vim.inspect("Running task")
	last_used[key] = vim.loop.hrtime() / 1e9

	--- Begin executing the task now
	local task = term.execute(recipe)
	task:attach_callback(on_exit)

	tasks[key] = task

	return task
end

---@return Task|nil
function M.get_task(name)
	return tasks[name]
end

---@return { [string]: Task }
function M.get_tasks()
	return tasks
end

function M.stop_all()
	for _, v in pairs(tasks) do
		v:stop()
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
