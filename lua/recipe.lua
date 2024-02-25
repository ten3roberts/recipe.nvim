local api = vim.api
local async = require("plenary.async")

local util = require("recipe.util")
local lib = require("recipe.lib")
local config = require("recipe.config")

local M = {
	Recipe = require("recipe.recipe"),
}

-- local modified_in_vim = {}

---Provide a custom config
---@param opts Config
function M.setup(opts)
	config.setup(opts)

	local group = api.nvim_create_augroup("recipe", { clear = true })

	async.run(function()
		lib.load_cache()
	end)

	api.nvim_create_autocmd("VimLeave", {
		group = group,
		callback = function()
			async.run(function()
				lib.save_cache()
			end)
		end,
	})
end

---Execute a recipe by name
---@param name string
---@param recipe Recipe
function M.insert(name, recipe)
	local recipe = M.make_recipe(recipe)
	return lib.insert_task(name, M.Recipe:new(recipe))
end

M.stop_all = lib.stop_all

function M.register(name, provider)
	local providers = require("recipe.providers")
	providers.register(name, provider)
end

---@async
---Loads all recipes asynchronously
---@return Tasks
function M.load()
	return lib.load()
end

---@param cb fun(recipes: Tasks)
function M.with_tasks_timeout(cb)
	async.run(function()
		return util.timeout(M.load, 100) or lib.all_tasks()
	end, cb)
end

---Executes a recipe by name
---@param name string
---@param open TermConfig|nil
function M.bake(name, open)
	async.run(function()
		local tasks = lib.load()
		local task = tasks[name]

		if task == nil then
			return util.log_error("No such recipe: " .. name)
		end

		task:spawn()
		if open then
			task:focus(open)
		end
	end)
end

function M.make_recipe(opts)
	local Recipe = require("recipe.recipe")

	if type(opts) == "string" then
		return Recipe:new({ cmd = opts })
	else
		return Recipe:new(opts)
	end
end

---Execute a recipe or a description of a recipe
---@param recipe Recipe|table
---@param open TermConfig|nil
---@return Task
function M.execute(recipe, open)
	local task = lib.insert_task(nil, M.Recipe:new(recipe))

	task:spawn()
	if open then
		task:focus(open)
	end

	return task
end

---@class Frecency
---@field uses number
---@field last_use number

---@type { [string]: Frecency }
local recipe_frecency = {}

---@param tasks Tasks
local function order(tasks)
	-- Collect all
	local t = {}

	for _, v in pairs(tasks) do
		table.insert(t, v)
	end

	local now = vim.loop.now()

	local loc = util.get_position()

	table.sort(t, function(a, b)
		return lib.score(a, now, loc) > lib.score(b, now, loc)
	end)

	return t
end

function M.pick()
	M.with_tasks_timeout(function(tasks)
		local items = order(tasks)

		if #items == 0 then
			vim.notify("No recipes")
			return
		end

		local max_len = 0
		for _, v in ipairs(items) do
			max_len = math.max(#(v.recipe.label or ""), max_len)
		end

		local opts = {
			format_item = function(task)
				local pad = string.rep(" ", math.max(max_len - #(task.recipe.label or "")))

				return (lib.get_task(task.recipe.label) and "*" or " ") .. " " .. task.recipe:format(pad)
			end,
		}

		vim.ui.select(items, opts, function(recipe, idx)
			if not recipe then
				return
			end

			local r = items[idx]
			if not r then
				return
			end

			local f = recipe_frecency[recipe.label] or { uses = 0, last_use = 0 }
			f.uses = f.uses + 1
			f.last_use = vim.loop.now()
			recipe_frecency[recipe.label] = f

			M.execute(recipe, {})
		end)
	end)
end

local __recipes = {}
function M.complete(lead, _, _)
	M.with_tasks_timeout(function(v)
		__recipes = v
	end)

	local t = {}

	for k, _ in pairs(__recipes) do
		if k:find(lead) then
			table.insert(t, k)
		end
	end

	local now = vim.loop.now()
	local loc = util.get_position()
	table.sort(t, function(a, b)
		return lib.score(a, now, loc) > lib.score(b, now, loc)
	end)

	return t
end

local sl = require("recipe.statusline")
function M.statusline()
	local spinner = ""
	local tasks = {}
	for task in pairs(lib.get_tasks()) do
		tasks[#tasks + 1] = task
	end

	if #tasks > 0 then
		sl.start()
		spinner = sl.get_spinner()
	else
		sl.stop()
	end
	return spinner
end

_G.__recipe_complete = M.complete

api.nvim_exec(
	[[
  function! RecipeComplete(lead, cmd, cur)
    return v:lua.__recipe_complete(a:lead, a:cmd, a:cur)
  endfun
]],
	true
)

return M
