local has_mason, mason = pcall(require, "mason-registry")

local codelldb = function(on_adapter)
	if not has_mason then
		local util = require("recipe.util")
		util.error("Codelldb requires mason.nvim for installation")
		return
	end
	local pkg = mason.get_package("codelldb")

	local function run()
		local port = vim.fn.rand() % 1000 + 8000
		print("Launching codelldb on port " .. port)
		local stdout = vim.loop.new_pipe(false)
		local stderr = vim.loop.new_pipe(false)

		local cmd = pkg:get_install_path() .. "/extension/adapter/codelldb"

		local handle, pid_or_err

		local opts = {
			stdio = { nil, stdout, stderr },
			args = { "--port=" .. port },
		}

		handle, pid_or_err = vim.loop.spawn(cmd, opts, function(code)
			stdout:close()
			stderr:close()
			handle:close()
			if code ~= 0 then
				print("codelldb exited with code", code)
			end
		end)

		assert(handle, "Error running codelldb: " .. tostring(pid_or_err))

		vim.defer_fn(function()
			on_adapter({
				type = "server",
				host = "127.0.0.1",
				port = port,
			})
		end, 2000)

		stdout:read_start(function(err, chunk)
			assert(not err, err)
			if chunk then
				vim.schedule(function()
					require("dap.repl").append(chunk)
				end)
			end
		end)
		stderr:read_start(function(err, chunk)
			assert(not err, err)
			if chunk then
				vim.schedule(function()
					require("dap.repl").append(chunk)
				end)
			end
		end)
	end

	if not pkg:is_installed() then
		if vim.fn.confirm("Install " .. pkg.name, "&Yes\n&No") ~= 1 then
			return print("Aborting installation")
		end
		pkg:install():once("install:success", run)
	else
		run()
	end
end

return {
	codelldb = codelldb,
}
