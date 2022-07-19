local M = {}
local api = vim.api
local util = require("recipe.util")

local adapters = require("recipe.adapters")
---@class config
---@field custom_recipes table<string, Recipe>
---@field term term customize terminal
---@field default_recipe Recipe
M.options = {
	---@class term
	---@field height number
	---@field width number
	---@field type string
	---@field border string
	---@field adapter table
	---@field jump_to_end boolean to the end/bottom of terminal
	term = {
		height = 0.7,
		width = 0.5,
		type = "smart",
		border = "shadow",
		jump_to_end = true,
	},
	actions = {
		qf = function(data, cmd, s)
			util.qf(data, cmd, "c", s)
		end,
		loc = function(data, cmd, s)
			util.qf(data, cmd, "l", s)
		end,
		dap = require("recipe.dap").launch,
		notify = util.notify,
	},
	recipes_file = "recipes.json",
	--- Define custom global recipes, either globally or by filetype as key
	custom_recipes = require("recipe.ft"),
	hooks = {
		pre = {
			function()
				vim.cmd(":wa")
			end,
		},
	},
	---@class Recipe
	---@field cmd string
	---@field cwd string
	---@field interactive boolean
	---@field restart boolean
	---@field action string|function|action[]|action
	---@field keep_open boolean Keep terminal open on success
	---@field focus boolean Focus the spawned terminal
	default_recipe = {
		interactive = false,
		restart = false,
		action = "qf",
		uses = 0,
		last_access = 0,
		keep_open = false,
		focus = true,
	},
	adapters = {
		cargo = adapters.codelldb,
		cmake = adapters.codelldb,
		make = adapters.codelldb,
	},
}

---@class action
---@field name string
---@field opts table
--
---@param recipe string|Recipe
---@tag recipe.make_recipe
function M.make_recipe(recipe)
	if type(recipe) == "string" then
		return vim.tbl_deep_extend("force", M.options.default_recipe, { cmd = recipe })
	elseif type(recipe) == "table" then
		-- Do merge in place to preserve ref
		for k, v in pairs(M.options.default_recipe) do
			if recipe[k] == nil then
				recipe[k] = v
			end
		end

		return recipe
	else
		vim.api.nvim_err_writeln("Expected recipe to be string or table, found: " .. type(recipe))
	end
end

function M.setup(config)
	M.options = vim.tbl_deep_extend("force", M.options, config or {})

	-- api.nvim_exec(string.format([[
	--   augroup Recipe
	--   au!
	--   au DirChanged,VimEnter,TabEnter * lua require"recipe".load_recipes(false)
	--   au BufWritePost %s lua require"recipe".load_recipes(true, vim.fn.expand("%%:p"))
	--   au TermEnter
	--   augroup END
	-- ]], fn.fnameescape(M.options.recipes_file)), false)

	-- Expand custom recipes
	for _, v in pairs(M.options.custom_recipes) do
		for name, recipe in pairs(v) do
			v[name] = M.make_recipe(recipe)
		end
	end
end

return M
