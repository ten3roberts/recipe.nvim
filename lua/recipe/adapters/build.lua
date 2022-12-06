local uv = vim.loop
local M = {}
local util = require("recipe.util")
local components = require("recipe.components")
local fn = vim.fn

---@param _ string
---@param recipe Recipe
---@param on_exit fun(code: number)
---@return Task|nil
function M.execute(_, recipe, on_exit)
	local data = { "" }
	local info = {
		restarted = false,
	}

	local task = { recipe = recipe, data = {} }

	local timer = uv.new_timer()

	local on_stdout, stdout_cleanup = util.curry_output("on_stdout", task)
	local on_stderr, stderr_cleanup = util.curry_output("on_stderr", task)

	local function exit(_, code)
		timer:stop()
		timer:close()

		stdout_cleanup()
		stderr_cleanup()

		if info.restarted then
			return
		end

		components.execute(recipe.components, "on_exit", task)

		on_exit(code)
	end

	local id = fn.jobstart(recipe.cmd, {
		cwd = recipe.cwd,
		on_stdout = on_stdout,
		on_exit = exit,
		on_stderr = on_stderr,
		env = recipe.env,
	})

	if id <= 0 then
		util.error("Failed to start job")
		return
	end

	components.execute(recipe.components, "on_start", task)
	task.stop = function()
		fn.jobstop(id)
		fn.jobwait({ id }, 1000)
	end

	task.restart = function(start, _)
		info.restarted = true
		fn.jobstop(id)
		fn.jobwait({ id }, 1000)

		M.execute(_, recipe, start)
	end

	task.focus = function() end

	return task
end

return M
