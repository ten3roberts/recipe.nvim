---@alias RecipeStore table<string, Recipe>
local util = require("recipe.util")

---@class Recipe
---@field source string
---@field name string
---@field adapter string
---@field components table<string, any>
---@field priority string
local Recipe = {}

Recipe.__index = Recipe

--- Creates a new recipe
---@return Recipe
function Recipe:new(o)
	o.components = o.components or {}
	o.name = o.name or o.cmd or util.random_name()
	o.cwd = o.cwd or vim.fn.getcwd()
	o.priority = o.priority or 1000
	return setmetatable(o, self)
end

---Adds a new component to the recipe
---@param value Component
---@return Recipe
function Recipe:add_component(type, value)
	self.components[type] = value
	return self
end

function Recipe:has_component(type)
	return self.components[type] ~= nil
end

---@class Component
---@field type string

return {
	Recipe = Recipe,
	components = {
		Reset = true,
	},
}
