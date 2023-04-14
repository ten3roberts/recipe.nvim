local M = {}
local util = require("recipe.util")

local _, dap = pcall(require, "dap")
return {
	---@class DapParams
	params = {
		close_task = true,
		adapter = nil,
		args = nil,
		program = nil,
		justMyCode = true,
	},
	---@param params DapParams
	new = function(params)
		return {
			on_exit = function(task)
				if task.code ~= 0 then
					return
				end

				if params.close_task ~= false then
					task:close()
				end

				local conf = {
					type = params.adapter or vim.o.ft,
					request = "launch",
					name = "Recipe " .. task.recipe.key,
					program = params.program,
					args = params.args,
					justMyCode = params.justMyCode,
					-- env = vim.tbl_extend("keep", opts.env or {}, task.env),
				}

				if dap then
					vim.notify("Launching dap session: " .. vim.inspect(conf))
					dap.run(conf)
				else
					util.log_error("Dap could not be found")
				end
			end,
		}
	end,
}
