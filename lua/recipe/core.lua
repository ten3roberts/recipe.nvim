---@alias RecipeStore table<string, Recipe>
local util = require("recipe.util")

---@class Recipe
---@field cmd string|string[]
---@field cwd string
---@field env table<string, string>
---@field source string
---@field name string
---@field adapter string
---@field components table<string, any>
---@field priority string
local Recipe = {}

Recipe.__index = Recipe
local config = require("recipe.config")

--- Creates a new recipe
---@return Recipe
function Recipe:new(o)
	o.components = o.components or {}
	for k, v in pairs(config.opts.default_components) do
		if o.components[k] == nil then
			o.components[k] = v
		end
	end
	o.name = o.name or (type(o.cmd) == "string" and o.cmd or table.concat(o.cmd, " ")) or util.random_name()
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

---@return string
function Recipe:fmt_cmd()
	if type(self.cmd) == "table" then
		return table.concat(self.cmd, " ")
	else
		return self.cmd
	end
end

function Recipe:format(padding)
	local cmd = self:fmt_cmd()

	return string.format("%s%s - %s %s", self.name, padding, self.source, cmd)
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
