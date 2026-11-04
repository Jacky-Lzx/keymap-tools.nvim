# keymap-tools.nvim

Neovim keymap hints in the bottom-right corner, with a searchable **choose and
execute** picker powered by [selection-tools.nvim](../selection-tools.nvim).
The hint window works independently of selection-tools and which-key.

## Requirements

- Neovim 0.10+
- `selection-tools.nvim` for the picker (the sibling checkout works directly)

## Setup

Add this local checkout to lazy.nvim. Set `mapleader` before loading the plugin.
Use `lazy = false` so automatic prefix hints are available from startup.

```lua
{
  dir = vim.fn.expand("~/Documents/Github/nvim_plugins/keymap-tools.nvim"),
  name = "keymap-tools.nvim",
  main = "keymap_tools",
  lazy = false,
  dependencies = {
    {
      dir = vim.fn.expand("~/Documents/Github/nvim_plugins/selection-tools.nvim"),
      name = "selection-tools.nvim",
      main = "selection_tools",
      opts = {},
    },
  },
  opts = {
    delay = 200,
    win = { width = 48, height = 16, border = "rounded" },
    groups = {
      ["<leader>s"] = "Search",
      ["<leader>g"] = "Git / LSP",
      ["<leader>t"] = "Toggle",
    },
  },
}
```

With another plugin manager, add both plugins to `runtimepath` and call
`require("keymap_tools").setup()`.

If replacing which-key, disable its lazy.nvim spec and remove its explicit
`<leader>?` mapping. Existing mappings are preserved, so an existing binding
takes precedence over this plugin's default picker key. Other plugins calling
`require("which-key").add()` need their configuration adjusted separately;
keymap-tools does not implement which-key's API. This repository does not modify
your Neovim configuration or sibling plugins.

## Usage

- Press a configured prefix (for example `<leader>`) and pause: a non-focusing
  window lists the next keys in the bottom-right corner.
- Continue typing to enter a group or execute a mapping. `<BS>` goes back one
  level; `<Esc>` / `<C-c>` closes the hint. Unknown combinations fall through to
  Neovim, including native commands such as `gg`.
- Press **`<leader>?`** in Normal or Visual mode to search mappings available in
  the current buffer and mode. Type a key or description, move with `<C-n>` /
  `<C-p>`, and confirm with `<CR>` to execute it in the original window. `<Esc>`
  cancels. A Visual selection is restored before execution or cancellation.
- `:KeymapTools` / `:KeymapTools pick` opens the same picker.
- `:KeymapTools show` opens the interactive hint at the root.
- `:KeymapTools refresh` refreshes prefix triggers after programmatic changes.

Mappings are read from Neovim at invocation time. Buffer-local mappings override
global mappings with the same keys. Descriptions come from `desc`, falling back
to the RHS or `Lua callback`. Internal triggers and `<Plug>` targets are hidden
from normal results. No built-in command catalog is bundled.

The plugin replays the original keys with remapping enabled, so Lua callbacks,
expression mappings, `<Plug>` chains, and buffer scope retain Neovim's behavior.
Automatic hints preserve Normal-mode counts and registers. The picker rejects a
mapping that was removed/replaced, or a source window that changed buffers while
it was open. Mappings that require more input continue reading it normally.

## Configuration and API

```lua
require("keymap_tools").setup({
  enabled = true, -- Automatic hints; the picker remains available when false
  delay = 200,   -- Milliseconds before showing the hint
  modes = { "n", "x" },
  triggers = { "<leader>", "<localleader>", "g", "z", "[", "]", "<C-w>" },
  groups = {}, -- Prefix -> label; <leader>/<localleader> are expanded
  win = { width = 48, height = 16, border = "rounded" },
  picker = { key = "<leader>?" }, -- Set key = false to install no global binding
})

local keymaps = require("keymap_tools")
keymaps.pick() -- Effective global + buffer-local maps for the current mode
keymaps.pick({ global = false }) -- Only buffer-local mappings
keymaps.pick({ ["local"] = false }) -- Only global mappings
keymaps.pick({ picker = { layout = { width = 0.7, height = 0.6 } } })
keymaps.show({ keys = "<leader>s" }) -- Interactive hint for a specific prefix
keymaps.hide()
keymaps.refresh()
local maps = keymaps.get_keymaps({ buf = 0, mode = "n" })
```

`get_keymaps()` also accepts `global`, `["local"]`, and `plugs = true`. Entries
contain `lhs`, raw `keys`, `mode`, `scope`, `desc`, `buf`, and the original `map`
dictionary. Only explicitly registered mappings appear. The interactive UI
supports Normal and Visual modes; the collection API accepts other map modes.

Automatic triggers are installed only when a prefix has descendants and no
existing exact mapping. They refresh on safe idle events, buffer/filetype and
LSP changes. An exact user mapping on a prefix keeps its normal behavior; use
`show()` explicitly if you want to inspect its descendants. Hints are suspended
for macro recording. Running both this plugin and which-key's automatic triggers
on the same prefixes is not supported.

The hint fits the terminal, clips by display cells (including CJK), and shows an
overflow count when necessary. Type another key to narrow the group. Colors use
`KeymapToolsNormal`, `KeymapToolsBorder`, `KeymapToolsKey`, and
`KeymapToolsGroup`, linked to standard highlight groups by default.

## Validation

```sh
sh tests/run.sh
```

Uses headless API checks and real terminal input against the actual sibling
selection-tools checkout. Set `SELECTION_TOOLS_DIR` if it lives elsewhere and
`NVIM_BIN` to test another Neovim binary. Requires Python 3 and StyLua.
