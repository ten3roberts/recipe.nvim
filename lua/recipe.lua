local fn = vim.fn
local api = vim.api

local job = require "recipe.job"


local function publish_qf(data, cmd)
  local expr = table.concat(data)

  api.nvim_command("doautocmd QuickFixCmdPre recipe")
  api.nvim_command(string.format("cgetexpr %q", expr))
  fn.setqflist({}, "r", { title = cmd })
  api.nvim_command("doautocmd QuickFixCmdPost recipe")
end

job.execute("rg function", publish_qf)
