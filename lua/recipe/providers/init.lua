local async = require("plenary.async")
local util = require("recipe.util")
local M = {}
---@class Provider
---@field load fun(path: string): RecipeStore

local providers = {}

---@class ProviderDef
---@field name string
---@field priority number|nil

---Register a provider
---@param name string
---@param provider Provider
function M.register(name, provider)
	providers[name] = provider
end

---Loads the recipes from the registered providers
---@param timeout number|nil
---@return RecipeStore
function M.load(timeout)
	local function load()
		local result = {}

		local config = require("recipe.config")
		local path = vim.loop.fs_realpath(vim.fn.getcwd())

		local futures = {}
		for i, def in pairs(config.opts.providers) do
			local provider = providers[def.name]
			if not provider then
				util.error("No such provider: " .. def.name)
				return {}
			end
			local prio = def.priority or math.ceil(1000 / i)

			local logger = require("recipe.logger")
			table.insert(futures, function()
				logger.fmt_debug("Provider: %s priority: %d", def.name, prio)
				for k, v in pairs(provider.load(path)) do
					local existing = result[k]
					-- If there are duplicate keys, prefer the highest priority
					if not existing or existing.priority < prio then
						v.source = v.source or def.name

						logger.fmt_debug("Loaded recipe %s from %s", k, v.source)
						if existing then
							logger.fmt_debug("Overriding recipe %s from %s", k, existing.source)
						end
						v.priority = prio
						-- Make sure name exists
						v.label = v.label or k
						result[k] = v
					end
				end
			end)
		end

		if #futures > 0 then
			async.util.join(futures)
		end

		return result
	end

	if timeout then
		return util.timeout(load, timeout) or {}
	else
		return load()
	end
end

M.test = async.void(function()
	require("recipe").setup({})
	local recipes = M.load()
	print("Loaded recipes: ", vim.inspect(recipes))
end)

return M
