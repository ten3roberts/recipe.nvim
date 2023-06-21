local api = vim.api
local M = {
	opts = {
		max_lines = 1000,
		throttle = 5000,
	},
}

local util = require("recipe.util")
local quickfix = require("recipe.quickfix")

---@type ComponentTemplate
return {
	---@class QfParams
	params = {
		compiler = nil,
		throttle = 2000,
		max_lines = 2000,
	},

	---@param params QfParams
	new = function(task, params)
		local lock = nil

		local compiler = params.compiler or util.get_compiler(task.recipe:fmt_cmd())
		if not compiler then
			return {}
		end

		---@param task Task
		local function parse(task, open, conservative)
			local lines = task:get_output(0, params.max_lines)
			lock = quickfix.set(lock, task.recipe, compiler, lines, open, conservative)
		end

		local throttle = util.throttle(parse, params.throttle)

		return {
			on_output = function(task)
				throttle(task, false, true)
			end,
			on_exit = function(task)
				throttle.stop()
				parse(task, "auto", false)
				quickfix.release_lock(lock)
			end,
		}
	end,
}
