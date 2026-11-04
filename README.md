# keymap-tools.nvim

Neovim keymap hints in the bottom-right corner, with a searchable **choose and
execute** picker powered by [selection-tools.nvim](../selection-tools.nvim).
The hint window works independently of selection-tools and which-key. It includes
operator-pending motions/textobjects, built-in key descriptions, registers,
marks, spelling suggestions, dynamic descriptions and scrollable groups.

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
takes precedence over this plugin's default picker key. Migrate description/group
registrations to `require("keymap_tools").add()` as described below. This is a
focused spec API, not a complete compatibility implementation of which-key.

## Usage

- Press a configured prefix (for example `<leader>`) and pause: a non-focusing
  window lists the next keys in the bottom-right corner.
- Continue typing to enter a group or execute a mapping. `<BS>` goes back one
  level; `<Esc>` / `<C-c>` closes the hint. Unknown combinations fall through to
  Neovim, including native commands such as `gg`.
- Pause after `d`, `c`, `y`, `gU`, or `g@` to see motions and textobjects. Continue
  with `i` / `a` to inspect inner/around objects. Counts, registers, forced motion
  types, custom operator functions, and native redo are retained. Fast input and
  macros stay on Neovim's ordinary input path.
- Press `"` to inspect registers before a Normal/Visual command, or `<C-r>` in
  Insert/command-line mode to insert a register. Clipboard registers are listed
  without reading their contents by default.
- Press `'`, backtick, `g'`, or g-backtick to inspect marks and their positions.
  The original command determines whether the jump is linewise or exact.
- Press `z=` for spelling suggestions, then type the displayed selector. The
  replacement uses Neovim's native numbered spelling command. Numeric prefixes
  such as `1z=` retain native behavior.
- `<C-d>` / `<C-u>` pages through long hint lists. An actual mapping using either
  key in the current group takes precedence over scrolling.
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
from normal results. Hint windows additionally show built-in descriptions and
metadata-only textobjects. Those virtual entries are excluded from the executable
picker and `get_keymaps()`.

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
  modes = { "n", "x", "o" },
  triggers = { "<leader>", "<localleader>", "g", "z", "[", "]", "<C-w>" },
  groups = {}, -- Prefix -> label; <leader>/<localleader> are expanded
  presets = true, -- false, or a table disabling individual catalogs
  providers = {
    registers = true, -- Or { clipboard = true } for clipboard previews
    marks = true,
    spelling = { suggestions = 20 }, -- Up to 62 selectors
  },
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
dictionary. Only actual mappings appear here and in the picker. Interactive hints
support Normal, Visual and operator-pending modes, plus register providers in
Insert/command-line mode. The collection API accepts other map modes.

### Descriptions, groups and custom textobjects

```lua
require("keymap_tools").add({
  { "<leader>s", group = "Search" },
  { "<leader>ss", function() vim.cmd("setlocal spell!") end,
    desc = function() return vim.wo.spell and "Disable spelling" or "Enable spelling" end },
  { mode = { "o", "x" },
    { "iQ", desc = "Inside custom object" }, -- Metadata for an existing reader/map
    { "aQ", desc = "Around custom object" },
  },
  { "<localleader>l", group = "LaTeX", buffer = true },
})
```

`mode` and `buffer` can be inherited by nested lists; `buffer = true` / `0` means
the current buffer. `desc` and `group` accept strings or functions evaluated when
the menu opens. Buffer-specific metadata overrides global metadata and is released
when the buffer is wiped. `hidden = true` hides a row; `cond = false` suppresses
metadata. Both also accept functions.

The optional second positional value defines a real RHS/Lua callback. It accepts
`expr`, `remap`, `silent`, `nowait`, and `replace_keycodes`. A description-only
entry creates no mapping. Use it for textobjects consumed by mini.ai or another
existing key reader; it supplies hints without replacing that reader.

Native preset categories are `motions`, `navigation`, `windows`, `folds`, and
`textobjects`. For example, `presets = { windows = false }` omits window hints.
Actual mappings take precedence over native descriptions. Provider options accept
`false` or `{ enabled = false }` to disable individual providers. Their triggers
respect existing exact user mappings too.

Automatic triggers are installed only when a prefix has descendants and no
existing exact mapping. They refresh on safe idle events, buffer/filetype and
LSP changes. An exact user mapping on a prefix keeps its normal behavior; use
`show()` explicitly if you want to inspect its descendants. Hints are suspended
for macro recording, and automatic operator hints are skipped during macro replay.
Running both this plugin and which-key's automatic triggers
on the same prefixes is not supported.

The hint fits the terminal, clips by display cells (including CJK), and shows an
page range when necessary. Type another key to narrow the group. Colors use
`KeymapToolsNormal`, `KeymapToolsBorder`, `KeymapToolsKey`, and
`KeymapToolsGroup`, linked to standard highlight groups by default.

## Validation

```sh
sh tests/run.sh
```

Uses headless API checks and real terminal input against the actual sibling
selection-tools and installed mini.ai checkouts. Set `SELECTION_TOOLS_DIR` or
`MINI_AI_DIR` if they live elsewhere, and `NVIM_BIN` to test another Neovim binary.
Requires Python 3 and StyLua; spelling checks use the installed English dictionary.
