---@class RecipeView
---@field task Task|nil
---@field key string
local M = {}
M.__index = M

function M:new(key, task)
	return setmetatable({ key = key, task = task }, M)
end

---@return Task
function M:spawn()
	if self.task.state == "stopped" then
		self.task:spawn()
	end

	return self.task
end

function M:stop()
	if self.task then
		self.task:stop()
	end
end

function M:open()
	self:spawn():focus({})
end

---Focus a running recipe
function M:open_smart()
	self:spawn():focus({ kind = "smart" })
end

function M:open_float()
	self:spawn():focus({ kind = "float" })
end

function M:open_split()
	self:spawn():focus({ kind = "split" })
end

function M:open_vsplit()
	self:spawn():focus({ kind = "vsplit" })
end

local task_state_map = {
	pending = "-",
	running = "*",
	stopped = "#",
}

function M:format()
	local t = {}
	local task = self.task

	if task then
		table.insert(t, task_state_map[task.state] or "?")
	else
		table.insert(t, " ")
	end

	table.insert(t, self.task.recipe:format(self.key, 30))

	return table.concat(t, " ")
end

function M:quick_action()
	local actions = {
		{
			"open vsplit",
			function()
				M:open_vsplit()
			end,
		},
		{
			"open split",
			function()
				M:open_split()
			end,
		},
		{
			"open_smat",
			function()
				M:open_smart()
			end,
		},
		{
			"spawn",
			function()
				M:spawn()
			end,
		},
	}

	vim.ui.select(actions, {
		format_item = function(item)
			return item[1]
		end,
	}, function(item)
		item[2]()
	end)
end

return M
