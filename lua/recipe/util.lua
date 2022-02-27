local M = {}
local lib = require "recipe.lib"

function M.parse_efm(data, recipe, ty)
  local cmd = recipe.cmd

  local old_c = vim.b.current_compiler;

  local old_efm = vim.opt.efm

  local old_makeprg = vim.o.makeprg

  local compiler = lib.get_compiler(recipe.cmd)
  if compiler ~= nil then
    vim.cmd("compiler! " .. compiler)
  end

  local old_cwd
  if recipe.cwd then
    old_cwd = vim.fn.getcwd()
    vim.cmd("noau cd " .. recipe.cwd)
  end

  if #data == 1 and data[1] == "" then
    return
  end

  print(table.concat(data, "\n"))

  if ty == "c" then
    vim.fn.setqflist({}, "r", { title = cmd, lines = data })
    vim.cmd("copen | wincmd p")
  else
    vim.fn.setloclist(".", {}, "r", { title = cmd, lines = data })
    vim.cmd("lopen | wincmd p")
  end



  vim.b.current_compiler = old_c
  vim.opt.efm = old_efm
  vim.o.makeprg = old_makeprg
  if old_c ~= nil then
    vim.cmd("compiler " .. old_c)
  end

  if old_cwd then
    vim.cmd("noau cd " .. old_cwd)
  end

end

function M.notify(data, cmd)
  local s = table.concat(data, "\n")
  vim.notify(string.format("%q:\n%s", cmd, s))
end

return M
