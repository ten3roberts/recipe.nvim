---@class FtProvider: Provider
local provider = {}
local core = require("recipe.core")
local Recipe = core.Recipe

local M = {
	filetypes = {},
}

function M.setup(filetypes)
	for ft, v in pairs(filetypes) do
		local t = M.filetypes[ft] or {}

		for k, v in pairs(ft) do
			v = Recipe:new(v)
			v.name = k
			v.source = "ft"
			t[k] = v
		end
		M.filetypes[ft] = t
	end
	require("recipe").register("ft", provider)
end

function provider.load(_)
	local ft = vim.o.ft
	print("Loading filetypes: ", vim.inspect(M.filetypes), ft)
	return M.filetypes[ft] or {}
end

return M
