local M = {}

---@class Task
---@field stop fun()
---@field focus fun()
---@field restart fun(cb: fun(code: number): Task|nil): Task
---@field recipe Recipe

local adapters = require("recipe.adapters")

---@class Config
---@field custom_recipes table<string, Recipe>
---@field term TermConfig customize terminal
---@field default_recipe Recipe
---@field adapter table
M.opts = {
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
	---@field kind string
	---@field plain boolean
	---@field env table|nil
	---@field opts table Extra options for the current backend
	default_recipe = {
		kind = "build",
		opts = {},
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
		recipe = vim.tbl_deep_extend("force", M.opts.default_recipe, { cmd = recipe })
	elseif type(recipe) == "table" then
		recipe = vim.tbl_deep_extend("force", M.opts.default_recipe, recipe)
	else
		vim.api.nvim_err_writeln("Expected recipe to be string or table, found: " .. type(recipe))
	end

	--- Normalize the working directory
	recipe.cwd = vim.loop.fs_realpath(recipe.cwd or ".")

	return recipe
end

function M.setup(config)
	M.opts = vim.tbl_deep_extend("force", M.opts, config or {})

	for _, v in pairs(M.opts.custom_recipes) do
		for name, recipe in pairs(v) do
			v[name] = recipe
		end
	end
end

return M
