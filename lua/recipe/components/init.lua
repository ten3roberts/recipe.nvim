local util = require("recipe.util")
local components = {}

---@class Component
---@field on_start function(opts: any, task: Task)|nil
---@field on_exit function(opts: any, task: Task)|nil
---@field on_output function(opts: any, task: Task, bufnr: number)|nil
local M = {}

function M.register(name, component)
	components[name] = component
end

function M.alias(name, alias)
	components[alias] = components[name]
end

function M.get(name)
	local v = components[name]
	if not v then
		util.error("No such component: " .. name)
	end

	return v or {}
end

---@param recipe Recipe
---@param method string
---@return fun(...)
function M.collect_method(recipe, method)
	local t = {}
	for k, v in pairs(recipe.components) do
		local comp = M.get(k)
		local m = comp[method]
		if m then
			t[#t + 1] = function(...)
				m(v, ...)
			end
		end
	end

	return function(...)
		for _, v in ipairs(t) do
			v(...)
		end
	end
end

function M.execute(recipe, method, ...)
	for k, v in pairs(recipe.components) do
		local comp = M.get(k)
		if comp[method] then
			comp[method](v, ...)
		end
	end
end

return M
