local M = {}
local api = vim.api
local fn = vim.fn
local util = require "recipe.util"

local codelldb = function(on_adapter, cmd)
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  -- CHANGE THIS!
  cmd = cmd or 'codelldb'

  local handle, pid_or_err
  local opts = {
    stdio = {nil, stdout, stderr},
    detached = true,
  }
  handle, pid_or_err = vim.loop.spawn(cmd, opts, function(code)
    stdout:close()
    stderr:close()
    handle:close()
    if code ~= 0 then
      print("codelldb exited with code", code)
    end
  end)

  assert(handle, "Error running codelldb: " .. tostring(pid_or_err))

  stdout:read_start(function(err, chunk)
    assert(not err, err)
    if chunk then
      local port = chunk:match('Listening on port (%d+)')
      if port then
        vim.schedule(function()
          on_adapter({
            type = 'server',
            host = '127.0.0.1',
            port = port
          })
        end)
      else
        vim.schedule(function()
          require("dap.repl").append(chunk)
        end)
      end
    end
  end)
  stderr:read_start(function(err, chunk)
    assert(not err, err)
    if chunk then
      vim.schedule(function()
        require("dap.repl").append(chunk)
      end)
    end
  end)
end

--- @class config
M.options = {
  --- @class term
  --- @field height number
  --- @field width number
  --- @field type string
  --- @field border string
  --- @field adapter table
  term = {
    height = 0.7,
    width = 0.5,
    type = "float",
    border = "shadow"
  },
  actions = {
    qf = function(data, cmd, s) util.qf(data, cmd, "c", s) end,
    loc = function(data, cmd, s) util.qf(data, cmd, "l", s) end,
    dap = require "recipe.dap".launch,
    notify = util.notify,
  },
  recipes_file = "recipes.json",
  --- Define custom global recipes, either globally or by filetype as key
  --- use lib.make_recipe for conveniance
  custom_recipes = require "recipe.ft",
  hooks = {
    pre = { function() vim.cmd(":wa") end }

  },
  adapters = {
    cargo={
      type = "executable",
      command = "codelldb",
      name = "code-lldb",
    }
  }
}

function M.setup(config)
  M.options = vim.tbl_deep_extend("force", M.options, config or {})
  api.nvim_exec (string.format ([[
    augroup Recipe
    au!
    au DirChanged,VimEnter,TabEnter * lua require"recipe".load_recipes(false)
    au BufWritePost %s lua require"recipe".load_recipes(true, vim.fn.expand("%%:p"))
    augroup END
  ]], fn.fnameescape(M.options.recipes_file)), false)

  for k,v in pairs(M.options.custom_recipes) do
    for name,recipe in pairs(v) do
      v[name] = util.make_recipe(recipe)
    end
  end
end

return M
