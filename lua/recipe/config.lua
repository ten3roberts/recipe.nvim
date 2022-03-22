local M = {}
local api = vim.api
local fn = vim.fn
local util = require "recipe.util"

local adapters = require("recipe.adapters")
--- @class config
M.options = {
  --- @class term
  --- @field height number
  --- @field width number
  --- @field type string
  --- @field border string
  --- @field adapter table
  term = {
    height = 0.7,
    width = 0.5,
    type = "float",
    border = "shadow"
  },
  actions = {
    qf = function(data, cmd, s) util.qf(data, cmd, "c", s) end,
    loc = function(data, cmd, s) util.qf(data, cmd, "l", s) end,
    dap = require "recipe.dap".launch,
    notify = util.notify,
  },
  recipes_file = "recipes.json",
  --- Define custom global recipes, either globally or by filetype as key
  --- use lib.make_recipe for conveniance
  custom_recipes = require "recipe.ft",
  hooks = {
    pre = { function() vim.cmd(":wa") end }

  },
  adapters = {
    cargo=adapters.codelldb,
  }
}

function M.setup(config)
  M.options = vim.tbl_deep_extend("force", M.options, config or {})
  api.nvim_exec (string.format ([[
    augroup Recipe
    au!
    au DirChanged,VimEnter,TabEnter * lua require"recipe".load_recipes(false)
    au BufWritePost %s lua require"recipe".load_recipes(true, vim.fn.expand("%%:p"))
    au ExitPre * RecipeAbort
    augroup END
  ]], fn.fnameescape(M.options.recipes_file)), false)

  for k,v in pairs(M.options.custom_recipes) do
    for name,recipe in pairs(v) do
      v[name] = util.make_recipe(recipe)
    end
  end
end

return M
