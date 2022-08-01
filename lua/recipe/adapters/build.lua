local M = {}
local api = vim.api
local fn = vim.fn

local function remove_escape_codes(s)
	return s:gsub("\x1b%[.-m", ""):gsub("\r", "")
end

---@param recipe Recipe
---@param callback fun(code: number)
---@return Task|nil
function M.execute(recipe, callback)
	local data = { "" }
	local info = {
		restarted = false,
	}

	local function on_exit(_, code)
		if info.restarted then
			return
		end

		local old_cwd = vim.fn.getcwd()
		api.nvim_set_current_dir(recipe.cwd)

		require("recipe.util").qf(data, recipe, "c", code == 0)

		api.nvim_set_current_dir(old_cwd)
		callback(code)
	end

	local function on_output(_, lines)
		if #lines == 0 or #data > 5000 then
			return
		end

		-- Complete previous line
		data[#data] = data[#data] .. remove_escape_codes(lines[1])

		for i = 2, #data do
			data[#data + 1] = remove_escape_codes(lines[i])
		end
	end

	vim.notify("Executing: " .. recipe.cmd)

	local id = fn.jobstart(recipe.cmd, {
		cwd = recipe.cwd,
		on_stdout = on_output,
		on_exit = on_exit,
		on_stderr = on_output,
		env = recipe.env,
	})

	if id <= 0 then
		vim.notify("Failed to start job", vim.log.levels.ERROR)
		return nil
	end

	return {
		stop = function()
			fn.jobstop(id)
			fn.jobwait({ id }, 1000)
		end,
		restart = function(cb)
			info.restarted = true
			fn.jobstop(id)
			fn.jobwait({ id }, 1000)
			M.execute(recipe, cb)
		end,
		focus = function() end,
		recipe = recipe,
	}
end

return M
