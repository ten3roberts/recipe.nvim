local M = {}
local util = require("recipe.util")

---@class Config
---@field custom_recipes table<string, Recipe>
---@field term TermConfig customize terminal
---@field default_recipe Recipe
---@field adapter table
---@field dotenv string Load path as dotenv before spawn
M.opts = {
	---@class TermConfig
	term = {
		height = 0.5,
		width = { 120, 0.5 },
		kind = "smart",
		border = "none",
		global_terminal = true,
	},
	scroll_to_end = true,
	recipes_file = "recipes.json",
	--- Define custom recipes, global and per filetype
	custom_recipes = {
		global = {},
		filetypes = {
			rust = {
				build = { cmd = "cargo build" },
				check = { cmd = "cargo check" },
				clippy = { cmd = "cargo clippy" },
				clean = { cmd = "cargo clean" },
				run = { cmd = "cargo run" },
				test = { cmd = "cargo test --all-features" },
				doc = { cmd = "cargo doc --open" },
			},
			python = {
				run = { cmd = "python %" },
				build = { cmd = "python -m py_compile %" },
				check = { cmd = "python -m py_compile %" },
			},
			glsl = {
				check = { cmd = "glslangValidator -V %" },
			},
			html = {
				build = { cmd = "live-server %" },
				check = { cmd = "live-server %" },
				run = { cmd = "live-server %" },
			},
			lua = {
				build = { cmd = "luac %" },
				check = { cmd = "luac %" },
				clean = { cmd = "rm luac.out" },
				lint = { cmd = "luac %" },
				run = { cmd = "lua %" },
			},
			svelte = {
				run = { cmd = "npm run dev -- --open" },
			},
		},
	},
	hooks = {
		pre = {
			function(_)
				vim.cmd(":wa")
			end,
		},
	},

	---@type ProviderDef[]
	providers = {
		{ name = "lsp" },
		{ name = "recipes" },
		{ name = "make" },
		{ name = "ft" },
		{ name = "custom" },
	},

	--- The components which are attached to all recipes
	default_components = {
		qf = {},
	},

	debug_adapters = {
		rust = require("recipe.debug_adapters").codelldb,
		c = require("recipe.debug_adapters").codelldb,
		cpp = require("recipe.debug_adapters").codelldb,
	},

	dotenv = ".env",
}

function M.setup(config)
	M.opts = vim.tbl_deep_extend("force", M.opts, config or {})

	--- Setup the default providers
	require("recipe.providers.recipes").setup()
	require("recipe.providers.lsp").setup()
	require("recipe.providers.make").setup()
	require("recipe.providers.custom").setup(M.opts.custom_recipes.global)
	require("recipe.providers.ft").setup(M.opts.custom_recipes.filetypes)
end

return M
