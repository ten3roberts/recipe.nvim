local util = require("recipe.util")
local Recipe = require("recipe.recipe")
---@class RecipesProvider : Provider
---Provides recipes from the `recipes.json` file
local provider = {
	memo = util.memoize_files(),
}

---@return RecipeStore|nil
local function parse_targets(data)
	if data == nil then
		return nil
	end
	data = data or ""

	local result = {}

	for line in data:gmatch("[^\n]+") do
		local target = string.match(line, "^([A-Za-z0-9-_]+):")
		if target then
			local recipe = Recipe:new({
				cmd = "make " .. target,
				adapter = "build",
				name = target,
			})

			result[target] = recipe
		end
	end

	return result
end

---@async
---@param path string
---@return RecipeStore
function provider.load(path)
	local recipes = (provider.memo)(path .. "/" .. "Makefile", parse_targets)
		or (provider.memo)(path .. "/" .. "makefile", parse_targets)
		or {}

	return recipes
end

local M = {}
function M.setup()
	require("recipe.providers").register("make", provider)
end
return M
