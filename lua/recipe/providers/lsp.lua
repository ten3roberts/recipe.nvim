local async = require("plenary.async")
local core = require("recipe.core")
local provider = {
	--- Cache results to persist across buffers
	cached = {},
}

---@param bufnr number
---@param cb fun(err: table|nil, result: table|nil)
local function client_runnables(client, bufnr, cb)
	vim.lsp.buf_request(
		bufnr,
		"experimental/runnables",
		{ textDocument = vim.lsp.util.make_text_document_params(bufnr), position = nil },
		cb
	)
end

---@type fun(client, bufnr): (table|nil, table|nil)
local runnables_async = async.wrap(client_runnables, 3)

local function runnables(bufnr)
	local futures = {}
	local result = {}
	for _, client in pairs(vim.lsp.get_active_clients({ bufnr = bufnr })) do
		if client.supports_method("experimental/runnables") then
			table.insert(futures, function()
				local _, res = runnables_async(client, bufnr)
				for _, v in ipairs(res or {}) do
					table.insert(result, v)
				end
			end)
		end
	end

	if #futures > 0 then
		async.util.join(futures)
	end
	return result
end

--- Load lsp runnables
---@param _ string
---@return RecipeStore
function provider.load(_)
	local results = runnables(vim.api.nvim_get_current_buf())
	local t = provider.cached

	for _, v in ipairs(results or {}) do
		if v.kind == "cargo" then
			local cmd = { "cargo" }
			vim.list_extend(cmd, v.args.cargoArgs)
			vim.list_extend(cmd, v.args.cargoExtraArgs)
			table.insert(cmd, "--")
			vim.list_extend(cmd, v.args.executableArgs)
			local recipe = core.Recipe:new({ cmd = cmd, cwd = v.args.workspaceRoot, adapter = "term", name = v.label })
			t[recipe.name] = recipe
		end
	end
	return t
end

local M = {}
function M.setup()
	provider.cached = {}
	require("recipe").register("lsp", provider)
end
return M
