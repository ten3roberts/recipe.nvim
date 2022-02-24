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
  term = {
    height = 0.7,
    width = 0.5,
    type = "float"
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
    au BufWrite %s lua require"recipe".load_config()
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
  on_finish = "qf"
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
    t = vim.tbl_extend("force", default_recipe, { cmd = recipe })
  else
    t = vim.tbl_extend("force", default_recipe, recipe)
  end

  M.recipes[name] = t
end

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
  if type(recipe) == "string" then
    local t = vim.tbl_extend("force", default_recipe, { cmd = recipe })
    lib.execute(t, M.config)
  elseif type(recipe) == "table" then
    lib.execute(recipe, M.config)
  else
    api.nvim_err_writeln("No recipe: " .. name)
  end
end

return M
