local config = require("recipe.config")
local logger = require("recipe.logger")
local uv = vim.loop
local fn = vim.fn
local async = require("plenary.async")

local util = require("recipe.util")

local M = {}

---@type { [string]: Task }
---All currently running tasks
local tasks = {}

--- Stores recently run tasks
---@type Task[]
local recent_tasks = {}

local last_used = {}
M.last_used = last_used

---@param task Task
---@param pos Position|nil
function M.score(task, now, pos)
	local score = 0

	if task.last_use then
		score = score + 100000 - (now - task.last_use) / 1000
	end

	local dist = pos and task.recipe:distance_to(pos)
	if dist then
		score = score + 100 + math.max(100 - math.max(dist, 0), 0)
	end

	return score
end

function M.push_recent(task)
	if #recent_tasks > 16 then
		table.remove(recent_tasks, 0)
	end
	for i, v in ipairs(recent_tasks) do
		if v == task then
			table.remove(recent_tasks, i)
			break
		end
	end

	table.insert(recent_tasks, task)
end

--- Returns a list of tasks
function M.all_tasks()
	return tasks
end

---Returns a list of recent tasks
---@return Task[]
function M.recent()
	return recent_tasks
end

---@async
function M.load_cache()
	local cache = require("recipe.cache")

	local recipes = cache.load()

	logger.fmt_debug("Loaded %d recipes from cache", vim.tbl_count(recipes))
	for k, v in pairs(recipes) do
		M.insert_task(k, v)
	end
end

---@async
function M.save_cache()
	local cache = require("recipe.cache")

	local recipes = {}
	for k, v in pairs(tasks) do
		recipes[k] = v.recipe
	end

	cache.save(recipes)
	logger.fmt_debug("Saved %d recipes to cache", vim.tbl_count(recipes))
end

--- Loads recipes from providers into tasks
---@return table<string, Task>
function M.load()
	local providers = require("recipe.providers")
	local recipes = providers.load()
	for k, v in pairs(recipes) do
		M.insert_task(k, v)
	end

	async.run(function()
		M.save_cache()
	end)

	return tasks
end

---@param recipe Recipe
function M.insert_task(key, recipe)
	local Task = require("recipe.task")
	local key = key or recipe.label
	local task = tasks[key]

	if not task then
		logger.fmt_debug("Inserting recipe %s from %s", key, recipe.source or "")
		task = Task:new(key, recipe)
		tasks[key] = task
		return task
	elseif task.recipe.priority <= recipe.priority then
		logger.fmt_debug("Updating recipe %s from %s", key, task.recipe.source or "")
		-- Update the recipe
		task.recipe = recipe
		return task
	end
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
