local M = {}
local lib = require "recipe.lib"
local api = vim.api

function M.parse_efm(data, cmd, with)
  local expr = table.concat(data)

  local old_efm = vim.o.efm

  local efm = lib.get_efm(cmd)
  print(efm)

  api.nvim_command("doautocmd QuickFixCmdPre recipe")

  vim.o.efm = old_efm .. ", " .. efm

  pcall(api.nvim_command, string.format("noau %s %q", with, expr))

  vim.o.efm = old_efm

  api.nvim_command("doautocmd QuickFixCmdPost recipe")
end

function M.notify(data, cmd)
  local s = table.concat(data)
  vim.notify(string.format("%q:\n%s", cmd, s))
end

return M
