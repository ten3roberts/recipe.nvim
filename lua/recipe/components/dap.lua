local M = {}
local util = require("recipe.util")

local dap = {
	---@param opts any
	---@param task Task
	on_exit = function(opts, task)
		if task.code ~= 0 then
			return
		end

		if opts.close_task ~= false then
			task:close()
		end

		local conf = {
			type = opts.adapter or vim.o.ft,
			request = "launch",
			name = "Recipe " .. task.recipe.key,
			program = opts.program,
			args = opts.args,
			justMyCode = opts.justMyCode,
			env = vim.tbl_extend("keep", opts.env or {}, task.env),
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
