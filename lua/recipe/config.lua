local M = {}
local api = vim.api
local fn = vim.fn
local util = require "recipe.util"
--- @class config
M.options = {
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
    qf = function(data, cmd, s) util.qf(data, cmd, "c", s) end,
    loc = function(data, cmd, s) util.qf(data, cmd, "l", s) end,
    notify = util.notify,
  },
  recipes_file = "recipes.json",
  --- Define custom global recipes, either globally or by filetype as key
  --- use lib.make_recipe for conveniance
  custom_recipes = require "recipe.ft",
  hooks = {
    pre = { function() vim.cmd(":wa") end }

  }
}

function M.setup(config)
  M.options = vim.tbl_deep_extend("force", M.options, config or {})
  api.nvim_exec (string.format ([[
    augroup Recipe
    au!
    au DirChanged,VimEnter,TabEnter * lua require"recipe".load_recipes()
    au BufWritePost %s lua require"recipe".load_recipes(true)
    augroup END
  ]], fn.fnameescape(M.options.recipes_file)), false)


  setmetatable(M.options.custom_recipes, M.options.custom_recipes)
end

return M
