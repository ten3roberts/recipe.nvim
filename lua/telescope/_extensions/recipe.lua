local async = require("plenary.async")
return require("telescope").register_extension({
	setup = function(ext_config, config)
		-- access extension config and user config
	end,
	exports = {
		pick_recipe = async.void(require("recipe.ui.telescope").pick),
		pick_local = async.void(require("recipe.ui.telescope").pick_local),
	},
})
