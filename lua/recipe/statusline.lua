local M = {}
local uv = vim.loop

local spinner = {
  "·     ",
  " ·    ",
  "  ·   ",
  "   ·  ",
  "    · ",
  "   ·  ",
  "  ·   ",
  " ·    ",
}

local current = 0

function M.next()
  local n = ((current) % #spinner) + 1
  current = n
end

local timer

local playing = false
function M.start()
  if not timer then
    timer = uv.new_timer()
  end

  if playing then return end

  playing = true
  timer:start(200, 200, vim.schedule_wrap(function()
    vim.cmd "redraw"
    M.next()
  end))
end

function M.stop()
  if not timer or not playing then return end

  playing = false
  timer:stop()
end

function M.get_spinner()
  return spinner[current] or ""
end

return M
