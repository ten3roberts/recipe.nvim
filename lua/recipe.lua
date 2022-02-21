local fn = vim.fn
local api = vim.api

local lib = require "recipe.lib"
local util = require "recipe.util"

local M = {}

M.config = {
  term = {
    height = 0.7,
    width = 0.5,
    type = "float"
  },
  actions = {
    qf = function(data, cmd) util.parse_efm(data, cmd, "cgetexpr") end,
    loc = function(data, cmd) util.parse_efm(data, cmd, "lgetexpr") end,
    notify = util.notify,
 }
}

function M.setup(config)
  M.config = vim.tbl_deep_extend("force", M.config, config)
end


lib.execute("ls -a", { on_finish = "notify", interactive = true}, M.config)

return M
