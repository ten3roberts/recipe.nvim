local api = vim.api
local uv = vim.loop
local fn = vim.fn

local M = {}

-- Execute a command async
function M.execute(cmd, on_finish)
  local shell = vim.env.SHELL

  local stdin = uv.new_pipe()
  local stdout = uv.new_pipe()
  local stderr = uv.new_pipe()

  local job_data = {}

  local handle
  local on_exit = function(code)
    local state = code == 0 and "Success" or string.format("Failure %d", code)

    vim.notify(string.format("%s: %q", state, cmd))

    stdin:close()
    stdout:close()
    stderr:close()

    print(table.concat(job_data, ""))

    on_finish(job_data, cmd)
  end

  handle = uv.spawn(shell, {
    stdio = {nil, stdout, stderr},
    args = { "-c", cmd }
  }, vim.schedule_wrap(on_exit))

  if not handle then
    api.nvim_err_writeln(string.format("Command not found: %q", cmd))
    stdin:close()
    stdout:close()
    stderr:close()
    return
  end


  uv.read_start(stdout, function(_, data)
    if data then
      table.insert(job_data, data)
    end
  end)

  uv.read_start(stderr, function(_, data)
    if data then
      table.insert(job_data, data)
    end
  end)
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

-- Accumulate an errorformat for all matching commands
function M.get_efm(cmd)

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

  return table.concat(efm, "")
end

print(vim.inspect(M.get_efm("cargo")))

return M
