local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values

local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local providers = require("recipe.providers")
local lib = require("recipe.lib")

local M = {}

---@param v RecipeView
local function score(v, now)
	local last_use = lib.last_used[v.recipe.name] or 0

	return (v.task and 10 or 1) / (now - last_use)
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
	for _, recipe in pairs(recipes) do
		local task = tasks[recipe.name]
		if not recipe.hidden or task then
			table.insert(t, RecipeView.new(recipe, task))
		end
	end

	local now = vim.loop.hrtime() / 1e9

	table.sort(t, function(a, b)
		return score(a, now) > score(b, now)
	end)

	pickers
		.new(opts, {
			prompt_title = "Recipes",
			finder = finders.new_table({
				results = t,
				entry_maker = function(entry)
					---@type Recipe
					local fmt = entry:format()

					return {
						value = entry,
						display = fmt,
						ordinal = entry.recipe.name .. " " .. entry.recipe:fmt_cmd(),
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			attach_mappings = function(_, map)
				actions.select_default:replace(M.actions.open_smart)
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
