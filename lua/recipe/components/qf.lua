local api = vim.api
local M = {
	opts = {
		max_lines = 1000,
		throttle = 5000,
	},
}

local quickfix = require("recipe.quickfix")

---@type Component
local qf = {}

---@param _ any
---@param task Task
local function parse(lock, task, open)
	local qf = task.data.qf
	local lines = task:get_output(0, M.opts.max_lines)
	qf.lock = quickfix.set(qf.lock, task.recipe, qf.compiler, lines, open)
end

---comment
---@param task Task
function qf.on_output(opts, task)
	local qf = task.data.qf

	qf.throttled_parse(opts, task, false)
end
local util = require("recipe.util")

function qf.on_start(opts, task)
	local throttled_parse, stop_parse = util.throttle(parse, M.opts.throttle)

	task.data.qf = {
		throttled_parse = throttled_parse,
		stop_parse = stop_parse,
		lock = quickfix.acquire_lock(true),
		compiler = opts.compiler or util.get_compiler(task.recipe:fmt_cmd()),
	}
end

---@param task Task
function qf.on_exit(opts, task)
	local qf = task.data.qf

	qf.stop_parse()
	parse(opts, task, nil)
	quickfix.release_lock(qf.lock)
end

function M.setup(opts)
	M.opts = vim.tbl_extend("force", M.opts, opts or {})
	require("recipe.components").register("qf", qf)
end

---@type ComponentTemplate
return {
	---@class QfParams
	params = {
		compiler = nil,
		throttle = 1000,
		max_lines = 5000,
	},

	---@param params QfParams
	new = function(params)
		local lock = nil

		local compiler = params.compiler

		---@param task Task
		function parse(task, open)
			local compiler = compiler or util.get_compiler(task.recipe:fmt_cmd())
			local lines = task:get_output(0, params.max_lines)
			lock = quickfix.set(lock, task.recipe, compiler, lines, open)
		end
		local throttle = util.throttle(parse, params.throttle)

		return {
			on_output = function(task)
				throttle(task, false)
			end,
			on_exit = function(task)
				throttle.stop()
				parse(task, nil)
				quickfix.release_lock(lock)
			end,
		}
	end,
}
