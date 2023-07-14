local M = {}
local Recipe = require("recipe.recipe")

local Popup = require("nui.popup")

---@param recipe Recipe
function M.open(recipe)
	local popup = Popup({
		enter = true,
		relative = "editor",
		border = "single",
		position = "50%",
		size = {
			width = "80",
			height = "32",
		},
	})

	popup:mount()
end

---@param popup NuiPopup
function M.draw(popup)

function M.test()
	M.open(Recipe:new({ label = "test" }))
end

return M
