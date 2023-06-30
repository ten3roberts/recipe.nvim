local M = {}
local util = require("recipe.util")

---@class Executable
---@field name string
---@field path string
---@field kind string

---@param task Task
---@return Executable
local function find_executables(task)
	local output = task.stdout
	local t = {}
	for _, line in ipairs(output) do
		local ok, a = pcall(vim.json.decode, line)

		if ok then
			assert(a)
			---@type string|nil
			if a.reason == "build-finished" then
				break
			end

			if a.reason == "compiler-artifact" then
				local executable = a.executable
				assert(executable, "Missing executable")
				local kind = a.target.kind

				local name = a.target.name
				local profile = a.profile

				print("Found artifact: " .. vim.inspect(a))

				if vim.tbl_contains(kind, "bin") or vim.tbl_contains(kind, "example") or profile.test == true then
					local ex = {
						name = name,
						path = executable,
						kind = (kind or {})[1],
						test = profile.test,
					}

					print("Found executable " .. vim.inspect(ex))

					table.insert(t, ex)
				end
			end
		end
	end

	return t
end
local _, dap = pcall(require, "dap")
return {
	---@class DapParams
	params = {
		close_task = true,
		adapter = nil,
		args = nil,
		program = nil,
		justMyCode = true,
		env = nil,
	},
	---@param params DapParams
	new = function(_, params)
		return {
			on_exit = function(task)
				if task.code ~= 0 then
					util.log_error("Build failed, skipping debug")
					return
				end

				local executables = find_executables(task)

				vim.notify("Found executables: " .. vim.inspect(executables))

				---@param executable Executable
				local function launch(executable)
					if params.close_task ~= false then
						task:close()
					end

					local conf = {
						type = params.adapter or vim.o.ft,
						request = "launch",
						name = "Recipe " .. task.recipe.label,
						program = executable.path,
						args = params.args,
						justMyCode = params.justMyCode,
						env = vim.tbl_extend("keep", params.env or {}, task.env),
					}

					if dap then
						vim.notify("Launching dap session: " .. vim.inspect(conf))
						dap.terminate()
						vim.schedule(function()
							dap.run(conf)
						end)
					else
						util.log_error("Dap could not be found")
					end
				end

				if #executables == 0 then
					util.log_error("Failed to find executable in build output")
				-- elseif #executables == 1 then
				-- 	launch(executables[1])
				else
					vim.ui.select(executables, {
						prompt = "Select executable:",
						format_item = function(item)
							return table.concat({ item.name, item.kind, item.path }, " - ")
						end,
					}, function(item)
						if item then
							launch(item)
						end
					end)
				end
			end,
		}
	end,
}
