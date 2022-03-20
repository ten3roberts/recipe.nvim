local util = require "recipe.util"

local M = {}

local dap = require("dap")
local has_setup = false
function M.setup()
  local config = require "recipe.config"
  if has_setup then return end
  has_setup = true
  for k,v in pairs(config.options.adapters) do
    dap.adapters["recipe-" .. k] = v
  end
end

--- @param _ string
--- @param recipe recipe
--- @param opts table
function M.launch(_, recipe, code, opts)
  if code ~= 0 then
    return
  end
  M.setup()
  local compiler = util.get_compiler(recipe.cmd)
  local config = require "recipe.config"
  local conf = vim.tbl_extend ("force", {
    type="recipe-" .. compiler,
    request = "launch",
    cwd=recipe.cwd,
    name = "Recipe " .. recipe.cmd,
  }, opts)

  dap.run(conf)
end

return M
