local M = {}

---@class RecipeAdapter
---@field kind string
---@field config table
local default_adapter = {
	kind = "build",
	config = {},
}

---@class Task
---@field stop fun()
---@field focus fun()
---@field restart fun(): Task
---@field recipe Recipe

local adapters = require("recipe.adapters")

---@class Config
---@field custom_recipes table<string, Recipe>
---@field term TermConfig customize terminal
---@field default_recipe Recipe
---@field adapter table
M.options = {
	---@class TermConfig
	term = {
		height = 0.7,
		width = 0.5,
		type = "smart",
		border = "single",
		jump_to_end = true,
		auto_close = false,
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
	---@field adapter Adapter
	---@field restart boolean
	---@field plain boolean
	---@field action string|function|action[]|action
	---@field keep_open boolean Keep terminal open on success
	---@field focus boolean Focus the spawned terminal
	---@field env table|nil
	default_recipe = {
		---@class Adapter
		---@field kind string
		---@field config table
		adapter = { kind = "build", config = {} },
		restart = false,
		plain = false,
	},

	adapters = {
		cargo = adapters.codelldb,
		cmake = adapters.codelldb,
		make = adapters.codelldb,
	},
}

---@param recipe string|Recipe
---@tag recipe.make_recipe
function M.make_recipe(recipe)
	if type(recipe) == "string" then
		recipe = vim.tbl_deep_extend("force", M.options.default_recipe, { cmd = recipe })
	elseif type(recipe) == "table" then
		recipe = vim.tbl_deep_extend("force", M.options.default_recipe, recipe)
	else
		vim.api.nvim_err_writeln("Expected recipe to be string or table, found: " .. type(recipe))
	end

	recipe.cwd = vim.loop.fs_realpath(recipe.cwd or ".")

	return recipe
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
			v[name] = recipe
		end
	end
end

return M
