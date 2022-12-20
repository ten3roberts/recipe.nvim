local api = vim.api
local M = {
	opts = {
		max_lines = 10000,
		throttle = 1000,
	},
}

local quickfix = require("recipe.quickfix")

---@type Component
local qf = {}

---comment
---@param task Task
function qf.on_output(task)
	local qf = task.data.qf

	local lines = api.nvim_buf_get_lines(task.bufnr, 0, -1, true)

	local cur = vim.loop.hrtime()
	local function write_qf()
		qf.lock = quickfix.set(qf.lock, task.recipe, lines)
		qf.last_report = vim.loop.hrtime()
	end

	if qf.in_flight then
		return
	end

	if (cur - qf.last_report) / 1e6 > M.opts.throttle then
		write_qf()
	else
		local timer = vim.loop.new_timer()
		timer:start(
			M.opts.throttle,
			0,
			vim.schedule_wrap(function()
				timer:stop()
				timer:close()
				qf.in_flight = nil

				write_qf()
			end)
		)

		qf.in_flight = timer
	end
end

function qf.on_start(task)
	task.data.qf = {
		last_report = 0,
		lines = {},
		lock = nil,
	}
end

---@param task Task
function qf.on_exit(task)
	local qf = task.data.qf
	if qf.in_flight then
		qf.in_flight:stop()
		qf.in_flight:close()
		qf.in_flight = nil
	end

	local lines = api.nvim_buf_get_lines(task.bufnr, 0, -1, true)
	qf.lock = quickfix.set(qf.lock, task.recipe, lines)
	quickfix.release_lock(qf.lock)
end

function M.setup(opts)
	M.opts = vim.tbl_extend("force", M.opts, opts or {})
	require("recipe.components").register("qf", qf)
end

return M
