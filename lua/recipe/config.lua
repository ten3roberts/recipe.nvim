local M = {}

---@class Task
---@field stop fun()
---@field focus fun()
---@field restart fun(cb: fun(code: number): Task|nil): Task
---@field callback fun(code: number) added by lib
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
			function(_)
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
	---@field depends_on (string|Recipe)[]
	default_recipe = {
		cmd = "",
		kind = "build",
		opts = {},
		restart = false,
		plain = false,
		depends_on = {},
	},

	adapters = {
		cargo = adapters.codelldb,
		cmake = adapters.codelldb,
		make = adapters.codelldb,
	},
}

---@param recipe Recipe
---@tag recipe.make_recipe
function M.make_recipe(recipe)
	if type(recipe) ~= "table" then
		vim.notify("Recipe must be of kind table")
		return { cmd = "" }
	end
	recipe = vim.tbl_deep_extend("force", M.opts.default_recipe, recipe)

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
