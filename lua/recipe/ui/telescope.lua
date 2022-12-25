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
			---@type RecipeView
			local value = entry.value

			local root = value.recipe:display()

			local tree = NuiTree({ bufnr = bufnr, nodes = { root } })

			local util = require("recipe.ui.util")

			util.expand_tree(tree, 3)

			tree:render()
		end,
	})

	return previewer
end

local RecipeView = require("recipe.ui.recipe_view")

function M.recipe_action(method, close)
	return function(prompt)
		if close then
			actions.close(prompt)
		end

		local sel = action_state.get_selected_entry()
		---@type RecipeView
		local value = sel.value

		value[method](value)
		if not close then
			local current_picker = action_state.get_current_picker(prompt)
			current_picker:refresh()
		end
	end
end

M.actions = {
	open_smart = M.recipe_action("open_smart", true),
	open = M.recipe_action("open", true),
	open_split = M.recipe_action("open_split", true),
	open_vsplit = M.recipe_action("open_vsplit", true),
	open_float = M.recipe_action("open_float", true),
	stop = M.recipe_action("stop", false),
	spawn = M.recipe_action("spawn", false),
}

-- our picker function: colors
function M.pick(opts)
	opts = opts or {}

	local recipes = providers.load(1000)
	local tasks = lib.get_tasks()

	local t = {}

	for key, recipe in pairs(recipes) do
		local task = tasks[recipe.name]
		if not recipe.hidden or task then
			table.insert(t, RecipeView:new(key, recipe, task))
		end
	end

	local now = vim.loop.hrtime() / 1e9

	table.sort(t, function(a, b)
		return lib.score(a.recipe, a.task, now) > lib.score(b.recipe, b.task, now)
	end)

	pickers
		.new(opts, {
			prompt_title = "Recipes",
			previewer = new_previewer(),
			finder = finders.new_table({
				results = t,
				entry_maker = function(entry)
					---@type Recipe
					local fmt = entry:format()

					return {
						value = entry,
						display = fmt,
						ordinal = entry.key .. " " .. entry.recipe:fmt_cmd(),
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			attach_mappings = function(_, map)
				actions.select_default:replace(M.actions.open)
				actions.select_horizontal:replace(M.actions.open_split)
				actions.select_vertical:replace(M.actions.open_vsplit)
				actions.select_tab:replace(M.actions.spawn)
				map({ "i", "n" }, "<C-d>", M.actions.stop)
				return true
			end,
		})
		:find()
end

return M
