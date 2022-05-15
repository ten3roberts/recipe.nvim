local filetypes = {
  rust = {
    build = 'cargo build --bins -q',
    check = 'cargo check --bins --examples -q',
    clippy = 'cargo clippy -q',
    clean = 'clean -q',
    run = { cmd = 'cargo run', interactive = true },
    test = { cmd = 'cargo test -q --all-features', interactive = true, keep_open = false },
    doc = 'cargo doc -q --open',
  },
  python = {
    run = { cmd = "python %", interactive = true },
    build = "python -m py_compile %",
    check = "python -m py_compile %",
  },
  glsl = {
    check = 'glslangValidator -V %'
  },
  html = {
    build = 'live-server %',
    check = 'live-server %',
    run = 'live-server %',
  },
  lua = {
    build = 'luac %',
    check = 'luac %',
    clean = 'rm luac.out',
    lint = 'luac %',
    run = 'lua %',
  },
  svelte = {
    run = { cmd = 'npm run dev -- --open', interactive = true },
  },
}

return filetypes
