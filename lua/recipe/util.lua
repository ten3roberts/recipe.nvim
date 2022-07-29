local M = {}
local fn = vim.fn

function M.get_compiler(cmd)
	local rtp = vim.o.rtp
	for part in cmd:gmatch("%w*") do
		local compiler = fn.findfile("compiler/" .. part .. ".vim", rtp)
		if compiler ~= "" then
			return part
		end
	end
end

function M.vim_qf(data, recipe, ty, ok)
	if ok then
		vim.fn.setqflist({}, "r", {})
		vim.cmd(ty .. "close")
		return
	end
	local cmd = recipe.cmd

	local old_c = vim.b.current_compiler

	local old_efm = vim.opt.efm

	local old_makeprg = vim.o.makeprg

	local compiler = M.get_compiler(recipe.cmd)
	if compiler ~= nil then
		vim.cmd("compiler! " .. compiler)
	end

	if #data == 1 and data[1] == "" then
		return
	end

	if ty == "c" then
		vim.fn.setqflist({}, "r", { title = cmd, lines = data })
		vim.cmd("copen | wincmd p")
	else
		vim.fn.setloclist(".", {}, "r", { title = cmd, lines = data })
		vim.cmd("lopen | wincmd p")
	end

	vim.b.current_compiler = old_c
	vim.opt.efm = old_efm
	vim.o.makeprg = old_makeprg
	if old_c ~= nil then
		vim.cmd("compiler " .. old_c)
	end
end

function M.nvim_qf(data, recipe, ty, ok)
	local cmd = recipe.cmd

	local compiler = M.get_compiler(recipe.cmd)
	if compiler ~= nil then
		vim.cmd("compiler! " .. compiler)
	end

	if #data == 1 and data[1] == "" then
		return
	end

	require("qf").set(ty, {
		title = cmd,
		compiler = compiler,
		lines = data,
		tally = true,
		open = not ok,
	})
end

local has_qf, qf = pcall(require, "qf")

if has_qf then
	M.qf = M.nvim_qf
else
	M.qf = M.vim_qf
end

function M.notify(data, cmd)
	local s = table.concat(data, "\n")
	vim.notify(string.format("%q:\n%s", cmd, s))
end

return M
