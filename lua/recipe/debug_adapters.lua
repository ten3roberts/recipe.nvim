local codelldb = function(on_adapter)
	local port = vim.fn.rand() % 1000 + 8000
	print("Launching codelldb on port " .. port)
	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)

	require("recipe.install").request("codelldb", function(cmd)
		local handle, pid_or_err
		local opts = {
			stdio = { nil, stdout, stderr },
			args = { "--port=" .. port },
		}

		print(cmd)

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
				-- local port = chunk:match('Listening on port (%d+)')
				-- if port then
				-- else
				vim.schedule(function()
					require("dap.repl").append(chunk)
				end)
				-- end
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
	end)
end

return {
	codelldb = codelldb,
}
