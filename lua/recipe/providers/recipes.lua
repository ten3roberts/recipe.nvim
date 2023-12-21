local util = require("recipe.util")
local Recipe = require("recipe.recipe")

---Provides recipes from the `recipes.json` file
---@class RecipesProvider : Provider
local provider = {
	memo = util.memoize_files(vim.secure.read),
	discovered = {},
}

---@return RecipeStore
local function parse_recipes(data, path)
	data = data or "{}"
	local ok, json = pcall(vim.json.decode, data)
	assert(json)
	if not ok then
		util.log_error(string.format("Failed to read recipes file: %s", json))
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
			label = key,
			source = nil,
			depends_on = {},
		}

		-- if not value.cmd then
		-- 	return nil, "Missing field `cmd`"
		-- end

		recipe.cmd = value.cmd

		-- Resolve dependencies
		for i, v in ipairs(value.depends_on or value.dependencies or {}) do
			if type(v) == "string" then
				-- local dep, err = parse_recipe(v, v)
				-- if not dep then
				-- 	return nil, "Failed to parse dependency:\n" .. err
				-- end

				table.insert(recipe.depends_on, v)
			elseif type(v) == "table" then
				-- Anonymous recipe
				local child_key = key .. ":dep." .. i
				local dep, err = parse_recipe(child_key, v)

				if not dep then
					return nil, "Failed to parse dependency:\n" .. err
				end

				dep.hidden = true

				table.insert(recipe.depends_on, child_key)
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
			util.log_error("Failed to parse recipe: " .. key .. "\n" .. err)
			recipes[key] = nil
		end
	end

	return recipes
end

---@async
---@param path string
---@return RecipeStore
function provider.load(path)
	local logger = require("recipe.logger")
	local config = require("recipe.config")
	local current = path .. "/" .. config.opts.recipes_file
	provider.discovered = vim.tbl_filter(function(v)
		return v ~= current
	end, provider.discovered)

	table.insert(provider.discovered, current)

	local recipes = {}
	for i, path in ipairs(provider.discovered) do
		local source = "recipe " .. vim.fn.fnamemodify(path, ":p:.:h")
		require("recipe.logger").fmt_info("Loading recipes from %s: %s", path, source)

		local res = (provider.memo)(path, parse_recipes)
		logger.fmt_info("Loaded recipes from %d:[%s]: %d", i, path, vim.tbl_count(res))
		for k, v in pairs(res) do
			v.source = source
			recipes[k] = v
		end
	end

	return recipes
end

local M = {}
function M.setup() end
require("recipe.providers").register("recipes", provider)
return M
