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

function M.make_recipe(cmd)
  return {
    cmd = cmd,
    interactive = false,
    on_finish = "qf",
    uses = 0,
    last_access = 0,
  }
end

local function open_term_win(buf, opts)
  local lines = vim.o.lines
  local cols = vim.o.columns
  local cmdheight = vim.o.cmdheight

  local height = math.ceil(opts.height < 1 and opts.height * lines) or opts.height
  local width = math.ceil(opts.width < 1 and opts.width * cols) or opts.width
  print(width, height)

  local row = math.ceil((lines - height) / 2 - cmdheight)
  local col = math.ceil((cols - width) / 2)

  local win
  if opts.type == "float" then
    win = api.nvim_open_win(buf, true,
    {
        relative='editor',
        row = row,
        col = col,
        height=height,
        width=width,
        border = opts.border,
      })
  elseif opts.type == "split" then
    vim.cmd("split")
    win = vim.api.nvim_get_current_win()
    api.nvim_win_set_buf(win)
  elseif opts.type == "vsplit" then
    vim.cmd("vsplit")
    win = vim.api.nvim_get_current_win()
    api.nvim_win_set_buf(win)
  else
    api.nvim_err_writeln("Recipe: Unknown terminal mode " .. opts.type)
  end

  return { buf = buf, win = win}
end

local job_count = 0
local jobs = {}
local job_names = {}

_G.__recipe_read = function(id, data)
  local job = jobs[id]

  local jdata = job.data
  local jlen = #jdata
  if #data == 0 or jlen > 1000 then return end

  -- Complete prev
  jdata[jlen] = jdata[jlen] .. data[1]

  for i=2,#data do
    table.insert(jdata, data[i])
  end
end

_G.__recipe_exit = function(id, code)
  local job = jobs[id]

  if not job.recipe.interactive then
    local duration = (uv.hrtime() - job.start_time) / 1000000

    local state = code == 0 and "Success" or string.format("Failure %d", code)


    vim.notify(string.format("%s: %q %s", state, job.recipe.cmd,
      format_time(duration)))
  end

  if code == 0 and job.term then
    api.nvim_buf_delete(job.term.buf, {})
  end

  local on_finish = job.recipe.on_finish
  if type(on_finish) == "function" then
    on_finish(job.data, job.recipe)
  elseif type(on_finish) == "string" then
    local f = job.config.actions[on_finish]
    if f then
      f(job.data, job.recipe)
    else
      api.nvim_err_writeln("No action: " .. on_finish)
    end
  end

  job_names[job.key] = nil
  job[id] = nil
  job_count = job_count - 1
end

vim.api.nvim_exec( [[
  function! RecipeJobRead(j,d,e)
  call v:lua.__recipe_read(a:j, a:d)
  endfun
  function! RecipeJobExit(j,d,e)
  call v:lua.__recipe_exit(a:j, a:d)
  endfun
]], false)

function M.focus(key)
  local job = job_names[key]
  if not job then
    return false
  end

  if job.term then
    local win = fn.bufwinid(job.term.buf)
    if win ~= -1 then
      api.nvim_set_current_win(win)
    else
      open_term_win(job.term.buf, job.config.term)
    end
  end

  return true
end

function M.active_jobs()
  return job_count
end

function M.is_active(key)
  return job_names[key] ~= nil
end

function M.stop_all()
  for i in pairs(jobs) do
    fn.jobstop(i)
  end
end

-- Execute a command async
function M.execute(key, recipe, config)
  local start_time = uv.hrtime()

  local id
  local term

  local fname = fn.expand("%.")
  local cmd = recipe.cmd:gsub("%%", fname)

  if M.focus(key) then
    return
  end

  if recipe.interactive then
    local buf = api.nvim_create_buf(true, true)
    term = open_term_win(buf, config.term)
    id = vim.fn.termopen(cmd, {
      cwd = recipe.cwd,
      on_stdout = "RecipeJobRead",
      on_exit = "RecipeJobExit",
      on_stderr = "RecipeJobRead",
    })
  else
    id = vim.fn.jobstart(cmd, {
      cwd = recipe.cwd,
      on_stdout = "RecipeJobRead",
      on_exit = "RecipeJobExit",
      on_stderr = "RecipeJobRead",
    })
  end

  if id <= 0 then
    api.nvim_err_writeln("Failed to start job")
    return
  end

  local job = {
    recipe = recipe,
    config = config,
    start_time = start_time,
    term = term,
    data = {""},
    key = key,
  }

  recipe.uses = recipe.uses + 1
  recipe.last_access = uv.hrtime() / 1000000000

  jobs[id] = job
  job_names[key] = job
  job_count = job_count + 1
end

function M.get_compiler(cmd)
  local rtp = vim.o.rtp
  for part in cmd:gmatch('[A-Za-Z_-]*') do
    local compiler = fn.findfile("compiler/" .. part .. ".vim", rtp)
    if  compiler ~= "" then
      return part
    end
  end
end



return M
