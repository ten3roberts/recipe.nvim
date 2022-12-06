local util = require("recipe.util")
local components = {}

---@class Component
---@field on_start function(task: Task)|nil
---@field on_exit function(task: Task)|nil
---@field on_stdout function(task: Task, line: string)|nil
---@field on_stderr function(task: Task, line: string)|nil
local M = {}

function M.register(name, component)
	components[name] = component
end

function M.get(name)
	local v = components[name]
	if not v then
		util.error("No such component: " .. name)
	end

	return v or {}
end

---@param components table<string, any>
---@param method string
---@return fun(...)
function M.collect_method(components, method)
	local t = {}
	for k, _ in pairs(components) do
		local comp = M.get(k)
		if comp[method] then
			t[#t + 1] = comp[method]
		end
	end

	return function(...)
		for _, v in ipairs(t) do
			v(...)
		end
	end
end

function M.execute(components, method, ...)
	for k, _ in pairs(components) do
		local comp = M.get(k)
		if comp[method] then
			comp[method](...)
		end
	end
end

return M
