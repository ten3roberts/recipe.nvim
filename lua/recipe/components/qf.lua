local lock = nil

local quickfix = require("recipe.quickfix")

local function set_qf(open)
	lock = quickfix.set(lock, task.recipe, data, open)
end
return {
	on_start = function(task)
		task.data.qf = {
			last_report = vim.loop.hrtime(),
			lock = nil,
		}
	end,
	---@param task Task
	on_output = function(task)
		local qf = task.data.qf
		local cur = vim.loop.hrtime()

		if cur - qf.last_report > 1e9 then
			quickfix.set(qf.lock, task.recipe, task.output)
			qf.last_report = cur
		end
	end,
	on_exit = function(task)
		quickfix.release_lock(task.data.qf.lock)
	end,
}
