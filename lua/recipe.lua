local api = vim.api

local lib = require "recipe.lib"
local util = require "recipe.util"

local M = {}

---@class config
---@field term term
---@field actions table key-value pairs for on_finish actions
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
  }
}

--- Provide a custom config
--- @param config config
function M.setup(config)
  M.config = vim.tbl_deep_extend("force", M.config, config)
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

--- Execute a recipe by name
--- @param name string
--- @param recipe recipe
function M.insert_recipe(name, recipe)
  local t = vim.tbl_extend("force", default_recipe, recipe)

  M.recipes[name] = t

end

--- Return a recipe by name
--- @return recipe|nil
function M.recipe(name)
  return M.recipes[name]
end

--- Execute a recipe asynchronously
function M.bake(name)
  local recipe = M.recipe(name)
  if recipe then
    lib.execute(recipe, M.config)
  else
    api.nvim_err_writeln("No recipe: " .. name)
  end

end


lib.execute({cmd = "cargo build --color=never", cwd = "../../rust/waves", on_finish = "qf", interactive = true}, M.config)
-- lib.execute({cmd = "ls ~/", on_finish = "notify", interactive = false}, M.config)


return M
