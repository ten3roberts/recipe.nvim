local logger = require("recipe.logger")
local async = require("plenary.async")
local util = require("recipe.util")
local Recipe = require("recipe.recipe")
---@alias ProviderCache table<string, Recipe>

---@class Cache
---@field scope string
---@field path string
local cache = {}

local M = {}

local function parse_recipes(data)
	local recipes = {}
	for k, v in pairs(data) do
		local recipe = Recipe:from_json(v)
		recipe.from_cache = true
		recipe.priority = -1
		recipes[k] = recipe
	end
	return recipes
end

---@param scope string
---@return string
local function escape_scope(scope)
	local s = scope:gsub(" ", "%%"):gsub("\\", "%%"):gsub("/", "%%")
	return s
end

local function get_cache_path(scope)
	local path = vim.fn.stdpath("state") .. "/recipe"
	vim.fn.mkdir(path, "p")
	return path .. "/" .. escape_scope(scope) .. ".json"
end

---@async
---@return table<string, Recipe>
function M.load()
	local scope = vim.loop.fs_realpath(vim.fn.getcwd())
	local path = get_cache_path(scope)

	cache.scope = scope
	cache.path = path

	logger.fmt_debug("Loading recipes from %q", path)
	if vim.loop.fs_realpath(path) == nil then
		logger.fmt_debug("No recipes found at %q", path)
		return {}
	end

	local content, err = util.read_file_async(path)
	if not content then
		logger.fmt_error("Failed to load %q: %s", path, err)
		return {}
	end

	local ok, data = pcall(vim.json.decode, content)
	if not ok then
		util.log_error(string.format("Failed to read recipes file: %s", data))
		return {}
	end

	assert(data)

	async.util.scheduler()
	local recipes = parse_recipes(data.recipes)

	cache.scope = scope
	cache.path = path

	return recipes
end

---@param recipes table<string, Recipe>
function M.save(recipes)
	local path = cache.path
	if not path then
		return
	end

	local recipes_data = {}
	for k, v in pairs(recipes) do
		recipes_data[k] = v:to_json()
	end
	local data = { recipes = recipes_data }

	local json = vim.json.encode(data)

	logger.fmt_debug("Writing recipes to %q", path)
	local err = util.write_file_async(path, json)
	if err then
		util.log_error(string.format("Failed to write recipes file: %s", err))
	end
end

return M
