local uv = vim.loop
local M = {}
local util = require("recipe.util")
local fn = vim.fn

local function remove_escape_codes(s)
	-- from: https://stackoverflow.com/questions/48948630/lua-ansi-escapes-pattern
	local ansi_escape_sequence_pattern = "[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]"

	return s:gsub(ansi_escape_sequence_pattern, ""):gsub("\r", "")
end

local quickfix = require("recipe.quickfix")

---@param _ string
---@param recipe Recipe
---@param on_exit fun(code: number)
---@return Task|nil
function M.execute(_, recipe, on_exit)
	local data = { "" }
	local info = {
		restarted = false,
	}

	local lock = nil

	local function set_qf(open)
		lock = quickfix.set(lock, recipe, data, open)
	end

	local timer = uv.new_timer()
	local old_len = #data
	timer:start(
		200,
		1000,
		vim.schedule_wrap(function()
			if #data ~= old_len then
				old_len = #data
				set_qf(nil)
			end
		end)
	)

	local function exit(_, code)
		timer:stop()
		timer:close()

		if info.restarted then
			return
		end

		set_qf(code ~= 0)

		quickfix.release_lock(lock)

		on_exit(code)
	end

	local last_report = vim.loop.hrtime()

	local function on_output(_, lines)
		if #lines == 0 or #data > 5000 then
			return
		end

		-- Complete previous line
		data[#data] = data[#data] .. remove_escape_codes(lines[1])

		for i = 2, #lines do
			data[#data + 1] = remove_escape_codes(lines[i])
		end
		local cur = vim.loop.hrtime()

		if cur - last_report > 1e9 then
			set_qf(false)
			last_report = cur
		end
	end

	local id = fn.jobstart(recipe.cmd, {
		cwd = recipe.cwd,
		on_stdout = on_output,
		on_exit = exit,
		on_stderr = on_output,
		env = recipe.env,
	})

	if id <= 0 then
		util.error("Failed to start job")
		return
	end

	return {
		output = data,
		stop = function()
			fn.jobstop(id)
			fn.jobwait({ id }, 1000)
		end,
		restart = function(start, cb)
			info.restarted = true
			fn.jobstop(id)
			fn.jobwait({ id }, 1000)

			M.execute(_, recipe, start)
		end,
		focus = function() end,
		recipe = recipe,
	}
end

return M
