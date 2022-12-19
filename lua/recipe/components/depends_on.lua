local M = {}

function M.setup()
	require("recipe.components").register("depends_on", {})
	require("recipe.components").alias("depends_on", "dependencies")
end

return M
