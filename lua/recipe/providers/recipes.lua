local util = require("recipe.util")
local Recipe = require("recipe.recipe")

---Provides recipes from the `recipes.json` file
---@class RecipesProvider : Provider
local provider = {
	memo = util.memoize_files(),
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
		local recipe = {
			name = key,
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
				local dep = recipes[v]

				if dep == in_progress then
					return nil, "Cyclic dependency"
				end

				-- Try parse it
				local value = json[v]
				if not dep and value then
					local r, err = parse_recipe(v, value)

					if r then
						recipes[v] = r
					else
						return nil, "Failed to parse dependency:\n" .. err
					end

					dep = r
				end

				if not dep then
					print("Recipes: ", vim.inspect(recipes))
					return nil, "Unresolved dependency: " .. v
				end

				table.insert(recipe.depends_on, dep)
			else
				if type(v) == "table" then
					local dep, err = parse_recipe(key .. ":dep." .. i, v)

					if not dep then
						return nil, "Failed to parse dependency:\n" .. err
					end

					dep.hidden = true
					recipes[dep.name] = dep

					table.insert(recipe.depends_on, dep)
				end
			end
		end

		-- Don't blindly merge
		recipe.cwd = value.cwd
		recipe.env = value.env
		recipe.components = value.components
		recipe.priority = value.priority

		return Recipe:new(recipe)
	end

	for key, value in pairs(json) do
		if not recipes[key] then
			recipes[key] = in_progress
			local recipe, err = parse_recipe(key, value)
			if recipe then
				recipes[key] = recipe
			else
				util.error("Failed to parse recipe: " .. key .. "\n" .. err)
				recipes[key] = nil
			end
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
