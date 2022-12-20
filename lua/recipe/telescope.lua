local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local themes = require("telescope.themes")

local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local providers = require("recipe.providers")
local lib = require("recipe.lib")

local M = {}

local last_used = {}

local function score(v, now)
	local last_use = last_used[v.key] or 0

	return 1 / (now - last_use)
end

-- our picker function: colors
function M.pick(opts)
	opts = opts or {}

	local recipes = providers.load(1000)
	local tasks = lib.get_tasks()

	local t = {}
	for k, v in pairs(recipes) do
		table.insert(t, { key = k, recipe = v, task = tasks[k] })
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
					local recipe = entry.recipe
					local fmt = recipe:format(34)

					return {
						value = entry,
						display = fmt,
						ordinal = fmt,
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					local now = vim.loop.hrtime() / 1e9
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					local value = selection.value

					print("Selection: ", vim.inspect(value))
					last_used[value.key] = now

					require("recipe").execute(value.recipe)
				end)
				return true
			end,
		})
		:find()
end

return M
