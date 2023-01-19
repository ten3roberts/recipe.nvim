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

---@param _ any
---@param task Task
local function parse(_, task, open)
	local lines = task:get_output()
	qf.lock = quickfix.set(qf.lock, task.recipe, lines, open)
end

---comment
---@param task Task
function qf.on_output(opts, task)
	local qf = task.data.qf

	qf.throttled_parse(opts, task, false)
end
local util = require("recipe.util")

function qf.on_start(_, task)
	task.data.qf = {
		throttled_parse = util.throttle(parse, M.opts.throttle),
		lock = nil,
	}
end

---@param task Task
function qf.on_exit(opts, task)
	local qf = task.data.qf

	parse(opts, task, nil)
	quickfix.release_lock(qf.lock)
end

function M.setup(opts)
	M.opts = vim.tbl_extend("force", M.opts, opts or {})
	require("recipe.components").register("qf", qf)
end

return M
