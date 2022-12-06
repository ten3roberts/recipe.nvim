local api = vim.api
local fn = vim.fn

local util = require("recipe.util")
local lib = require("recipe.lib")
local config = require("recipe.config")

local M = {
	Recipe = require("recipe.core").Recipe,
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

	au({ "BufWritePre" }, {
		pattern = config.opts.recipes_file,
		callback = function(o)
			vim.notify(string.format("Modified %s in vim", o.file))
			-- modified_in_vim[o.file] = true
		end,
	})

	if config.opts.term.jump_to_end then
		au("TermOpen", {
			callback = function()
				vim.cmd("normal! G")
			end,
		})
	end
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

----- Loads recipes from `recipes.json`
-----@param callback fun(recipes: table<string, Recipe>)
--function M.load_recipes(callback)
--	local path = vim.loop.fs_realpath(config.opts.recipes_file)

--	if not path then
--		return callback({})
--	end

--	local function parse(data)
--		local cwd = fn.fnamemodify(path, ":p:h")
--		local old_cwd = fn.getcwd()

--		local ok, obj = pcall(vim.json.decode, data)

--		if not ok then
--			vim.notify(string.format("Failed to parse %s:\n%s", path, obj), vim.log.levels.ERROR)
--			return
--		end

--		api.nvim_set_current_dir(cwd)

--		local count = 0
--		local result = {}
--		for k, v in pairs(obj) do
--			if type(k) ~= "string" then
--				api.nvim_err_writeln("Expected string key in %q", path)
--				return
--			end
--			count = count + 1

--			v = config.make_recipe(v)
--			result[k] = v
--		end

--		api.nvim_set_current_dir(old_cwd)

--		vim.notify(string.format("Loaded %d recipes", count))

--		return result
--	end

--	local function read()
--		memo(path, function(data)
--			if not data then
--				return {}
--			end

--			modified_in_vim[path] = nil

--			local value = parse(data)
--			return value
--		end, callback)
--	end

--	if modified_in_vim[path] then
--		lib.trust_path(path, function()
--			vim.notify("Trusted: " .. path)
--		end)
--		read()
--	else
--		lib.is_trusted(path, function(trusted)
--			if trusted then
--				cache[path] = true
--				return read()
--			else
--				local mtime = fn.getftime(path)
--				local strtime = fn.strftime("%c", mtime)
--				local dur = lib.format_time((fn.localtime() - mtime) * 1000)
--				local trust = fn.confirm(
--					string.format("Trust recipes from %q?\nModified %s (%s ago)", path, strtime, dur),
--					"&Yes\n&No\n&View file",
--					2
--				)
--				if trust == 1 then
--					lib.trust_path(path, function() end)
--					cache[path] = true
--					return read()
--				elseif trust == 2 then
--					cache[path] = true
--					vim.notify(string.format("%q was not trusted. No recipes read", path), vim.log.levels.WARN)
--				elseif trust == 3 then
--					vim.cmd("edit " .. fn.fnameescape(path))
--					vim.notify("Viewing recipes. Use :w to accept and trust file")
--				end

--				return {}
--			end
--		end)
--	end
--end

--- Execute a recipe by name asynchronously
---@param name string
---@param callback fun(code: number)|nil
function M.bake(name, callback)
	M.load_cb(function(recipes)
		local recipe = recipes[name]

		if recipe == nil then
			return util.error("No such recipe: " .. name)
		end

		M.execute(recipe, callback)
	end)
end

--- Execute a recipe by name asynchronously
---@param name string
M.bake_async = async.wrap(M.bake, 2)

--- Execute an arbitrary command
---@param recipe Recipe
function M.execute_async(recipe)
	local core = require("recipe.core")
	recipe = core.Recipe:new(recipe)
	-- Execute dependencies before
	-- local semaphore = { remaining = 1 }

	-- 	local function ex(code)
	-- 		if semaphore.remaining == nil or code ~= 0 then
	-- 			semaphore.remaining = nil
	-- 			return
	-- 		end

	-- 		semaphore.remaining = semaphore.remaining - 1

	-- 		if semaphore.remaining == 0 then
	-- 			lib.spawn(key, recipe, callback)
	-- 		end
	-- 	end

	local deps = {}
	for _, v in ipairs(recipe.components.dependencies or recipe.components.depends_on or {}) do
		table.insert(deps, function()
			if type(v) == "string" then
				M.bake_async(v)
			else
				M.execute_async(v)
			end
		end)
	end

	if #deps > 0 then
		async.util.join(deps)
	end

	lib.spawn_async(recipe)
end

---Execute a recipe
---@param recipe Recipe
---@param callback fun(code: number)|nil
M.execute = function(recipe, callback)
	async.run(function()
		M.execute_async(recipe)
	end, function(code)
		if callback then
			callback(code)
		end
	end)
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
	vim.notify("Complete")
	M.load_cb(function(r)
		__recipes = r
	end)

	local t = {}

	for _, k in ipairs(order(__recipes)) do
		if k[1]:find(lead) then
			t[#t + 1] = k[1]
		end
	end

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
