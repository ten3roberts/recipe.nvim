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
		env = nil,
	},
	---@param params DapParams
	new = function(_, params)
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
					name = task.recipe.label,
					program = params.program,
					args = params.args,
					justMyCode = params.justMyCode,
					env = vim.tbl_extend("keep", params.env or {}, task.env),
				}

				if dap then
					vim.notify("Launching dap session")
					dap.terminate()
					vim.schedule(function()
						dap.run(conf)
					end)
				else
					util.log_error("Dap could not be found")
				end
			end,
		}
	end,
}
