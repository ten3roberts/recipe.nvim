---@class CustomProvider: Provider
local provider = {}
local Recipe = require("recipe.recipe")

local M = { recipes = {} }

function M.setup(recipes)
	for k, v in pairs(recipes) do
		v = Recipe:new(v)
		v.name = k
		v.source = "custom"
		M.recipes[k] = v
	end

	require("recipe").register("custom", provider)
end

function provider.load(_)
	local config = require("recipe.config")
	return config.opts.custom_recipes.global
end

return M
