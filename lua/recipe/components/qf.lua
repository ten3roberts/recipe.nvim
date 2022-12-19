local util = require("recipe.util")
local M = {
	opts = {
		max_lines = 10000,
		throttle = 1000,
	},
}

local lock = nil

local quickfix = require("recipe.quickfix")

local function on_output(task, line)
	local qf = task.data.qf

	if #qf.lines > M.opts.max_lines then
		return
	end

	line = util.remove_escape_codes(line)
	table.insert(qf.lines, line)

	local cur = vim.loop.hrtime()
	local function write_qf()
		qf.lock = quickfix.set(qf.lock, task.recipe, qf.lines)
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

---@type Component
local qf = {}

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

	qf.lock = quickfix.set(qf.lock, task.recipe, qf.lines)
	quickfix.release_lock(qf.lock)
end

qf.on_stdout = on_output
qf.on_stderr = on_output

function M.setup(opts)
	M.opts = vim.tbl_extend("force", M.opts, opts or {})
	require("recipe.components").register("qf", qf)
end

return M
