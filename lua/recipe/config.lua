local M = {}
local core = require("recipe.core")
local Recipe = core.Recipe
local util = require("recipe.util")

---@class Task
---@field stop fun()
---@field focus fun()
---@field restart fun(on_start: fun(task: Task|nil), on_exit: fun(code: number): Task|nil): Task
---@field callbacks fun(code: number)[] added by lib
---@field recipe Recipe

---@class Config
---@field custom_recipes table<string, Recipe>
---@field term TermConfig customize terminal
---@field default_recipe Recipe
---@field adapter table
---@field dotenv string Load path as dotenv before spawn
M.opts = {
	---@class TermConfig
	term = {
		height = 0.7,
		width = 0.5,
		kind = "smart",
		border = "shadow",
		jump_to_end = true,
		auto_close = false,
	},
	recipes_file = "recipes.json",
	--- Define custom recipes, global and per filetype
	custom_recipes = {
		global = {},
		filetypes = {
			rust = {
				build = { cmd = "cargo build --bins -q" },
				check = { cmd = "cargo check --bins --examples -q" },
				clippy = { cmd = "cargo clippy -q" },
				clean = { cmd = "cargo clean -q" },
				run = { cmd = "cargo run", kind = "term" },
				test = { cmd = "cargo test --all-features", kind = "term", keep_open = false },
				doc = { cmd = "cargo doc -q --open" },
			},
			python = {
				run = { cmd = "python %", kind = "term" },
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
				run = { cmd = "npm run dev -- --open", kind = "term" },
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

	adapters = {
		term = require("recipe.adapters.term"),
		build = require("recipe.adapters.build"),
		dap = require("recipe.adapters.dap"),
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
