local utils = require("recipe.util")
local deferred_refresh = utils.throttle(function()
	local Panel = require("recipe.ui.panel")
	for _, panel in pairs(Panel.get_active()) do
		panel:refresh()
	end
end, 200)

return {
	params = {},
	new = function()
		local Panel = require("recipe.ui.panel")
		local update_task = utils.throttle(
			vim.schedule_wrap(function(task)
				for _, panel in pairs(Panel.get_active()) do
					panel:rerender_task(task)
				end
			end),
			1000
		)

		return {
			on_start = deferred_refresh,
			on_output = update_task,
			on_exit = vim.schedule_wrap(function(task)
				update_task.stop()
				update_task.call_now(task)
				deferred_refresh()
			end),
		}
	end,
}
