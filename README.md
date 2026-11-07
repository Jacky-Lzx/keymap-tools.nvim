# keymap-tools.nvim

The selection-tools picker composes key, icon, scope and description columns. Icons and separators do not affect matching. Description text inherits shared component defaults; `components = false` retains the legacy formatted row.

Key hints, searchable mappings and live toggle descriptions.

## Features

- Inspect effective buffer and global mappings.
- Describe groups, toggles, registers, marks and operator-pending keys.
- Show an optional screencast of recently typed keys.

## Requirements

Neovim **0.10+**. Hints have no required plugin dependency. The mapping picker requires selection-tools.nvim.

## Installation

With lazy.nvim:

```lua
{
  "Jacky-Lzx/keymap-tools.nvim",
  main = "keymap_tools",
  dependencies = { "Jacky-Lzx/selection-tools.nvim" },
  opts = {},
}
```

Or put this repository and its required dependencies on `runtimepath`, then call:

```lua
require("keymap_tools").setup({})
```

## Usage

```vim
:KeymapTools
:KeymapTools show
```

## Documentation

- [Complete reference](doc/keymap-tools.txt) — `:help keymap-tools`.
- [Workflow and integration guide](doc/guide.md).
- Diagnose availability with `:checkhealth keymap_tools`.

## Development

Run from the repository root:

```sh
python3 tests/run.py unit --filter docs
python3 tests/run.py default
```

See [the test workflow](tests/README.md) for dependencies, optional suites and
retained failure evidence. Local development overrides belong in your package
manager configuration; public installation uses the repository above.
