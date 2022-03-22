local M = {}

local uv = vim.loop

M.installers = {}
M.installers.codelldb =  { program = "extension/adapter/codelldb", cmd = [[
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
}

local dir = vim.fn.stdpath("data") .. "/recipe/"
vim.fn.mkdir(dir, "p")

function M.request(name, callback)
  local installer = M.installers[name]
  if installer == nil then
    return callback(name)
  end

  local path = dir .. name .. "/"

  uv.fs_mkdir(path, 511, function()
    -- assert(not err, "Failed to create " .. path .. ": " .. err or "")
      local prog = path .. installer.program
    uv.fs_stat(prog, vim.schedule_wrap(function(_, stat)
      if stat and stat.type == "file" then
        return callback(prog)
      else
        if vim.fn.confirm("Install " .. name, "&Yes\n&No") ~= 1 then
          return print("Aborting installation")
        end

        require("recipe").execute({ cmd=installer.cmd, raw=true, cwd=path, action = function() callback(prog) end, interactive = false })
      end
    end))
  end)
end

return M
