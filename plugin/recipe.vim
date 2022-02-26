command! -nargs=* RecipeAdd lua require'recipe'.insert(<q-args>)
command! RecipeClear lua require'recipe'.clear()
command! -nargs=* -complete=customlist,RecipeComplete Bake lua require'recipe'.bake(<q-args>)
command! -nargs=* -complete=shellcmd Execute lua require'recipe'.execute(<q-args>)
command! RecipeLoadConfig lua require'recipe'.load_config()
command! RecipePick lua require'recipe'.pick()
