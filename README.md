# Recipe 🍜

Easily define per project or filetype commands to kick off test suits or run
REPLS ...

... and have the results land in the quickfix list.

Recipes are automatically loaded from `recipes.json` from the current working
directory. Recipes for common filetypes are preloaded, like build commands.

Pairs extraordinarily well with [qf.nvim](https://github.com/ten3roberts/qf.nvim)

## Setup
```lua
require "recipe".setup {}
```

## Baking 🍞
Run a recipe by name by simply

```lua
require "recipe".bake(name)
```

If a recipe of the specified name is not loaded it will attempted to fallback to
a filetype default. This allows generic "lint" or "build" commands.

## Recipes

Recipes define a task which is executec async in the shell, similar to "tasks"
in VSCode.

Recipes can be either be defined globally, per filetype, or per project

To define global recipes, look at [Configuration](#Configuration).

Per-project recipes are defined in `recipes.json` in the current working
directory and will be loaded automatically if trusted (More on that later).

Each recipe defined in json can either be a string specifying a shell command, or a table for
additional options.

Any filename modifiers such as `%`, `<cfile>`, and others will be expanded
before the command is executed, which can be used to execute file specific
commands or opening an HTML file in the browser.

All recipes are a lua table consiting of
  - *cmd* - The command to execute
  - *interactive* - Open a terminal for the process and allow user input,
    useful for running your program
  - *on_finish* - Execute a function by ref or name (as specified in
    `config.actions`)

Use `recipe.lib.make_recipe(cmd, [interactive = false])` to easily create a
command using sane defaults.

Recipe invocations are idempotent, so multiple of the same build invocations
won't be run at the same time. If a recipe uses expansion, the expanded command
is used to determine idempotency.

If a recipe is interactive and is run again, the terminal will be focused or
created again. This is very useful for a REPL which can be closed, reopened, or
refocused.

### Example
```json
{
  "build": "cargo build --examples",
  "run": "cargo run --example physics",
  "run_term": {
    "cmd": "cargo run --example cli",
    "interactive": true
  },
  "open": {
    "cmd": "xdg-open %:h",
    "on_finish": "loc"
  }
}

```

## Configuration
```lua
M.config = {
  -- Configure the terminal for interctive commands
  term = {
    height = 0.7,
    width = 0.5,
    type = "float", -- | "split" | "vsplit"
    border = "shadow"
  },
  -- Specify your own actions as a function
  -- These are then used in `recipe.on_finish`
  actions = {
    qf = function(data, cmd) util.parse_efm(data, cmd, "c") end,
    loc = function(data, cmd) util.parse_efm(data, cmd, "l") end,
    notify = util.notify,
  },
  -- Change the file for looking for recipes
  recipes_file = "recipes.json",
  --- Define custom global recipes, either globally or by filetype as key
  --- use lib.make_recipe for conveniance
  custom_recipes = {
    rust = {
      upgrade = make_recipe("cargo upgrade --workspace"),
    },
    global = {
      open = make_recipe("xdg-open %:h"),
      open_f = make_recipe("xdg-open <cfile>")
    }
  }
}
```

## Statusline

To get an indicator or a running job, simply include `recipe.statusline` on your
statusline.

## Security

It is not always a safe to be able to execute arbitrary commands which are
loaded from a file, as is the case for `recipes.json`.

While the user may have created the file themselves, malicious recipes could be
loaded through entering cloned repositories from the internet which have a
`recipes.json` or could be induced through git when carelessly merging or
pulling other peoples code.

To mitigate this issue, the plugin will ask for confirmation before loading
project local recipes for new projects, or if the recipes file has been changed
outside of Vim.

This also means that tying "build" or other common commands to an autocommand or
keymap is safe and won't automatically run malicious code.
