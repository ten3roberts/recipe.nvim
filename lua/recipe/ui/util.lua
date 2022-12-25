local M = {}

---@param lines NuiLine[]
function M:fill_buffer(lines, bufnr)
	for i, line in ipairs(lines) do
		line:render(bufnr, -1, i)
	end
end

local function get_tree_nodes(tree, max_depth)
	local nodes = {}

	local function process(node, depth)
		table.insert(nodes, node)

		if depth < max_depth and node:has_children() then
			for _, node in ipairs(tree:get_nodes(node:get_id())) do
				process(node, depth + 1)
			end
		end
	end

	for _, node in ipairs(tree:get_nodes()) do
		process(node, 1)
	end

	return nodes
end

function M.expand_tree(tree, max_depth)
	local nodes = get_tree_nodes(tree, max_depth)
	for _, node in ipairs(nodes) do
		node:expand()
	end
	-- If you want to expand the root
	-- local root = tree:get_nodes()[1]
	-- root:expand()
end

function M.apply_tree_mappings(popup, tree)
	popup:map("n", "<CR>", function()
		local node = tree:get_node()

		if node:is_expanded() then
			node:collapse()
		else
			node:expand()
		end
		tree:render()
	end)
end

return M
