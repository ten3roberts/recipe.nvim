local util = require("recipe.util")
local core = require("recipe.core")
---@class RecipesProvider : Provider
---Provides recipes from the `recipes.json` file
local provider = {
	memo = util.memoize_files(),
}

---@return RecipeStore
local function parse_recipes(data)
	data = data or "{}"
	local ok, json = pcall(vim.json.decode, data)
	if not ok then
		util.error(string.format("Failed to read recipes file: %s", json))
		return {}
	end

	local recipes = {}

	for key, value in pairs(json) do
		local recipe = core.Recipe:new(vim.tbl_extend("force", value, { name = key, source = "recipes" }))
		recipes[key] = recipe
	end

	return recipes
end

---@async
---@param path string
---@return RecipeStore
function provider.load(path)
	local config = require("recipe.config")
	local recipes = (provider.memo)(path .. "/" .. config.opts.recipes_file, parse_recipes)
	return recipes
end

local M = {}
function M.setup() end
require("recipe").register("recipes", provider)
return M
