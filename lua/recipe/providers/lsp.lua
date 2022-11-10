local async = require("plenary.async")
local core = require("recipe.core")
local provider = {
	--- Cache results to persist across buffers
	cached = {},
}

---@param bufnr number
---@param cb fun(err: table|nil, result: table|nil)
local function runnables(bufnr, cb)
	vim.lsp.buf_request(
		bufnr,
		"experimental/runnables",
		{ textDocument = vim.lsp.util.make_text_document_params(bufnr), position = nil },
		cb
	)
end

---@type fun(bufnr): (table|nil, table|nil)
local runnables_async = async.wrap(runnables, 2)

--- Load lsp runnables
---@param _ string
---@return RecipeStore
function provider.load(_)
	local _, results = runnables_async(0)
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
