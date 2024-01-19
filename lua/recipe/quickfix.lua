local logger = require("recipe.logger")
local util = require("recipe.util")
local api = vim.api
local uv = vim.loop

---@class Lock
---@field expiration number
---@field timeout number
---@field id integer
---@type Lock|nil
local qf_lock = nil

local lock_id = 0

local M = {}

local function get_change_tick()
	local change_tick = vim.fn.getqflist({ changedtick = 1 }).changedtick
	require("recipe.logger").fmt_info("Change tick: %d", change_tick)
	return change_tick
end

---@return Lock|nil
function M.acquire_lock(force)
	local cur_time = uv.now()

	if qf_lock == nil or cur_time > qf_lock.expiration or force then
		local id = lock_id
		lock_id = lock_id + 1
		qf_lock = {
			expiration = cur_time + 10,
			id = id,
		}

		return qf_lock
	else
		return nil
	end
end

---@param lock Lock|nil
function M.release_lock(lock)
	if qf_lock and lock and lock.id == qf_lock.id then
		qf_lock = nil
	end
end

--- Tracks the change tick that we have caused to determine if another process has set the quickfix.
---
--- If so, we should not set the quickfix list and prefer the other process's changes.
---
--- A common example of this is `:grep`, `lsp`, `telescope`.
local quickfix_change_tick = nil

---@param lock Lock|nil
---@param recipe Recipe
---@param data string[]
---@param open boolean|nil
---@param conservative boolean|nil
---@return Lock|nil
function M.set(lock, recipe, compiler, data, open, conservative)
	--- Refresh lock

	local cur_time = uv.now()
	-- If lock is eol attempt to reaquire
	local external_change_tick = get_change_tick()

	if quickfix_change_tick and quickfix_change_tick ~= external_change_tick then
		logger.warn(
			string.format(
				"[%s] Quickfix changed externally %d => %d",
				recipe.label,
				quickfix_change_tick,
				external_change_tick
			)
		)
		if conservative then
			return
		end
	end

	if not lock or cur_time > lock.expiration then
		M.release_lock(lock)

		lock = M.acquire_lock()
	end

	-- A lock is successfully held
	if lock then
		lock.expiration = cur_time + 10000

		-- local old_cwd = vim.fn.getcwd()
		-- api.nvim_set_current_dir(recipe.cwd)
		util.qf(recipe:fmt_cmd(), compiler, data, open)
		logger.fmt_info("%s %s wrote to quickfix list", recipe.label, recipe.label or "<no label>")
		-- api.nvim_set_current_dir(old_cwd)
	end

	local change_tick = get_change_tick()
	logger.fmt_info("New change tick: %d", change_tick)
	quickfix_change_tick = change_tick

	return lock
end

return M
