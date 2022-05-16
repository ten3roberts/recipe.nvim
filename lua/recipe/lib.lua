local api = vim.api
local config = require "recipe.config"
local uv = vim.loop
local fn = vim.fn

local M = {}

local function remove_escape_codes(s)
  return s:gsub("\x1b%[.-m", ""):gsub("\r", "")
end

function M.format_time(ms)
  local d, h, m, s = 0, 0, 0, 0
  d = math.floor(ms / 86400000)
  ms = ms % 86400000

  h = math.floor(ms / 3600000)
  ms = ms % 3600000

  m = math.floor(ms / 60000)
  ms = ms % 60000

  s = math.floor(ms / 1000)
  ms = math.floor(ms % 1000)

  local t = {}
  if d > 0 then
    t[#t + 1] = d .. "d"
  end
  if h > 0 then
    t[#t + 1] = h .. "h"
  end
  if m > 0 then
    t[#t + 1] = m .. "m"
  end
  if s > 0 then
    t[#t + 1] = s .. "s"
  end

  return table.concat(t, " ")
end

local function open_term_win(win, bufnr)
  local opts = config.options.term
  local lines = vim.o.lines
  local cols = vim.o.columns
  local cmdheight = vim.o.cmdheight

  local height = math.ceil(opts.height < 1 and opts.height * lines) or opts.height
  local width = math.ceil(opts.width < 1 and opts.width * cols) or opts.width

  local row = math.ceil((lines - height) / 2 - cmdheight)
  local col = math.ceil((cols - width) / 2)


  bufnr = bufnr or api.nvim_create_buf(true, true)

  if win then
    api.nvim_win_set_buf(win, bufnr)
  elseif opts.type == "float" then
    win = api.nvim_open_win(bufnr, true,
      {
      relative = 'editor',
      row = row,
      col = col,
      height = height,
      width = width,
      border = opts.border,
    })

    local function close()
      if api.nvim_win_is_valid(win) and api.nvim_get_current_win() ~= win then
        api.nvim_win_close(win, false)
      end
    end

    vim.api.nvim_create_autocmd("WinLeave", { callback = function()
      vim.defer_fn(close, 100);
    end, buffer = bufnr })
  elseif opts.type == "split" then
    vim.cmd("split")
    win = vim.api.nvim_get_current_win()
    api.nvim_win_set_buf(win, bufnr)
  elseif opts.type == "vsplit" then
    vim.cmd("vsplit")
    win = vim.api.nvim_get_current_win()
    api.nvim_win_set_buf(win, bufnr)
  elseif opts.type == "smart" then
    local font_lh_ratio = 0.3
    local w, h = api.nvim_win_get_width(0) * font_lh_ratio, api.nvim_win_get_height(0)
    local cmd = (w > h) and "vsplit" or "split"
    vim.cmd(cmd)
    win = vim.api.nvim_get_current_win()
    api.nvim_win_set_buf(win, bufnr)
  else
    api.nvim_err_writeln("Recipe: Unknown terminal mode " .. opts.type)
  end


  return { buf = bufnr, win = win }
end

---@class Job
---@field recipe Recipe
---@field running boolean
---@field start_time number
---@field id number
---@field term number|nil
---@field data string[]
---@field key string
local job_count = 0
local jobs = {}
local job_names = {}

_G.__recipe_read = function(id, data)
  local job = jobs[id]

  local jdata = job.data
  local jlen = #jdata
  if #data == 0 or jlen > 10000 then return end

  -- Complete prev
  local d = remove_escape_codes(data[1])
  jdata[jlen] = jdata[jlen] .. d

  for i = 2, #data do
    local s = remove_escape_codes(data[i])
    table.insert(jdata, s)
  end
end

local success_codes = {
  [0] = true,
  [130] = true, -- SIGINT
  [129] = true -- SIGTERM
}

_G.__recipe_exit = function(id, code)
  local job = jobs[id]

  local success = success_codes[code] or false

  local duration = (uv.hrtime() - job.start_time) / 1000000

  local level = code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR;

  local state = code == 0 and "Success" or string.format("Failure %d", code)

  vim.notify(string.format("%s: %q %s", state, job.key,
    M.format_time(duration)), level)


  job.running = false
  jobs[id] = nil
  job_count = job_count - 1

  if job.term == nil or (not job.recipe.keep_open and code == 0) then
    if job.term then
      api.nvim_buf_delete(job.term.buf, {})
      job.term = nil
    end
    job_names[job.key] = nil
  else
    local buf = job.term.buf
    api.nvim_create_autocmd("WinClosed", {
      callback = function()
        vim.notify("Closing on au")
        api.nvim_buf_delete(buf, {})
        job.term = nil

        job_names[job.key] = nil
      end,
      buffer = buf
    })
  end

  local function execute_action(action, opts)
    if type(action) == "table" then
      if #action > 0 then
        for _, v in ipairs(action) do
          execute_action(v, action.opts or {})
        end
      else
        execute_action(action.name, action.opts or {})
      end
      return
    end

    local f = config.options.actions[action] or action
    if type(f) == "function" then
      f(job.data or "", job.recipe, success, opts)
    elseif f ~= "" then
      api.nvim_err_writeln("No action: " .. tostring(action))
    end
  end

  local old_cwd = vim.fn.getcwd()

  if job.recipe.cwd then
    api.nvim_set_current_dir(job.recipe.cwd)
  end

  local action = job.recipe.action

  local stat, err = pcall(execute_action, action)

  if not stat then
    api.nvim_err_writeln("Failed to execute recipe actions: " .. err)
  end

  if old_cwd then
    api.nvim_set_current_dir(old_cwd)
  end

end


vim.api.nvim_exec([[
  function! RecipeJobRead(j,d,e)
  call v:lua.__recipe_read(a:j, a:d)
  endfun
  function! RecipeJobExit(j,d,e)
  call v:lua.__recipe_exit(a:j, a:d)
  endfun
]], false)


function M.find_active(key)
  local job = job_names[key]
  return job
end

function M.focus(job)
  if job.term then
    local win = fn.bufwinid(job.term.buf)
    if win ~= -1 then
      api.nvim_set_current_win(win)
    else
      open_term_win(nil, job.term.buf)
    end
  end

  return true
end

function M.active_jobs()
  return job_count, jobs
end

function M.is_active(key)
  local job = job_names[key]
  return (job and job.running == true) or false
end

function M.stop_all()
  for i in pairs(jobs) do
    fn.jobstop(i)
  end
end

-- Execute a command async
function M.execute(key, recipe)
  local start_time = uv.hrtime()

  local id
  local term

  local cmd = recipe.raw and recipe.cmd or recipe.cmd:gsub("([%%#][:phtre]*)", fn.expand):gsub("(<%a+>[:phtre]*)", fn.expand)

  local cur_win = api.nvim_get_current_win()
  for _, hook in ipairs(config.options.hooks.pre) do
    hook(recipe)
  end

  local job = M.find_active(key)
  if job then
    if not job.running or recipe.restart then
      -- Reuse window if the old jobs terminal exists and is visible
      if job.term then
        local term_buf = job.term.buf
        local win = fn.bufwinid(term_buf)
        if win ~= -1 then
          term = open_term_win(win)
          api.nvim_buf_delete(job.term.buf, {})
          job.term = nil
        end
      end

      if job.running then
        vim.notify("Stopping job")
        fn.jobstop(job.id)
        fn.jobwait({ job.id }, 1000)
      end
    else
      M.focus(job)
      if not recipe.focus then
        api.nvim_set_current_win(cur_win)
      end
      return
    end
  end

  if recipe.interactive then
    term = term or open_term_win()

    api.nvim_set_current_win(term.win)

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

  job = {
    recipe = recipe,
    start_time = start_time,
    id = id,
    term = term,
    data = { "" },
    key = key,
    running = true,
  }

  if id <= 0 then
    api.nvim_err_writeln("Failed to start job")
    return
  end

  job = {
    recipe = recipe,
    running = true,
    start_time = start_time,
    id = id,
    term = term,
    data = { "" },
    key = key,
  }

  recipe.uses = recipe.uses + 1
  recipe.last_access = uv.hrtime() / 1000000000

  jobs[id] = job
  job_names[key] = job
  job_count = job_count + 1


  if not recipe.focus then
    api.nvim_set_current_win(cur_win)
  end
end

local trusted_paths = nil
local trusted_paths_dir = fn.stdpath("cache") .. "/recipe"
local trusted_paths_path = trusted_paths_dir .. "/trusted_paths.json"

--- @diagnostic disable
function M.read_file(path, callback)
  uv.fs_open(path, "r", 438, function(err, fd)
    if err then return callback() end
    uv.fs_fstat(fd, function(err, stat)
      assert(not err, err)
      uv.fs_read(fd, stat.size, 0, function(err, data)
        assert(not err, err)
        uv.fs_close(fd, function(err)
          assert(not err, err)
          return callback(data)
        end)
      end)
    end)
  end)
end

--- @diagnostic disable
local function write_file(path, data, callback)
  uv.fs_open(path, "w", 438, function(err, fd)
    assert(not err, err)
    uv.fs_write(fd, data, 0, function(err)
      assert(not err, err)
      uv.fs_close(fd, function(err)
        assert(not err, err)
        return callback()
      end)
    end)
  end)
end

function M.trusted_paths(callback)
  if trusted_paths then return callback(trusted_paths) end

  M.read_file(trusted_paths_path, vim.schedule_wrap(function(data)
    trusted_paths = data and fn.json_decode(data) or {}
    callback(trusted_paths)
  end))
end

function M.is_trusted(path, callback)
  path = fn.fnamemodify(path, ":p")
  M.trusted_paths(function(paths)
    callback(paths[path] == fn.getftime(path))
  end)
end

function M.trust_path(path, callback)
  path = fn.fnamemodify(path, ":p")

  M.trusted_paths(function(paths)
    local cur = paths[path]
    local new = fn.getftime(path)
    if cur == new then
      return callback()
    end

    paths[path] = new
    fn.mkdir(trusted_paths_dir, "p")
    local data = fn.json_encode(trusted_paths);
    write_file(trusted_paths_path, data, callback)
  end)

end

return M
