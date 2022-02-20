local fn = vim.fn
local api = vim.api

local lib = require "recipe.lib"


local function publish_qf(data, cmd)
  local expr = table.concat(data)

  local old_efm = vim.o.efm

  local efm = lib.get_efm(cmd)
  print(efm)

  api.nvim_command("doautocmd QuickFixCmdPre recipe")

  vim.o.efm = old_efm .. ", " .. efm

  pcall(api.nvim_command, string.format("cgetexpr %q", expr))

  vim.o.efm = old_efm

  api.nvim_command("doautocmd QuickFixCmdPost recipe")
end

lib.execute("sleep 0.3 && rg function", publish_qf)
lib.execute("cargo --version", publish_qf)
