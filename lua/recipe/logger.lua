local log = require("plenary.log")

return log.new({
	plugin = "recipe",
	highlights = false,
	use_console = vim.env.RECIPE_LOG_CONSOLE or false,
	use_file = vim.env.RECIPE_LOG_FILE or false,
	level = vim.env.RECIPE_LOG_LEVEL or "info",
})
