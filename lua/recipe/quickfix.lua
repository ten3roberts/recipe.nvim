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

---@return Lock|nil
function M.acquire_lock()
	local cur_time = uv.now()

	if qf_lock == nil or cur_time > qf_lock.expiration then
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

---@param lock Lock|nil
---@param recipe Recipe
---@param data string[]
---@param open boolean|nil
---@return Lock|nil
function M.set(lock, recipe, data, open)
	--- Refresh lock

	local cur_time = uv.now()
	-- If lock is eol attempt to reaquire
	if not lock or cur_time > lock.expiration then
		M.release_lock(lock)

		lock = M.acquire_lock()
	end

	-- A lock is successfully held
	if lock then
		lock.expiration = cur_time + 10

		local compiler = util.get_compiler(recipe:fmt_cmd())
		local old_cwd = vim.fn.getcwd()
		api.nvim_set_current_dir(recipe.cwd)
		util.qf(recipe:fmt_cmd(), compiler, data, open)
		api.nvim_set_current_dir(old_cwd)
	end

	return lock
end

return M
