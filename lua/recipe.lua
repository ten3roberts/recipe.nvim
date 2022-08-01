local api = vim.api
local fn = vim.fn

local lib = require("recipe.lib")
local config = require("recipe.config")

local M = {}

---Provide a custom config
---@param opts Config
function M.setup(opts)
	config.setup(opts)

	local group = api.nvim_create_augroup("Recipe", { clear = true })
	local function au(event, o)
		o.group = group
		api.nvim_create_autocmd(event, o)
	end

	au({ "DirChanged", "VimEnter" }, {
		callback = function()
			M.load_recipes(false)
		end,
	})

	au({ "BufWritePost" }, {
		pattern = config.opts.recipes_file,
		callback = function(o)
			M.load_recipes(true, o.file)
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

---@type table<string, Recipe>
M.recipes = {}
local loaded_paths = {}

function M.clear()
	M.recipes = {}
end

--- @return string
function M.serialize()
	return fn.json_encode(M.recipes)
end

--- Execute a recipe by name
--- @param name string
function M.insert(name, recipe)
	local t = config.make_recipe(recipe)
	M.recipes[name] = t
end

M.stop_all = lib.stop_all

--- Loads recipes from `recipes.json`
function M.load_recipes(force, path)
	path = path or config.opts.recipes_file
	local cwd = fn.fnamemodify(path, ":p:h")
	api.nvim_set_current_dir(cwd)

	if not force and loaded_paths[cwd] ~= nil then
		return
	end

	loaded_paths[cwd] = true

	lib.read_file(
		path,
		vim.schedule_wrap(function(data)
			if not data or #data == 0 then
				return
			end

			lib.is_trusted(path, function(trusted)
				if not trusted and not force then
					local mtime = fn.getftime(path)
					local strtime = fn.strftime("%c", mtime)
					local dur = lib.format_time((fn.localtime() - mtime) * 1000)
					local trust = fn.confirm(
						string.format("Trust recipes from %q?\nModified %s (%s ago)", path, strtime, dur),
						"&Yes\n&No\n&View file",
						2
					)
					if trust == 3 then
						vim.cmd("edit " .. fn.fnameescape(path))
						vim.notify("Viewing recipes. Use :w to accept and trust file")
						return
					else
						if trust ~= 1 then
							return
						end
					end
				end

				lib.trust_path(
					path,
					vim.schedule_wrap(function()
						local ok, obj = pcall(vim.json.decode, data)

						if not ok then
							vim.notify(string.format("Failed to parse %s:\n%s", path, obj), vim.log.levels.ERROR)
							return
						end

						local c = 0
						for k, v in pairs(obj) do
							if type(k) ~= "string" then
								api.nvim_err_writeln("Expected string key in %q", path)
								return
							end

							c = c + 1

							v = config.make_recipe(v)

							M.insert(k, v)
						end

						vim.notify(string.format("Loaded %d recipes", c))
					end)
				)
			end)
		end)
	)
end

--- Return a recipe by name
--- @return Recipe|nil
function M.recipe(name)
	return M.recipes[name]
end

--- Execute a recipe by name asynchronously
---@param name string
---@param callback fun(code: number)|nil
function M.bake(name, callback)
	local custom = config.opts.custom_recipes
	local recipe = M.recipe(name) or custom.global[name] or (custom[vim.o.ft] or {})[name]

	if recipe == nil then
		return vim.notify("No recipe: " .. name, vim.log.levels.ERROR)
	end

	M.execute(recipe, name, callback)
end

--- Execute an arbitrary command
---@param recipe Recipe
---@param key string|nil optional key
---@param callback fun(code: number)|nil
function M.execute(recipe, key, callback)
	recipe = config.make_recipe(recipe)
	key = key or recipe.cmd
	-- Execute dependencies before
	local semaphore = { remaining = 1 }

	local function ex(code)
		if semaphore.remaining == nil or code ~= 0 then
			semaphore.remaining = nil
			return
		end

		semaphore.remaining = semaphore.remaining - 1

		if semaphore.remaining == 0 then
			lib.spawn(key, recipe, callback)
		end
	end

	for _, v in ipairs(recipe.depends_on) do
		semaphore.remaining = semaphore.remaining + 1
		if type(v) == "string" then
			M.bake(v, ex)
		else
			M.execute(v, nil, ex)
		end
	end

	ex(0)
end

---@class Frecency
---@field uses number
---@field last_use number

---@type { [string]: Frecency }
local recipe_frecency = {}

local function recipe_score(recipe, now)
	local f = recipe_frecency[recipe[1]] or { uses = 0, last_use = 0 }
	local dur = now - f.last_use
	print(string.format("Duration for: %s: %d", recipe[1], dur))

	return (f.uses + 1) / dur * recipe[3]
end

local function order()
	-- Collect all
	local recipes = M.recipes
	local t = {}

	local custom = config.opts.custom_recipes
	local global = custom.global

	for k, v in pairs(custom[vim.o.ft] or {}) do
		t[k] = { k, v, 0.25 }
	end

	for k, v in pairs(global) do
		t[k] = { k, v, 0.5 }
	end

	for k, v in pairs(recipes) do
		t[k] = { k, v, 1.0 }
	end

	local tasks = lib.get_tasks()
	for k, v in pairs(tasks) do
		t[k] = { k, v.recipe, 2.0 }
	end

	-- Collect into list
	local items = {}
	for _, v in pairs(t) do
		items[#items + 1] = v
	end

	local now = vim.loop.hrtime() / 1000000000
	table.sort(items, function(a, b)
		return recipe_score(a, now) > recipe_score(b, now)
	end)

	return items
end

function M.pick()
	local items = order()

	if #items == 0 then
		return
	end

	local max_len = 0
	for _, v in ipairs(items) do
		max_len = math.max(#v[1], max_len)
	end

	local opts = {
		format_item = function(val)
			local pad = string.rep(" ", math.max(max_len - #val[1]))

			local key = val[1]
			local recipe = val[2]

			return string.format("%s %s%s - %s", lib.get_task(key) and "*" or " ", key, pad, recipe.cmd or recipe)
		end,
	}

	vim.ui.select(items, opts, function(item, idx)
		if not item then
			return
		end

		local r = items[idx]
		if not r then
			return
		end

		local key = r[1]
		local recipe = r[2]

		local f = recipe_frecency[key] or { uses = 0, last_use = 0 }
		f.uses = f.uses + 1
		f.last_use = vim.loop.hrtime() / 1000000000
		recipe_frecency[key] = f

		M.execute(recipe)
	end)
end

function M.complete(lead, _, _)
	local t = {}

	for _, k in ipairs(order()) do
		if k[1]:find(lead) then
			t[#t + 1] = k[1]
		end
	end

	return t
end

local sl = require("recipe.statusline")
function M.statusline()
	local spinner = ""

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
