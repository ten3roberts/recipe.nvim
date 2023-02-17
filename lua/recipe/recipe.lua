local util = require("recipe.util")
---@alias RecipeStore table<string, Recipe>

---@class Location
---@field lnum number
---@field col number
---@field end_lnum number
---@field end_col number

---@class Recipe
---@field cmd string|string[]
---@field hidden boolean
---@field cwd string
---@field env table<string, string>
---@field source string
---@field key string
---@field components table<string, any>
---@field depends_on Recipe[]
---@field priority number
---@field location Location
local Recipe = {}
Recipe.__index = Recipe

local config = require("recipe.config")

--- Creates a new recipe
---@return Recipe
function Recipe:new(o)
	local t = {}
	t.components = o.components or {}

	for k, v in pairs(config.opts.default_components) do
		if t.components[k] == nil then
			t.components[k] = v
		end
	end

	if o.key == nil then
		o.key = (type(o.cmd) == "string" and o.cmd or table.concat(o.cmd, " ")) or util.random_name()
	end

	t.source = o.source or "user"
	t.env = o.env
	t.hidden = o.hidden
	t.cmd = o.cmd
	t.key = o.key
	t.location = o.location

	t.depends_on = {}
	for _, dep in ipairs(o.depends_on or {}) do
		table.insert(t.depends_on, Recipe:new(dep))
	end

	t.cwd = o.cwd or vim.fn.getcwd()
	t.priority = o.priority or 1000
	return setmetatable(t, self)
end

---Adds a new component to the recipe
---@param value Component
---@return Recipe
function Recipe:add_component(type, value)
	self.components[type] = value
	return self
end

---@param pos Position
---@return number|nil
function Recipe:distance_to(pos)
	if not self.location or self.location.bufnr ~= pos.bufnr then
		return nil
	end

	local to_start = self.location.lnum - pos.lnum
	local to_end = pos.lnum - self.location.end_lnum
	local dist = math.max(to_start, to_end)

	return dist
end

---@return string
function Recipe:fmt_cmd()
	local cmd = self.cmd
	if type(cmd) == "table" then
		return table.concat(cmd, " ")
	elseif type(cmd) == "string" then
		return cmd
	else
		error("Invalid type of cmd")
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

local function ident(name)
	return text(name, "Identifier")
end

local function field(name, value)
	return line({ ident(name), text(": "), text(value) })
end

local function display_location(location)
	return {
		tree.Node({ text = ident("start") }, {
			tree.Node({
				text = field("bufnr", text(location.bufnr .. " " .. vim.fn.bufname(location.bufnr) or "<no buffer>")),
			}, {}),
			tree.Node({ text = field("lnum", tostring(location.lnum)) }, {}),
			tree.Node({ text = field("col", tostring(location.col)) }, {}),
			tree.Node({ text = field("end_lnum", tostring(location.end_lnum)) }, {}),
			tree.Node({ text = field("end_col", tostring(location.end_col)) }, {}),
		}),
	}
end

function Recipe:display()
	local nodes = {
		tree.Node({ text = line({ ident("name"), text(": "), text(self.key, "String") }) }, {}),
		tree.Node({ text = self:display_cmd() }, {}),
		tree.Node({ text = line({ ident("source"), text(": "), text(self.source, "String") }) }, {}),
		tree.Node({ text = line({ ident("cwd"), text(": "), text(self.cwd, "String") }) }, {}),
	}

	local components = {}
	for k, v in pairs(self.components) do
		table.insert(
			components,
			tree.Node({ text = field(k, vim.inspect(v, { newline = " ", indent = "", depth = 3 })) })
		)
	end

	if #components ~= 0 then
		table.insert(nodes, tree.Node({ text = ident("components") }, components))
	end

	local deps = {}
	for _, v in pairs(self.depends_on or {}) do
		table.insert(deps, v:display())
	end

	if #deps ~= 0 then
		table.insert(nodes, tree.Node({ text = ident("depends_on") }, deps))
	end

	if self.location then
		table.insert(nodes, tree.Node({ text = ident("location") }, display_location(self.location)))
	end

	return tree.Node({ text = text(self.key) }, nodes)
end

function Recipe:format(key, padding)
	local cmd = self:fmt_cmd()
	local padding = string.rep(" ", math.max(padding - #key, 0))

	return string.format("%s%s - %s %s", key, padding, self.source, cmd)
end

function Recipe:has_component(kind)
	return self.components[kind] ~= nil
end

return Recipe
