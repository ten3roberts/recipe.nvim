local Split = require("nui.split")
local NuiLine = require("nui.line")
local NuiText = require("nui.text")
local Popup = require("nui.popup")

---@class Section
---@field lstart integer
---@field len integer
---@field render: fun(self: Section, put: fun(line: NuiLine))

---@class TaskView
---@field task Task
---@field lines NuiLine[]
local TaskView = {}
TaskView.__index = TaskView

function TaskView:new(task)
	return setmetatable({ task = task, lines = {} }, TaskView)
end

function TaskView:update()
	table.insert(
		lines,
		NuiLine({ (NuiText(pad(task.key, 1), "Identifier")), NuiText(" "), NuiText(task.recipe:fmt_cmd()) })
	)

	local cwd = vim.fn.fnamemodify(task.recipe.cwd, ":p:.")
	if #cwd > 0 then
		table.insert(lines, NuiLine({ NuiText("cwd ", "Identifier"), NuiText(cwd) }))
	end

	table.insert(lines, NuiLine({ NuiText(string.upper(task.state), state_color[task.state]) }))

	if task.bufnr and vim.api.nvim_buf_is_valid(task.bufnr) then
		local task_lines = task:get_tail_output(4)
		table.insert(lines, NuiLine({ NuiText("Output:") }))

		for i = 1, 4 do
			table.insert(lines, NuiLine({ indent, NuiText(task_lines[i] or " ") }))
		end
	end

	table.insert(lines, NuiLine({}))
end

---@class Panel
---@field split Split
---@field lines NuiLine[]
---@field sections Section
---@field num_lines integer
local Panel = {}

Panel.__index = Panel

function Panel:new()
	local panel = {}

	local split = Popup({
		relative = "editor",
		position = "50%",
		enter = true,
		-- size = 16,
		size = {
			width = "80%",
			height = "60%",
		},
	})

	split:mount()

	panel.split = split

	return setmetatable(panel, Panel)
end

---@return Task[]
local function ordered_tasks()
	local lib = require("recipe.lib")

	local t = {}
	for _, task in pairs(lib.all_tasks()) do
		if not task.recipe.hidden then
			table.insert(t, task)
		end
	end

	local now = vim.loop.now()

	table.sort(t, function(a, b)
		return lib.score(a, now, nil) > lib.score(b, now, nil)
	end)

	return t
end

local state_color = {
	pending = "Blue",
	running = "Green",
	stopped = "Red",
}

local function pad(s, len)
	return s .. string.rep(" ", math.max(0, len - #s))
end
local indent = NuiText("    ")
function Panel:update_tasks()
	self.sections = {}
	for k, task in pairs(ordered_tasks()) do
		local len = 16
		local section = {
			lstart = self.num_lines + 1,
			len = len,
			render = function(self, put)
				put(
					NuiLine({ (NuiText(pad(task.key, 1), "Identifier")), NuiText(" "), NuiText(task.recipe:fmt_cmd()) })
				)

				local cwd = vim.fn.fnamemodify(task.recipe.cwd, ":p:.")
				if #cwd > 0 then
					put(NuiLine({ NuiText("cwd ", "Identifier"), NuiText(cwd) }))
				end

				put(NuiLine({ NuiText(string.upper(task.state), state_color[task.state]) }))

				if task.bufnr and vim.api.nvim_buf_is_valid(task.bufnr) then
					local task_lines = task:get_tail_output(4)
					put(NuiLine({ NuiText("Output:") }))

					for i = 1, 4 do
						put(NuiLine({ indent, NuiText(task_lines[i] or " ") }))
					end
				end
			end,
		}

		table.insert(self.sections, section)
	end
end

function Panel:render()
	local lines = {}

	local ns_id = self.split.ns_id
	local bufnr = self.split.bufnr

	table.insert(lines, NuiLine({ NuiText("Task Overview", "String") }))

	local lib = require("recipe.lib")
	local indent = NuiText("    ")

	for _, section in ipairs(self.sections) do
		local cursor = section.lstart
		local put = function(line)
			print("Drawing line: " .. cursor)
			line:render(bufnr, ns_id, cursor)
			cursor = cursor + 1
		end

		section.render(section, put)
	end
end

local panel = Panel:new()
panel:update_tasks()
panel:render()
