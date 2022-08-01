local util = require("recipe.util")

local M = {}

local has_dap, dap = pcall(require, "dap")
local has_setup = false

function M.setup()
	if not has_dap then
		return
	end
	local config = require("recipe.config")
	if has_setup then
		return
	end
	has_setup = true

	dap.adapters = vim.tbl_extend("keep", dap.adapters, config.opts.debug_adapters)
end

--- @param _ string
--- @param recipe Recipe
--- @param opts table
function M.launch(_, recipe, ok, opts)
	if not ok then
		return
	end

	M.setup()
	local compiler = util.get_compiler(recipe.cmd)
	local conf = vim.tbl_extend("force", {
		type = opts.adapter or ("recipe-" .. compiler:lower()),
		request = "launch",
		cwd = recipe.cwd,
		name = "Recipe " .. recipe.cmd,
		justMyCode = false,
	}, opts)

	dap.run(conf)
end

---@param recipe Recipe
---@param on_start fun(task: Task|nil)
---@param on_exit fun(code: number)
function M.execute(recipe, on_start, on_exit)
	M.setup()

	local opts = recipe.opts

	local conf = {
		type = opts.adapter or vim.o.ft,
		request = "launch",
		name = "Recipe " .. recipe.cmd,
		program = recipe.cmd,
		justMyCode = true,
	}

	dap.run(conf, { env = recipe.env, cwd = recipe.cwd })

	on_start({
		focus = function() end,
		stop = function() end,
		execute = function() end,
	})

	on_exit(0)
end

return M
