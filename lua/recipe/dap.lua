local util = require "recipe.util"

local M = {}

local has_dap, dap = pcall(require, "dap")
local has_setup = false
function M.setup()
  if not has_dap then
    return
  end
  local config = require "recipe.config"
  if has_setup then return end
  has_setup = true
  for k, v in pairs(config.options.adapters) do
    dap.adapters["recipe-" .. k] = v
  end
end

--- @param _ string
--- @param recipe Recipe
--- @param opts table
function M.launch(_, recipe, ok, opts)
  if not ok then
    return
  end

  M.setup()
  local compiler = util.get_compiler(recipe.cmd)
  local conf = vim.tbl_extend("force", {
    type = opts.adapter or ("recipe-" .. compiler:lower()),
    request = "launch",
    cwd = recipe.cwd,
    name = "Recipe " .. recipe.cmd,
  }, opts)

  dap.run(conf)
end

return M
