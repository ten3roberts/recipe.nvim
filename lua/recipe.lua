local api = vim.api

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

	local group = api.nvim_create_augroup("Recipe", { clear = true })
	local function au(event, o)
		o.group = group
		api.nvim_create_autocmd(event, o)
	end

	require("recipe.components.qf").setup()
	require("recipe.components.dap").setup()

	au({ "BufWritePre" }, {
		pattern = config.opts.recipes_file,
		callback = function(o)
			vim.notify(string.format("Modified %s in vim", o.file))
			-- modified_in_vim[o.file] = true
		end,
	})

	-- if config.opts.term.jump_to_end then
	-- 	au("TermOpen", {
	-- 		callback = function()
	-- 			vim.cmd("normal! G")
	-- 		end,
	-- 	})
	-- end
end

---Execute a recipe by name
---@param name string
---@param recipe Recipe
function M.insert(name, recipe)
	local t = config.make_recipe(recipe)
	-- __recipes[name] = t
end

M.stop_all = lib.stop_all

local async = require("plenary.async")
local providers = require("recipe.providers")
function M.register(name, provider)
	providers.register(name, provider)
end

---@async
---Loads all recipes asynchronously
---@return RecipeStore
function M.load()
	return providers.load()
end

---@param cb fun(recipes: RecipeStore)
function M.load_cb(cb)
	async.run(M.load, cb)
end

---Executes a recipe by name
---@param name string
---@param open TermConfig|boolean|nil
function M.bake(name, open)
	M.load_cb(function(recipes)
		local recipe = recipes[name]

		if recipe == nil then
			return util.error("No such recipe: " .. name)
		end

		M.execute(recipe, open)
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

---Execute a recipe
---@param recipe Recipe
---@param open TermConfig|nil
---@return Task
M.execute = function(recipe, open)
	local task = lib.spawn(M.Recipe:new(recipe))
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

---@param recipe Recipe
local function recipe_score(recipe, now)
	local f = recipe_frecency[recipe.name] or { uses = 0, last_use = 0.0 }
	local dur = now - f.last_use

	return (f.uses + 1) / (dur + 1) * recipe.priority * (lib.get_task(recipe.name) and 200 or 100)
end

---@param recipes table<string, Recipe>
local function order(recipes)
	-- Collect all
	local t = {}

	for _, v in pairs(recipes) do
		t[v.name] = v
	end

	local tasks = lib.get_tasks()
	for _, v in pairs(tasks) do
		t[v.recipe.name] = v.recipe
	end

	local now = vim.loop.hrtime() / 1000000000
	local all = {}
	for _, v in pairs(t) do
		table.insert(all, v)
	end
	table.sort(all, function(a, b)
		return recipe_score(a, now) > recipe_score(b, now)
	end)

	return all
end

function M.pick()
	M.load_cb(function(recipes)
		local items = order(recipes)

		if #items == 0 then
			vim.notify("No recipes")
			return
		end

		local max_len = 0
		for _, v in ipairs(items) do
			max_len = math.max(#(v.name or ""), max_len)
		end

		local opts = {
			format_item = function(recipe)
				local pad = string.rep(" ", math.max(max_len - #(recipe.name or "")))

				return (lib.get_task(recipe.name) and "*" or " ") .. " " .. recipe:format(pad)
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

			local f = recipe_frecency[recipe.name] or { uses = 0, last_use = 0 }
			f.uses = f.uses + 1
			f.last_use = vim.loop.hrtime() / 1000000000
			recipe_frecency[recipe.name] = f

			M.execute(recipe)
		end)
	end)
end

local __recipes = {}
function M.complete(lead, _, _)
	providers.load_callback(1000, function(v)
		__recipes = v
	end)

	vim.notify("Complete: " .. lead)

	local t = {}

	for k, _ in pairs(__recipes) do
		if k:find(lead) then
			print("k: ", k, "lead: ", lead)
			table.insert(t, k)
		end
	end

	local now = vim.loop.hrtime() / 1e9

	table.sort(t, function(a, b)
		return lib.score(a, nil, now) > lib.score(b, nil, now)
	end)

	print("t: ", vim.inspect(t))

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
