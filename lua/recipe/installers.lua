local M = {}

local uv = vim.loop

M.installers = {}
M.installers.codelldb =  [[
    os=$(uname);
    arch=$(uname -m);
    if [ "$os" = "Linux" ]; then
      case $(uname -m) in
        x86_64) wget -O CodeLLDB.zip "https://github.com/vadimcn/vscode-lldb/releases/latest/download/codelldb-x86_64-linux.vsix" ;;
        aarch64|arm64) wget -O CodeLLDB.zip "https://github.com/vadimcn/vscode-lldb/releases/latest/download/codelldb-aarch64-linux.vsix" ;;
      esac
    elif [ "$os" = "Darwin" ]; then
      case $(uname -m) in
        x86_64) wget -O CodeLLDB.zip "https://github.com/vadimcn/vscode-lldb/releases/latest/download/codelldb-x86_64-darwin.vsix" ;;
        aarch64|arm64) wget -O CodeLLDB.zip "https://github.com/vadimcn/vscode-lldb/releases/latest/download/codelldb-aarch64-darwin.vsix" ;;
      esac
    fi;
    unzip -u CodeLLDB.zip
    rm -f CodeLLDB.zip
  ]]

local dir = vim.fn.stdpath("data") .. "/recipe/"
vim.fn.mkdir(dir, "p")

function M.ensure_installed(name, callback)
  local cmd = M.installers[name]
  if cmd == nil then
    return callback()
  end

  local path = dir .. name
  uv.fs_mkdir(path, 0511, function(err)
    assert(err, "Failed to create " .. path)
    uv.fs_stat(path, vim.schedule_wrap(function(_, stat)
      if stat and stat.type == "directory" then
        return callback()
      else
        require("recipe").execute({ cmd=cmd, raw=true, cwd=path, action = callback, interactive = false })
      end
    end))
  end)


end

return M
