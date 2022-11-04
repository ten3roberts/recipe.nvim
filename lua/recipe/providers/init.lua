local async = require("plenary.async")
local util = require("recipe.util")
local M = {}
---@class Provider
local Provider = {}
Provider.__index = Provider

---@async
---@param path string
---@return RecipeStore
function Provider.load(path) end

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

---@async
---Loads the recipes from the registered providers
---@return RecipeStore
function M.load()
	local config = require("recipe.config")
	local path = vim.loop.fs_realpath(vim.fn.getcwd())
	local t = {}

	local futures = {}
	for i, def in pairs(config.opts.providers) do
		local provider = providers[def.name]
		if not provider then
			util.error("No such provider: " .. def.name)
			return {}
		end
		local prio = def.priority or math.ceil(1000 / i)

		table.insert(futures, function()
			for k, v in pairs(provider.load(path)) do
				local existing = t[k]
				-- If there are duplicate keys, prefer the highest priority
				if not existing or existing.priority < prio then
					v.source = def.name
					v.priority = prio
					-- Make sure name exists
					v.name = v.name or k
					t[k] = v
				end
			end
		end)
	end

	async.util.join(futures)

	return t
end

M.test = async.void(function()
	require("recipe").setup({})
	local recipes = M.load()
	print("Loaded recipes: ", vim.inspect(recipes))
end)

return M
