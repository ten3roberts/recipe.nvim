local api = vim.api
local fn = vim.fn

local lib = require "recipe.lib"
local util = require "recipe.util"

local M = {}

--- @class config
--- @field term term
--- @field actions table key-value pairs for on_finish actions
--- @field config_file string
M.config = {
  --- @class term
  --- @field height number
  --- @field width number
  --- @field type string
  --- @field border string
  term = {
    height = 0.7,
    width = 0.5,
    type = "float",
    border = "shadow"
  },
  actions = {
    qf = function(data, cmd) util.parse_efm(data, cmd, "c") end,
    loc = function(data, cmd) util.parse_efm(data, cmd, "l") end,
    notify = util.notify,
  },
  config_file = "recipes.json"
}

--- Provide a custom config
--- @param config config
function M.setup(config)
  M.config = vim.tbl_deep_extend("force", M.config, config or {})
  api.nvim_exec (string.format ([[
    augroup Recipe
    au!
    au DirChanged,VimEnter lua require"recipe".load_config()
    au BufWritePost %s lua require"recipe".load_config()
    augroup END
  ]], fn.fnameescape(M.config.config_file)), false)

  M.load_config()
end


--- @class recipe
--- @field cmd string
--- @field interactive boolean
--- @field on_finish string|function
local default_recipe = {
  interactive = false,
  on_finish = "qf",
  uses = 0,
  last_access = 0
}


M.recipes = {}

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
  local t
  if type(recipe) == "string" then
    t = lib.make_recipe(name)
  else
    t = vim.tbl_extend("force", default_recipe, recipe)
  end

  M.recipes[name] = t
end


M.stop_all = lib.stop_all

--- Loads recipes from `recipes.json`
function M.load_config()
  local path = M.config.config_file
  local f = io.open(path, "r")

  if not f then
    vim.notify("No recipes")
    return
  end


  local lines = {}
  for line in f:lines() do
    lines[#lines + 1] = line
  end

  local obj = fn.json_decode(lines)

  local c = 0
  for k,v in pairs(obj) do
    if type(k) ~= "string" then
      api.nvim_err_writeln("Expected string key in %q", path);
      return
    end

    c = c + 1
    M.insert(k, v)
  end

  vim.notify(string.format("Loaded %d recipes", c))
end

--- Return a recipe by name
--- @return recipe|nil
function M.recipe(name)
  return M.recipes[name]
end

local filetypes = require "recipe.ft"

--- Execute a recipe asynchronously
function M.bake(name)
  local recipe = M.recipe(name) or filetypes[vim.o.ft][name]
  if recipe then
    lib.execute(name, recipe, M.config)
  else
    api.nvim_err_writeln("No recipe: " .. name)
  end
end

function M.execute(cmd)
    local t = lib.make_recipe(cmd)
    lib.execute(cmd, t, M.config)
end

local function recipe_score(recipe, now)
  local dur = now - recipe.last_access

  return recipe.uses / dur

end

local function order()
  local t = {}
  for k,v in pairs(M.recipes) do
    t[#t+1] = {k,v}
  end

  for k,v in pairs(filetypes[vim.o.ft]) do
    if not M.recipes[k] then
    t[#t+1] = {k,v}
    end
  end

  local now = vim.loop.hrtime() / 1000000000
  table.sort(t, function(a,b) return recipe_score(a[2], now) >  recipe_score(b[2], now) end)
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
    M.bake(r[1])
  end)
end

function M.complete(lead, _, _)
  lead = lead .. ".*"
  local t = {}
  for k,_ in pairs(M.recipes) do
    if k:gmatch(lead) then
      t[#t+1] = k
    end
  end

  for k,_ in pairs(filetypes[vim.o.ft]) do
    if k:gmatch(lead) then
      t[#t+1] = k
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
