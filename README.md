# Recipe 🍜

Easily define per project or filetype commands to kick off test suits or run
REPLS ...

... and have the results land in the quickfix list.

Recipes are fetched from multiple sources, such as the `recipes.json` file, the
current filetype, lsp, Makefiles, and more.

Pairs extraordinarily well with [qf.nvim](https://github.com/ten3roberts/qf.nvim)

## Setup
```lua
require "recipe".setup {}
```

## Baking 🍞
Run a recipe by name

```lua
require "recipe".bake("build")
```

or
```viml
:Bake my-name
```

If a recipe of the specified name is not loaded it will attempted to fallback to
a filetype default. This allows generic "lint" or "build" commands.

## Recipes

Recipes define a task which is executed async in the shell, similar to "tasks"
in VSCode.

Recipes can be either be defined globally, per filetype, or per project

To define global recipes, look at [Configuration](#Configuration).

Per-project recipes are defined in `recipes.json` in the current working
directory and will be loaded automatically if trusted (More on that later).

Any filename modifiers such as `%`, `<cfile>`, and others will be expanded
before the command is executed, which can be used to execute file specific
commands or opening an HTML file in the browser.

Recipe invocations are idempotent, so multiple of the same build invocations
won't be run at the same time.

A recipe contains a `cmd` and a `key` which is used to identify it across
several executions.

### Components

Components define additional behavior for a recipe, such as parsing the command
output into the quickfix list, or launching a debug session.

```lua
local recipe = {
    cmd = "echo Hello, ${SCOPE}",
    key = "my-command",
    env = {
	SCOPE = "World"
    },
    components = {
	qf = {},
      }
  }

require "recipe".execute(recipe):focus()
```


### Example
```json
{
  "build": "cargo build --examples",
  "run": "cargo run --example physics",
  "run_term": {
    "cmd": "cargo run --example cli",
    "kind": "term"
  },
  "open": {
    "cmd": "xdg-open %:h",
  }
}

```

A recipe can have one or more dependencies, which will be run prior to
execution.

This can be specfied as a list of strings, which refer to recipe names, or
tables which themselves are recipes, or a mix of both. This is useful for
"compile before debug" scenarios.

## Configuration
```lua
---@class Task
---@field stop fun()
---@field focus fun()
---@field restart fun(on_start: fun(task: Task|nil), on_exit: fun(code: number): Task|nil): Task
---@field callbacks fun(code: number)[] added by lib
---@field recipe Recipe

---@class Config
---@field custom_recipes table<string, Recipe>
---@field term TermConfig customize terminal
---@field default_recipe Recipe
---@field adapter table
---@field dotenv string Load path as dotenv before spawn
M.opts = {
	---@class TermConfig
	term = {
		height = 0.7,
		width = 0.5,
		type = "smart",
		border = "single",
		jump_to_end = true,
		auto_close = false,
	},
	recipes_file = "recipes.json",
	--- Define custom global recipes, either globally or by filetype as key
	custom_recipes = require("recipe.ft"),
	hooks = {
		pre = {
			function(_)
				vim.cmd(":wa")
			end,
		},
	},

	---@class Recipe
	---@field cmd string
	---@field cwd string
	---@field kind string one of build,term,dap or a custom adapter
	---@field plain boolean
	---@field env table|nil
	---@field opts table Extra options for the current backend
	---@field depends_on (string|Recipe)[]
	default_recipe = {
		cmd = "",
		kind = "build",
		opts = {},
		restart = false,
		plain = false,
		depends_on = {},
		env = { __type = "table" },
	},

	debug_adapters = {
		rust = require("recipe.debug_adapters").codelldb,
		c = require("recipe.debug_adapters").codelldb,
		cpp = require("recipe.debug_adapters").codelldb,
	},
	dotenv = ".env",
}
```

## Debugging

Recipe supports launching a DAP debugging session on a successful build.

```json
{
  "build": {
    "cmd": "cargo build"
  },
  "debug-rust": {
    "cmd": "./target/debug/myprogram",
    "kind": "dap",
    "depends_on": [ "build" ]
  }
}
```

### Adapter

If no adapter is specified it will be guessed based on the compiler.

For rust (cargo) and C/C++ (make, cmake) the `CodeLLDB` adapter is used.
In lieu of a debug adapter installer `CodeLLDB` will be installed automatically.

If you wish to include other default adapters I will more than kindly accept a
PR.

Otherwise a custom adapter or other options can be specified in the same way as
`dap.run`

## Repl and Interactive Programs

By setting `"kind": "term"` the recipe will be launched in a terminal
according to `config.term`.

If a running job is executed again, the terminal window will be focused or
opened again. By setting a keybinding to either `:Bake my-recipe` or `:RecipePick` (for a frecency sorted popup) you can quickly define your own project defined repls.
Sometimes it is useful to quickly restart a program each time instead of focusing, for example when developing a server, where you need to rebuild and restart.

This is accomplished by setting `"restart": true` and works for both interactive
and non-interactive programs.

## Ad-hoc recipes

While predeclared project wise recipes are useful, it is sometimes necessary to
execute an arbitrary command.

For this, the vim `Ex` and `ExI` commands are provided for background and
interactive jobs.

A more complicated recipe can also be executed directly by `recipe.execute`.

```lua
require "recipe".execute { cmd = "cargo add tokio -F all", kind = "term" }
```

This is useful for plugins executing commands on behalf of `recipe`.

Use a `bang` `ExI!` or `{ opts = { auto_close = false } }` to keep the terminal open after
a successful command. Can also be overridden in [#Setup]

## Persistent terminals

Due to the refocusing of running jobs, persisent terminals are easy.

`ExI $SHELL`

or

`ExI cargo test` for a pesistent rust testing terminal.

Or why not

```lua
require "recipe".execute { cmd = "cargo run", kind = "term", restart = true }
```

If these terminals are to be run from the pick menu, you can add them to the
`custom_recipes.global` table in [#Setup]

## Statusline

To get an indicator of running jobs, simply include `recipe.statusline` on your
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
