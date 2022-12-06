local M = {
	opts = {
		max_lines = 10000,
	},
}

local lock = nil

local quickfix = require("recipe.quickfix")

local function set_qf(task, open)
	lock = quickfix.set(lock, task.recipe, data, open)
end

local function on_output(task, line)
	local qf = task.data.qf

	if #qf.lines > M.opts.max_lines then
		return
	end

	table.insert(qf.lines, line)

	local cur = vim.loop.hrtime()

	if cur - qf.last_report > 5e8 then
		qf.lock = quickfix.set(qf.lock, task.recipe, qf.lines)
		qf.last_report = cur
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
