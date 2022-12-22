---@class RecipeView
---@field recipe Recipe
---@field task Task|nil
local M = {}
M.__index = M

function M.new(recipe, task)
	return setmetatable({ recipe = recipe, task = task }, M)
end

---@return Task
function M:spawn()
	if not self.task or self.task.state == "stopped" then
		local lib = require("recipe.lib")
		self.task = lib.spawn(self.recipe)
	end

	return self.task
end

function M:stop()
	if self.task then
		self.task:stop()
	end
end

---Focus a running recipe
function M:open_smart()
	self:spawn():focus({})
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

	table.insert(t, self.recipe:format(30))

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