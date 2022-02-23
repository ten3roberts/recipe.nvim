# Recipe 🍜

Easily define per project or filetype commands to kick off test suits ...

... and have the results land in the quickfix list.

Pairs extraordinarily well with [qf.nvim](https://ten3roberts/qf.nvim)

## Setup
```lua
require "recipe".setup {}
```

## Baking
Run a recipe by name by simply

```lua
require "recipe".bake(name)
```

## Per project configuration
Add a file called `recipes.json` in the working directory and it will be loaded automatically.

Recipes can either be a string specifying a shell command, or a table for
additional options

### Example
```json
{
  "build": "cargo build --examples",
  "run": "cargo run --example physics",
}

```
