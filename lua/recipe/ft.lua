local filetypes = {
  rust = {
    build = 'cargo build -q',
    check = 'cargo check --examples -q',
    clippy = 'cargo clippy -q',
    clean = 'clean -q',
    run = 'cargo run',
    test = 'cargo test -q --all-features',
    doc = 'cargo doc -q --open',
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
  __index = function()
    return {}
  end
}


return filetypes
