local M = {}
local lib = require "recipe.lib"
local api = vim.api

function M.parse_efm(data, recipe, ty)
  local cmd = recipe.cmd

  local old_c = vim.b.current_compiler;

  local old_efm = vim.opt.efm

  local old_makeprg = vim.o.makeprg

  local compiler = lib.get_compiler(recipe.cmd)
  if compiler ~= nil then
    vim.cmd("compiler! " .. compiler)
  end

  api.nvim_command("doautocmd QuickFixCmdPre recipe")

  if ty == "c" then
    vim.fn.setqflist({}, "r", { title = cmd, lines = data })
  else
    vim.fn.setloclist({}, "a", { title = cmd, lines = data })
  end

  api.nvim_command("doautocmd QuickFixCmdPost recipe")

  vim.b.current_compiler = old_c
  vim.opt.efm = old_efm
  vim.o.makeprg = old_makeprg
  if old_c ~= nil then
    vim.cmd("compiler " .. old_c)
  end

end

function M.notify(data, cmd)
  local s = table.concat(data, "\n")
  vim.notify(string.format("%q:\n%s", cmd, s))
end

return M
