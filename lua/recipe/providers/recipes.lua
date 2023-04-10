local util = require("recipe.util")
local Recipe = require("recipe.recipe")

---Provides recipes from the `recipes.json` file
---@class RecipesProvider : Provider
local provider = {
	memo = util.memoize_files(vim.secure.read),
}

---@return RecipeStore
local function parse_recipes(data, path)
	data = data or "{}"
	local ok, json = pcall(vim.json.decode, data)
	if not ok then
		util.error(string.format("Failed to read recipes file: %s", json))
		return {}
	end

	local recipes = {}
	local in_progress = {}

	local function parse_recipe(key, value)
		if type(value) == "string" then
			local recipe = recipes[value]

			-- Already parsed and loaded
			if recipe == in_progress then
				return nil, "Cyclic dependency"
			elseif recipe then
				recipes[key] = recipe
				return recipe
			end

			-- Not loaded yet

			-- Try parse it
			local j = json[value]
			if not j then
				return nil, "Unresolved dependency: " .. value
			end

			local recipe, err = parse_recipe(value, j)

			if not recipe then
				return nil, "Failed to parse dependency:\n" .. err
			end

			--- Insert the alias name as well
			recipes[key] = recipe
			return recipe
		end

		local recipe = {
			key = key,
			source = vim.fn.fnamemodify(path, ":p:."),
			depends_on = {},
		}

		if not value.cmd then
			return nil, "Missing field `cmd`"
		end

		recipe.cmd = value.cmd

		-- Resolve dependencies
		for i, v in ipairs(value.depends_on or value.dependencies or {}) do
			if type(v) == "string" then
				local dep, err = parse_recipe(v, v)
				if not dep then
					return nil, "Failed to parse dependency:\n" .. err
				end

				table.insert(recipe.depends_on, dep)
			elseif type(v) == "table" then
				-- Anonymous recipe
				local dep, err = parse_recipe(key .. ":dep." .. i, v)

				if not dep then
					return nil, "Failed to parse dependency:\n" .. err
				end

				dep.hidden = true

				table.insert(recipe.depends_on, dep)
			end
		end

		-- Don't blindly merge
		recipe.cwd = value.cwd
		recipe.env = value.env
		recipe.components = value.components
		recipe.priority = value.priority

		local recipe = Recipe:new(recipe)
		recipes[key] = recipe
		return recipe
	end

	for key, value in pairs(json) do
		recipes[key] = in_progress
		local recipe, err = parse_recipe(key, value)

		if not recipe then
			util.error("Failed to parse recipe: " .. key .. "\n" .. err)
			recipes[key] = nil
		end
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
require("recipe.providers").register("recipes", provider)
return M
