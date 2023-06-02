local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values

local actions = require("telescope.actions")
local previewers = require("telescope.previewers")
local action_state = require("telescope.actions.state")
local providers = require("recipe.providers")
local lib = require("recipe.lib")

local M = {}

local function new_previewer()
	local NuiTree = require("nui.tree")

	local function get_bufnr(self, status)
		if not self.state.bufnr then
			self.state.bufnr = vim.api.nvim_win_get_buf(status.preview_win)
		end
		return self.state.bufnr
	end

	local previewer = previewers.Previewer:new({
		preview_fn = function(self, entry, status)
			local bufnr = get_bufnr(self, status)
			---@type Task
			local task = entry.value

			local root = task.recipe:display()

			local tree = NuiTree({ bufnr = bufnr, nodes = { root } })

			local util = require("recipe.ui.util")

			util.expand_tree(tree, 3)

			tree:render()
		end,
	})

	return previewer
end

function M.task_action(method, close)
	return function(prompt_bufnr)
		local selection = {}

		local util = require("recipe.util")
		local picker = action_state.get_current_picker(prompt_bufnr)
		if not picker then
			util.error("Failed go get current picker")
			return
		end

		if #picker:get_multi_selection() > 0 then
			for _, item in ipairs(picker:get_multi_selection()) do
				table.insert(selection, item)
			end
		else
			table.insert(selection, action_state.get_selected_entry())
		end

		---@type Task

		vim.schedule(function()
			for _, sel in ipairs(selection) do
				local value = sel.value
				value[method](value)
			end
		end)

		if picker and close then
			actions.close(prompt_bufnr)
		end

		if not close then
			picker:refresh()
		end
	end
end

M.actions = {
	open_smart = M.task_action("open_smart", true),
	open = M.task_action("open", true),
	open_split = M.task_action("open_split", true),
	open_vsplit = M.task_action("open_vsplit", true),
	open_float = M.task_action("open_float", true),
	menu = M.task_action("menu", true),
	stop = M.task_action("stop", false),
	spawn = M.task_action("spawn", true),
	restart = M.task_action("restart", true),
}

-- our picker function: colors
function M.pick(opts)
	opts = opts or {}

	local t = {}

	local tasks = lib.load()

	for _, task in pairs(tasks) do
		if not task.recipe.hidden then
			table.insert(t, task)
		end
	end

	local now = vim.loop.now()

	local util = require("recipe.util")
	local pos = util.get_position()

	table.sort(t, function(a, b)
		return lib.score(a, now, pos) > lib.score(b, now, pos)
	end)

	pickers
		.new(opts, {
			prompt_title = "Recipes",
			previewer = new_previewer(),
			finder = finders.new_table({
				results = t,
				entry_maker = function(entry)
					---@type Task
					local fmt = entry:format()

					return {
						value = entry,
						display = fmt,
						ordinal = fmt,
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			attach_mappings = function(_, map)
				actions.select_default:replace(M.actions.open)
				actions.select_horizontal:replace(M.actions.open_split)
				actions.select_vertical:replace(M.actions.open_smart)
				actions.select_tab:replace(M.actions.spawn)
				map({ "i", "n" }, "<C-r>", M.actions.restart)
				map({ "i", "n" }, "<C-f>", M.actions.open_float)
				map({ "i", "n" }, "<C-d>", M.actions.stop)
				map({ "i", "n" }, "<C-e>", M.actions.menu)
				return true
			end,
		})
		:find()
end

return M
