local async = require("plenary.async")
local util = require("recipe.util")
local Recipe = require("recipe.recipe")
local provider = {}

---@param bufnr number
---@param cb fun(err: table|nil, result: table|nil)
local function client_runnables(client, bufnr, cb)
	client.request(
		"experimental/runnables",
		{ textDocument = vim.lsp.util.make_text_document_params(bufnr), position = nil },

		cb
	)
end

---@type fun(client, bufnr): (table|nil, table|nil)
local runnables_async = async.wrap(client_runnables, 3)

---@return table
local function runnables(bufnr)
	local futures = {}
	local result = {}
	for _, client in pairs(vim.lsp.get_active_clients({ bufnr = bufnr })) do
		if client.supports_method("experimental/runnables") then
			table.insert(
				futures,
				util.timeout(
					function()
						local _, res = runnables_async(client, bufnr)
						for _, v in ipairs(res or {}) do
							table.insert(result, v)
						end

						return nil
					end,
					1500,
					function()
						util.warn("LSP runnables timed out for " .. client.name)
					end
				)
			)
		end
	end

	if #futures > 0 then
		async.util.join(futures)
	end

	return result
end

---@class LocationUri
---@field targetUri string
---@field targetRange table

---@param location LocationUri
---@return Location
local function convert_location(location)
	return {
		lnum = location.targetRange.start.line,
		col = location.targetRange.start.character,
		bufnr = vim.uri_to_bufnr(location.targetUri),
		uri = location.targetUri,
		end_lnum = location.targetRange["end"].line,
		end_col = location.targetRange["end"].character,
	}
end

---@class CargoArgs
---@field cargoArgs string[]
---@field cargoExtraArgs string[]
---@field executableArgs string[]
---@field workspaceRoot string

---@class CargoRunnable
---@field args CargoArgs
---@field extra_args string[]
---@field executable_args string[]
---@field location LocationUri
---@field label string

---@param v CargoRunnable
local function cargo_command(v)
	local cmd = { "cargo" }
	vim.list_extend(cmd, v.args.cargoArgs)
	vim.list_extend(cmd, v.args.cargoExtraArgs)
	table.insert(cmd, "--")
	vim.list_extend(cmd, v.args.executableArgs)

	local location

	if v.location then
		location = convert_location(v.location)
	end

	return Recipe:new({
		cmd = cmd,
		cwd = v.args.workspaceRoot,
		key = v.label,
		location = location,
	})
end

---@param v CargoRunnable
local function cargo_debug_command(v)
	local cmd = { "cargo" }
	vim.list_extend(cmd, v.args.cargoArgs)

	for i, arg in ipairs(cmd) do
		if arg == "check" then
			return
		elseif arg == "run" then
			cmd[i] = "build"
		elseif arg == "test" then
			if not vim.tbl_contains(v.args.cargoArgs, "--no-run") then
				table.insert(v.args.cargoArgs, "--no-run")
			end
		end
	end

	if not vim.tbl_contains(v.args.cargoExtraArgs, "--message-format=json") then
		vim.list_extend(cmd, { "--message-format=json" })
	end
	vim.list_extend(cmd, v.args.cargoExtraArgs)

	local location

	if v.location then
		location = convert_location(v.location)
	end

	local label
	local run_target = v.label:match("run (%S+)")
	local test_target = v.label:match("test (%S+)")
	local test_mod_target = v.label:match("test%-mod (%S+)")
	if run_target then
		label = "debug " .. run_target
	elseif test_target then
		label = "debug-test " .. test_target
	elseif test_mod_target then
		label = "debug-mod " .. test_mod_target
	else
		label = "debug " .. v.label
	end

	return Recipe:new({
		cmd = cmd,
		cwd = v.args.workspaceRoot,
		key = label,
		location = location,
		components = {
			["cargo-dap"] = {
				args = v.args.executableArgs,
			},
		},
	})
end

--- Load lsp runnables
---@param _ string
---@return RecipeStore
function provider.load(_)
	local results = runnables(vim.api.nvim_get_current_buf())
	local t = {}

	for _, v in ipairs(results or {}) do
		if v.kind == "cargo" then
			local recipe = cargo_command(v)
			t[recipe.key] = recipe

			local recipe = cargo_debug_command(v)
			if recipe then
				t[recipe.key] = recipe
			end
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
