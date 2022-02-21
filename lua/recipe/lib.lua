local api = vim.api
local uv = vim.loop
local fn = vim.fn

local M = {}

local function format_time(ms)
  local h,m,s = 0, 0, 0

  h = math.floor(ms / 3600000)
  ms = ms % 3600000

  m = math.floor(ms / 60000)
  ms = ms % 60000

  s = math.floor(ms / 1000)
  ms = math.floor(ms % 1000)

  local out = ""
  if h > 0 then
    out = out .. h .. "h"
  end
  if m > 0 then
    out = out .. m .. "m"
  end
  if s > 0 then
    out = out .. s .. "s"
  end

  return out
end

local function open_term_win(opts)
  local buf = api.nvim_create_buf(true, true)
  local lines = vim.o.lines
  local cols = vim.o.columns
  local cmdheight = vim.o.cmdheight

  local height = math.ceil(opts.height < 1 and opts.height * lines) or opts.height
  local width = math.ceil(opts.width < 1 and opts.width * cols) or opts.width
  print(width, height)

  local row = math.ceil((lines - height) / 2 - cmdheight)
  local col = math.ceil((cols - width) / 2)

  if opts.type == "float" then
    api.nvim_open_win(buf, true, { relative='editor', row = row, col = col, height=height, width=width, border = "single"})
  elseif opts.type == "split" then
    vim.cmd("split")
    local win = vim.api.nvim_get_current_win()
    api.nvim_win_set_buf(win)
  elseif opts.type == "vsplit" then
    vim.cmd("vsplit")
    local win = vim.api.nvim_get_current_win()
    api.nvim_win_set_buf(win)
  else
    api.nvim_err_writeln("Recipe: Unknown terminal mode " .. opts.type)
  end

  return buf
end

local jobs = {}

_G.__recipe_read = function(id, data, _)
  local job = jobs[id]

  if #job.data < 1000 then
    for _, part in ipairs(data) do
      table.insert(job.data, part)
    end
  end
end

_G.__recipe_exit = function(id, code, _)
  local job = jobs[id]

  local duration = (uv.hrtime() - job.start_time) / 1000000

  local state = code == 0 and "Success" or string.format("Failure %d", code)

  vim.notify(string.format("%s: %q %s", state, job.cmd, format_time(duration)))

  if code == 0 and job.term then
    api.nvim_buf_delete(job.term, {})
  end

  local on_finish = job.opts.on_finish
  if type(on_finish) == "function" then
    on_finish(job.data, job.cmd)
  elseif job.config.actions[on_finish] then
    job.config.actions[on_finish](job.data, job.cmd)
  end

  job[id] = nil
end

vim.api.nvim_exec( [[
  function! RecipeJobRead(j,d,e)
  call v:lua.__recipe_read(a:j, a:d, a:e)
  endfun
  function! RecipeJobExit(j,d,e)
  call v:lua.__recipe_exit(a:j, a:d, a:e)
  endfun
]], false)

-- Execute a command async
function M.execute(cmd, opts, config)
  local start_time = uv.hrtime()

  local job
  local term

  if opts.interactive then
    term = open_term_win(config.term)
    job = vim.fn.termopen(cmd, {
      on_stdout = "RecipeJobRead",
      on_exit = "RecipeJobExit",
      on_stderr = "RecipeJobRead",
    })
  else
    job = vim.fn.jobstart(cmd, {
      on_stdout = "RecipeJobRead",
      on_exit = "RecipeJobExit",
      on_stderr = "RecipeJobRead",
    })
  end

  jobs[job] = {
    opts = opts,
    cmd = cmd,
    config = config,
    start_time = start_time,
    term = term,
    data = {}
  }
end

local function parse_compiler(compiler, t)
  t = t or {}
  local cont = fn.readfile(compiler)

  local in_exp = false

  for _, line in ipairs(cont) do

    local set_start = select(2, line:find("^%s*CompilerSet errorformat[+=]+")) or
  (in_exp and select(2, line:find("^%s*\\")))

    if set_start then
      in_exp = true

      local part = line:sub(set_start + 1)

      -- Remove comment
      local lend = part:find("%c\"")
      if lend then
        part = part:sub(0, lend - 1)
      end


      -- Unescape
      part = part:gsub("\\", "")

      table.insert(t, part)

    else
      in_exp = false
    end

  end
  return t
end


local efm_cache = {}
-- Accumulate an errorformat for all matching commands
function M.get_efm(cmd)
  if efm_cache[cmd] then
    return efm_cache[cmd]
  end

  local efm = {}

  local rtp = fn.escape(vim.o.runtimepath, " ")
  for part in cmd:gmatch('[A-Za-z_-]*') do
    -- check for compiler existance
    local compiler = fn.findfile("compiler/" .. part .. ".vim", rtp)
    if  compiler ~= "" then
      -- Read compiler
      parse_compiler(compiler, efm)
    end

  end

  local r = table.concat(efm, "")
  efm_cache[cmd] = r
  return r
end

return M
