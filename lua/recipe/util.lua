local M = {}
local fn = vim.fn

function M.get_compiler(cmd)
  local rtp = vim.o.rtp
  for part in cmd:gmatch('%w*') do
    local compiler = fn.findfile("compiler/" .. part .. ".vim", rtp)
    if compiler ~= "" then
      return part
    end
  end
end

--- @class recipe
--- @field cmd string
--- @field cwd string
--- @field interactive boolean
--- @field restart boolean
--- @field action string|function|List|action
M.default_recipe = {
  interactive = false,
  action = "qf",
  uses = 0,
  last_access = 0
}

--- @class action
--- @field name string
--- @field opts table

function M.make_recipe(recipe, interactive)
  if type(recipe) == "string" then
    return {
      cmd = recipe,
      interactive = interactive or false,
      action = "qf",
      uses = 0,
      last_access = 0,
    }
  elseif type(recipe) == "table" then
    return vim.tbl_extend("force", M.default_recipe, recipe)
  else
    vim.api.nvim_err_writeln("Expected recipe to be string or table, found: " .. type(recipe))
  end
end

function M.vim_qf(data, recipe, ty, ok)
  if ok then
    vim.fn.setqflist({}, "r", {})
    vim.cmd (ty .. "close")
    return;
  end
  local cmd = recipe.cmd

  local old_c = vim.b.current_compiler;

  local old_efm = vim.opt.efm

  local old_makeprg = vim.o.makeprg

  local compiler = M.get_compiler(recipe.cmd)
  if compiler ~= nil then
    vim.cmd("compiler! " .. compiler)
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
end

function M.nvim_qf(data, recipe, ty, ok)
  if ok == 0  then
    return require("qf").close "c"
  end

  local cmd = recipe.cmd

  local compiler = M.get_compiler(recipe.cmd)
  if compiler ~= nil then
    vim.cmd("compiler! " .. compiler)
  end

  if #data == 1 and data[1] == "" then
    return
  end

  require("qf").set(ty, {
    title = cmd,
    compiler = compiler,
    cwd = recipe.cwd,
    lines = data,
    open = not ok
  })
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
