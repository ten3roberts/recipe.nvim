local make_recipe = require "recipe.lib".make_recipe

local filetypes = {
  rust = {
    build = make_recipe 'cargo build -q',
    check = make_recipe 'cargo check --examples -q',
    clippy = make_recipe 'cargo clippy -q',
    clean = make_recipe 'clean -q',
    run = make_recipe 'cargo run',
    test = make_recipe 'cargo test -q --all-features',
    doc = make_recipe 'cargo doc -q --open',
  },
  glsl = {
    check = make_recipe 'glslangValidator -V %'
  },
  html = {
    build = make_recipe 'live-server %',
    check = make_recipe 'live-server %',
    run = make_recipe 'live-server %',
  },
  lua = {
    build = make_recipe 'luac %',
    check = make_recipe 'luac %',
    clean = make_recipe 'rm luac.out',
    lint = make_recipe 'luac %',
    run = make_recipe 'lua %',
  },
  svelte = {
    run = make_recipe ('npm run dev', true),
  },
  __index = function()
    return {}
  end
}

setmetatable(filetypes, filetypes)

return filetypes
