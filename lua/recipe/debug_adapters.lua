local has_mason, mason = pcall(require, "mason-registry")

local codelldb = function(on_adapter)
	local pkg = mason.get_package("codelldb")

	local function run()
		local port = vim.fn.rand() % 1000 + 8000
		print("Launching codelldb on port " .. port)
		local stdout = vim.loop.new_pipe(false)
		local stderr = vim.loop.new_pipe(false)

		vim.notify("Installed codelldb")
		local cmd = pkg:get_install_path() .. "/extension/adapter/codelldb"

		vim.notify("Spawning codelldb server: " .. cmd)
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
		vim.notify("codelldb already installed")
		run()
	end
end

return {
	codelldb = codelldb,
}
