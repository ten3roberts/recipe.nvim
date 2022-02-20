local api = vim.api
local uv = vim.loop

local M = {}

-- Execute a command async
function M.execute(cmd, on_finish)
  local shell = vim.env.SHELL

  local stdin = uv.new_pipe()
  local stdout = uv.new_pipe()
  local stderr = uv.new_pipe()

  local job_data = {}

  local on_exit = function(code)
    local state = code == 0 and "Success" or string.format("Failure %d", code)

    vim.notify(string.format("%s: %q", state, cmd))

    stdin:close()
    stdout:close()
    stderr:close()

    print(table.concat(job_data, ""))

    on_finish(job_data, cmd)

  end

  local handle = uv.spawn(shell, {
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

return M
