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
end

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
--- @param recipe recipe|string
function M.insert(name, recipe)
  local t = util.make_recipe(recipe)
  M.recipes[name] = t
end

M.stop_all = lib.stop_all

--- Loads recipes from `recipes.json`
function M.load_recipes(force, path)
  path = path or config.options.recipes_file
  local cwd = fn.fnamemodify(path, ":p:h");

  if not force and loaded_paths[cwd] ~= nil then
    return
  end

  loaded_paths[cwd ] = true;

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
        for k,v in pairs(obj) do
          if type(k) ~= "string" then
            api.nvim_err_writeln("Expected string key in %q", path);
            return
          end

          c = c + 1

          v = vim.tbl_extend("keep", util.make_recipe(v), { cwd = cwd })

          M.insert(k, v)
        end

        vim.notify(string.format("Loaded %d recipes", c))
      end))
    end)
  end))
end

--- Return a recipe by name
--- @return recipe|nil
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
    lib.execute(name, lib.make_recipe(recipe))
  elseif type(recipe) == "table" then
    lib.execute(name, recipe)
  else
    api.nvim_err_writeln("No recipe: " .. name)
  end
end

-- Execute an arbitrary command
-- @params cmd string
-- @params interactive bool
function M.execute(cmd, interactive)
  local t = util.make_recipe(cmd, interactive)
  lib.execute(cmd, t)
end

local function recipe_score(recipe, now)
  local dur = now - (recipe[2].last_access or 0)

  return ((recipe[2].uses or 0) + 1) / dur * recipe[3]

end

local function order()
  local recipes = M.recipes
  local t = {}
  for k,v in pairs(recipes) do
    t[#t+1] = {k,v,1.0}
  end

  local custom = config.options.custom_recipes
  local global = custom.global
  for k,v in pairs(global) do
    if not M.recipes[k] then
      t[#t+1] = {k,v,0.5}
    end
  end

  for k,v in pairs(custom[vim.o.ft] or {}) do
    if not recipes[k] and not global[k] then
      t[#t+1] = {k,v, 0.25}
    end
  end

  local now = vim.loop.hrtime() / 1000000000
  table.sort(t, function(a,b) return recipe_score(a, now) > recipe_score(b, now) end)
  return t
end

function M.pick()
  local items = order()

  if #items == 0 then
    return
  end

  local opts = {
    format_item = function(val)
      return
      string.format("%s %s - %s", lib.is_active( val[1] ) and "*" or " ", val[1], val[2].cmd or val[2])
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

  for _,k in ipairs(order()) do
    if k[1]:find(lead) then
      t[#t+1] = k[1]
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

api.nvim_exec( [[
  function! RecipeComplete(lead, cmd, cur)
    return v:lua.__recipe_complete(a:lead, a:cmd, a:cur)
  endfun
]], true)

return M
