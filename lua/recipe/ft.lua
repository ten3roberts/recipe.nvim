local filetypes = {
	rust = {
		build = { cmd = "cargo build --bins -q" },
		check = { cmd = "cargo check --bins --examples -q" },
		clippy = { cmd = "cargo clippy -q" },
		clean = { cmd = "cargo clean -q" },
		run = { cmd = "cargo run", interactive = true },
		test = { cmd = "cargo test --all-features", interactive = true, keep_open = false },
		doc = { cmd = "cargo doc -q --open" },
	},
	python = {
		run = { cmd = "python %", interactive = true },
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
		run = { cmd = "npm run dev -- --open", interactive = true },
	},
}

return filetypes
