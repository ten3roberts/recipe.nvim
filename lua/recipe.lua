local api = vim.api
local fn = vim.fn

local lib = require "recipe.lib"
local util = require "recipe.util"
local config = require "recipe.config"

local M = {}


--- Provide a custom config
--- @param opts config
function M.setup(opts)
  config.setup(opts)

  local group = api.nvim_create_augroup("Recipe", { clear = true })
  local function au(event, o)
    o.group = group
    api.nvim_create_autocmd(event, o)
  end

  au({ "DirChanged", "VimEnter" }, { callback = function()
    M.load_recipes(false)
  end })

  au({ "BufWritePost" }, { pattern = config.options.recipes_file, callback = function(o)
    M.load_recipes(true, o.file)
  end })

  if config.options.term.jump_to_end then
    au("TermOpen", { callback = function()
      vim.cmd "normal! G"
    end })
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
  local t = util.make_recipe(recipe)
  M.recipes[name] = t
end

M.stop_all = lib.stop_all

--- Loads recipes from `recipes.json`
function M.load_recipes(force, path)
  path = path or config.options.recipes_file
  local cwd = fn.fnamemodify(path, ":p:h");
  local old_cwd = fn.getcwd()
  api.nvim_set_current_dir(cwd)

  if not force and loaded_paths[cwd] ~= nil then
    return
  end

  loaded_paths[cwd] = true;

  lib.read_file(path, vim.schedule_wrap(function(data)
    if not data or #data == 0 then
      return
    end

    lib.is_trusted(path, function(trusted)
      if not trusted and not force then
        local mtime = fn.getftime(path)
        local strtime = fn.strftime("%c", mtime)
        local dur = lib.format_time((fn.localtime() - mtime) * 1000)
        local trust = fn.confirm(string.format("Trust recipes from %q?\nModified %s (%s ago)", path, strtime, dur), "&Yes\n&No\n&View file", 2)
        if trust == 3 then
          vim.cmd("edit " .. fn.fnameescape(path))
          vim.notify("Viewing recipes. Use :w to accept and trust file")
          return
        else if trust ~= 1 then return end
        end
      end

      lib.trust_path(path, vim.schedule_wrap(function()
        local obj = fn.json_decode(data)

        local c = 0
        for k, v in pairs(obj) do
          if type(k) ~= "string" then
            api.nvim_err_writeln("Expected string key in %q", path);
            return
          end

          c = c + 1

          v = util.make_recipe(v)
          api.nvim_set_current_dir(cwd)
          v.cwd = fn.fnamemodify(v.cwd or cwd, ":p")

          M.insert(k, v)
        end

        vim.notify(string.format("Loaded %d recipes", c))
        api.nvim_set_current_dir(old_cwd)
      end))
    end)
  end))
end

--- Return a recipe by name
--- @return Recipe|nil
function M.recipe(name)
  return M.recipes[name]
end

--- Execute a recipe asynchronously
function M.bake(name)
  local custom = config.options.custom_recipes
  local recipe = M.recipe(name)
      or custom.global[name]
      or (custom[vim.o.ft] or {})[name]

  if type(recipe) == "string" then
    lib.execute(name, util.make_recipe(recipe))
  elseif type(recipe) == "table" then
    lib.execute(name, recipe)
  else
    api.nvim_err_writeln("No recipe: " .. name)
  end
end

---Execute an arbitrary command
---@param cmd string
---@param interactive boolean|nil
---@param keep_open boolean|nil
function M.execute(cmd, interactive, keep_open)
  local t = util.make_recipe(cmd, interactive, keep_open)
  lib.execute(t.cmd, t)
end

local function recipe_score(recipe, now)
  local dur = now - (recipe[2].last_access or 0)

  return ((recipe[2].uses or 0) + 1) / dur * recipe[3]

end

local function order()
  -- Collect all
  local recipes = M.recipes
  local t = {}

  local custom = config.options.custom_recipes
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

  local _, jobs = lib.active_jobs()
  for _, v in pairs(jobs) do
    t[v.key] = { v.key, v.recipe, 2.0 }
  end

  -- Collect into list
  local items = {}
  for _, v in pairs(t) do
    items[#items + 1] = v
  end

  local now = vim.loop.hrtime() / 1000000000
  table.sort(items, function(a, b) return recipe_score(a, now) > recipe_score(b, now) end)
  return items
end

function M.pick()
  local items = order()

  if #items == 0 then
    return
  end

  local max_len = 0;
  for _, v in ipairs(items) do
    max_len = math.max(#v[1], max_len)
  end

  local opts = {
    format_item = function(val)
      local pad = string.rep(" ", math.max(max_len - #val[1]))
      return string.format("%s %s%s - %s", lib.is_active(val[1]) and "*" or " ", val[1], pad, val[2].cmd or val[2])
    end,
  }

  vim.ui.select(items, opts, function(item, idx)
    if not item then return end

    local r = items[idx]
    if not r then return end
    M.bake(r[1])
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

local sl = require "recipe.statusline"
function M.statusline()
  local spinner = ""
  if lib.active_jobs() > 0 then
    sl.start()
    spinner = sl.get_spinner()
  else
    sl.stop()
  end

  return spinner
end

_G.__recipe_complete = M.complete

api.nvim_exec([[
  function! RecipeComplete(lead, cmd, cur)
    return v:lua.__recipe_complete(a:lead, a:cmd, a:cur)
  endfun
]], true)

return M
