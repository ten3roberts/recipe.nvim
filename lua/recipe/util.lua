local M = {}
local lib = require "recipe.lib"

function M.vim_qf(data, recipe, ty, status)
  if status == 0 then
    vim.fn.setqflist({}, "r", {})
    vim.cmd (ty .. "close")
    return;
  end
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

function M.nvim_qf(data, recipe, ty, status)
  local cmd = recipe.cmd

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

  require("qf").set(ty, {
    title = cmd,
    compiler = compiler,
    lines = data,
    open = status ~= 0
  })

  if old_cwd then
    vim.cmd("noau cd " .. old_cwd)
  end
end

local function module_exists(name)
  if package.loaded[name] then
    return true
  else
    for _, searcher in ipairs(package.searchers or package.loaders) do
      local loader = searcher(name)
      if type(loader) == 'function' then
        package.preload[name] = loader
        return true
      end
    end
    return false
  end
end

if module_exists("qf") then
  M.qf = M.nvim_qf
else
  M.qf = M.vim_qf
end

function M.notify(data, cmd)
  local s = table.concat(data, "\n")
  vim.notify(string.format("%q:\n%s", cmd, s))
end

return M
