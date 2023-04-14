local util = require("recipe.util")
local components = {}

---@class ComponentTemplate
---@field params any
---@field new fun(any): Component

---@class Component
---@field on_start function(task: Task)|nil
---@field on_exit function(task: Task)|nil
---@field on_output function(task: Task)|nil
local M = {}

function M.register(name, component)
	components[name] = component
end

function M.alias(name, alias)
	components[alias] = components[name]
end

---@return ComponentTemplate|nil
function M.get(name)
	local v = components[name]
	if v then
		return v
	else
		local path = "recipe.components." .. name
		--- Attempt to find the component in a file
		local ok, template = pcall(require, path)
		if ok then
			components[name] = template
			return template
		else
			util.log_error("No such component: " .. name)
		end
	end
end

--- Instantiates all components
function M.instantiate(recipe)
	local t = {}
	for k, v in pairs(recipe.components) do
		local template = M.get(k)
		if template then
			local instance = template.new(vim.tbl_extend("force", template.params, v))
			table.insert(t, instance)
		end
	end

	return t
end

---@param instances Component[]
---@param method string
---@return fun(...)
function M.collect_method(instances, method)
	local t = {}
	for _, v in ipairs(instances) do
		local m = v[method]
		if m then
			t[#t + 1] = function(...)
				m(...)
			end
		end
	end

	return function(...)
		for _, v in ipairs(t) do
			v(...)
		end
	end
end

---@param instances Component[]
function M.execute(instances, method, ...)
	for _, v in ipairs(instances) do
		if v[method] then
			v[method](...)
		end
	end
end

return M
