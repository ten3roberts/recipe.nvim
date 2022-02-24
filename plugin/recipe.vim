command! -nargs=* RecipeAdd lua require'recipe'.insert(<q-args>)
command! RecipeClear lua require'recipe'.clear()
command! -nargs=* Bake lua require'recipe'.bake(<q-args>)
command! RecipeLoadConfig lua require'recipe'.load_config()
