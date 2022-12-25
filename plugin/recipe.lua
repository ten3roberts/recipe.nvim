local api = vim.api

local function execute(o)
	local recipe = require("recipe")
	local Recipe = require("recipe.recipe")
	recipe.execute(Recipe:new({ source = "user", cmd = o.fargs }), not o.bang)
end

local function bake(o)
	local recipe = require("recipe")
	recipe.bake(o.args, not o.band)
end

api.nvim_create_user_command("Execute", execute, { nargs = "*", complete = "shellcmd" })
api.nvim_create_user_command("Ex", execute, { nargs = "*", complete = "shellcmd" })
api.nvim_create_user_command("RecipeBake", bake, {
	complete = function(...)
		local recipe = require("recipe")
		return recipe.complete(...)
	end,
	nargs = "*",
})

api.nvim_create_user_command("RecipeAbort", function()
	local recipe = require("recipe")
	recipe.stop_all()
end, {})
