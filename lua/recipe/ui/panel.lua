local Split = require("nui.split")
local NuiLine = require("nui.line")
local NuiText = require("nui.text")
local Popup = require("nui.popup")

---@class Section
---@field lstart integer
---@field len integer
---@field render: fun(self): NuiLine[]

---@class Panel
---@field window NuiPopup
---@field lines NuiLine[]
---@field sections Section
---@field task_map table<string, integer>
---@field num_lines integer
local Panel = {}

Panel.__index = Panel

local active_panels = {}

function Panel:new()
	local panel = { num_lines = 0, task_map = {} }

	local split = Popup({
		relative = "editor",
		position = "100%",
		enter = true,
		-- size = 16,
		size = {
			width = 60,
			height = 24,
		},
	})

	split:on("BufHidden", function()
		vim.notify("Panel hidden")
		active_panels[split.bufnr] = nil
	end, {})

	panel.window = split

	return setmetatable(panel, Panel)
end

function Panel:mount()
	self.window:mount()

	active_panels[self.window.bufnr] = self
end

function Panel:unmount()
	if self.window.bufnr then
		active_panels[self.window.bufnr] = nil
	end

	self.window:unmount()
end

---@return table<integer, Panel>
function Panel.get_active()
	return active_panels
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

---@param render fun(section: Section): NuiLine[]
---@return integer
function Panel:push_section(render, len)
	local section = {
		lstart = self.num_lines + 1,
		len = len,
		render = render,
	}

	table.insert(self.sections, section)
	self.num_lines = self.num_lines + len
	return #self.sections
end

local indent = NuiText("    ")
function Panel:update_tasks()
	self.sections = {}
	self.num_lines = 0
	self.task_map = {}

	self:push_section(function(_)
		return { NuiLine({ NuiText("Task Overview", "String") }) }
	end, 1)

	local lib = require("recipe.lib")
	local recent = lib.recent()
	for from_end = 1, #recent do
		local i = #recent - from_end + 1
		local task = recent[i]

		local function render()
			local t = {}

			local task_state = NuiText(pad(string.upper(task.state), #"STOPPED"), state_color[task.state])

			table.insert(
				t,
				NuiLine({
					task_state,
					NuiText(" "),
					(NuiText(pad(task.key, 1), "Identifier")),
					NuiText(" "),
					NuiText(task.recipe:fmt_cmd()),
				})
			)

			local cwd = vim.fn.fnamemodify(task.recipe.cwd, ":p:.")
			if #cwd > 0 then
				table.insert(t, NuiLine({ NuiText("cwd ", "Identifier"), NuiText(cwd) }))
			end

			if task.bufnr and vim.api.nvim_buf_is_valid(task.bufnr) then
				local task_lines = task:get_tail_output(4)

				for i, line in ipairs(task_lines) do
					table.insert(t, NuiLine({ NuiText(tostring(i), "Number"), indent, NuiText(line) }))
				end
			end

			return t
		end

		local section_idx = self:push_section(render, 6)
		self.task_map[task.key] = section_idx
	end
end

---@param task Task
function Panel:rerender_task(task)
	local section_idx = self.task_map[task.key]
	if section_idx then
		local section = self.sections[section_idx]
		self:render_section(section)
	else
		vim.notify("Task not in panel" .. task.key)
	end
end

function Panel:render_section(section)
	local ns_id = self.window.ns_id
	local bufnr = self.window.bufnr

	local lines = section.render(section)
	local blank = NuiLine({ NuiText("----") })
	if #lines > section.len then
		lines[section.len] = NuiLine({ NuiText("...") })
	end

	for i = 1, section.len do
		local line = lines[i] or blank
		line:render(bufnr, ns_id, section.lstart + i - 1)
	end
end

function Panel:render()
	for _, section in ipairs(self.sections) do
		self:render_section(section)
	end
end

function Panel:refresh()
	self:update_tasks()
	self:render()
end

local panel = nil
function Panel:open()
	if not panel then
		panel = Panel:new()
	end
	panel:mount()
	panel:update_tasks()
	panel:render()
end

function Panel:close()
	if not panel then
		return
	end

	panel:unmount()
	panel = nil
end

return Panel
