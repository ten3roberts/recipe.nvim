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

---Spawns and awaits the whole dependency tree of recipe
---@param recipe Recipe
---@return Task|nil, number|nil
---@async
function M.spawn_tree(recipe)
	local deps = {}
	for _, v in ipairs(recipe.depends_on or {}) do
		table.insert(deps, function()
			vim.notify("Executing dependency: " .. v:fmt_cmd())
			M.spawn_await(v, false)
		end)
	end

	-- Await all dependencies
	if #deps > 0 then
		async.util.join(deps)
	end

	return M.spawn_await(recipe, true)
end

---Spawn a new task using the provided recipe
---This executes the task directly without regard for dependencies
---@param recipe Recipe
---@param interactive boolean
---@return Task|nil
function M.spawn(recipe, interactive)
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
		if interactive then
			task.focus()
		end

		return task
		-- local task = tasks[recipe.name]
		-- if recipe.components.restart then
		-- 	vim.notify("Restarting " .. recipe.name)
		-- 	task = task.restart(on_exit)
		-- else
		-- 	table.insert(task.callbacks, callback or function(_) end)
		-- 	task.focus()
		-- 	return
		-- end
		-- Run the task as normal
	end

	local task = term.execute(recipe)

	if task == nil then
		util.error("Failed to launch : " .. vim.inspect(recipe))
		return
	end

	table.insert(task.callbacks, on_exit)

	tasks[key] = task

	return task
end

---Spawn a task using the provided recipe and await completion
---@param recipe Recipe
---@param interactive boolean
---@return Task|nil,number|nil
function M.spawn_await(recipe, interactive)
	local task = M.spawn(recipe, interactive)
	if not task then
		return
	end

	---@type Task, number
	local task, code = async.wrap(function(cb)
		table.insert(task.callbacks, cb)
	end, 1)()

	return task, code
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
