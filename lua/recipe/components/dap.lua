local M = {}
local util = require("recipe.util")

local dap = {
	on_exit = function(opts, task)
		if task.code ~= 0 then
			return
		end

		local conf = {
			type = opts.adapter or vim.o.ft,
			request = "launch",
			name = "Recipe " .. task.recipe.name,
			program = opts.program,
			args = opts.args,
			justMyCode = opts.justMyCode,
			env = opts.env,
		}

		local _, dap = pcall(require, "dap")
		if dap then
			vim.notify("Launching dap session")
			dap.run(conf, { env = task.env, cwd = task.recipe.cwd })
		else
			util.error("Dap could not be found")
		end
	end,
}

function M.setup()
	require("recipe.components").register("dap", dap)
end

return M
