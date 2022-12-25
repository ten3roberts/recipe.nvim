---@alias RecipeStore table<string, Recipe>
local util = require("recipe.util")

---@class Recipe
---@field cmd string|string[]
---@field hidden boolean
---@field cwd string
---@field env table<string, string>
---@field source string
---@field name string
---@field components table<string, any>
---@field depends_on Recipe[]
---@field priority number
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

	if o.name == nil then
		o.name = (type(o.cmd) == "string" and o.cmd or table.concat(o.cmd, " ")) or util.random_name()
	end

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
	local cmd = self.cmd
	if type(cmd) == "table" then
		return table.concat(cmd, " ")
	elseif type(cmd) == "string" then
		return cmd
	else
		error("Invalid type")
	end
end
local line = require("nui.line")
local text = require("nui.text")
local tree = require("nui.tree")

function Recipe:display_cmd()
	local cmd = self.cmd
	local line = line()

	line:append("cmd", "Identifier")
	line:append(": ")

	if type(cmd) == "table" then
		line:append("[ ", "Delimiter")
		for _, v in ipairs(cmd) do
			line:append('"' .. v .. '"', "String")
			line:append(" ")
		end
		line:append("]", "Delimiter")
	elseif type(cmd) == "string" then
		line:append('"', "String")
		line:append(cmd, "String")
		line:append('"', "String")
	else
		error("Invalid type")
	end

	return line
end

function Recipe:display()
	local function ident(name)
		return text(name, "Identifier")
	end

	local nodes = {
		tree.Node({ text = line({ ident("name"), text(": "), text(self.name, "String") }) }, {}),
		tree.Node({ text = self:display_cmd() }, {}),
		tree.Node({ text = line({ ident("source"), text(": "), text(self.source, "String") }) }, {}),
		tree.Node({ text = line({ ident("cwd"), text(": "), text(self.cwd, "String") }) }, {}),
	}

	local deps = {}
	for _, v in pairs(self.depends_on or {}) do
		table.insert(deps, v:display())
	end

	if #deps ~= 0 then
		table.insert(nodes, tree.Node({ text = ident("depends_on") }, deps))
	end

	return tree.Node({ text = text(self.name) }, nodes)
end

function Recipe:format(key, padding)
	local cmd = self:fmt_cmd()
	local padding = string.rep(" ", math.max(padding - #self.name, 0))

	return string.format("%s%s - %s %s", key, padding, self.source, cmd)
end

function Recipe:has_component(kind)
	return self.components[kind] ~= nil
end

return Recipe
