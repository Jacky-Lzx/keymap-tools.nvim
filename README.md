# keymap-tools.nvim

Bottom-right Neovim keymap hints and an executable mapping picker powered by
selection-tools.nvim. Includes operator-pending motions/textobjects, register and
mark previews, spelling suggestions, dynamic descriptions, and list scrolling.
Hints use two columns by default, filling top to bottom and then left to right.
Narrow windows automatically fall back to one column.
Read-only toggle registrations supply live descriptions and structured state;
feature owners keep their mappings and switching logic.

Requires Neovim 0.10+. selection-tools.nvim is needed only for `pick()`.

## Install

```lua
{
  dir = vim.fn.expand("~/Documents/Github/nvim_plugins/keymap-tools.nvim"),
  name = "keymap-tools.nvim",
  main = "keymap_tools",
  event = "VimEnter",
  opts = { defer = true, hints = { delay = 200 } },
  config = function(_, opts)
    local keymaps = require("keymap_tools")
    keymaps.setup(opts)
    keymaps.register("config", {
      groups = {
        { prefix = "<leader>s", label = "Search" },
        { prefix = "<leader>g", label = "Git / LSP" },
      },
    })
    vim.keymap.set({ "n", "x" }, "<leader>?", keymaps.pick,
      { desc = "Choose and execute buffer keymap" })
  end,
}
```

Set `mapleader` before registering keys. Disable other automatic hint plugins on
the same prefixes. `setup()` installs automatic hint triggers, never a global
picker shortcut; bind user actions explicitly with `vim.keymap.set()`.

Register selection-tools separately if you use the picker; it can use `lazy = true`
and will load on the first `pick()`. It is not a dependency of automatic hints:

```lua
{
  dir = vim.fn.expand("~/Documents/Github/nvim_plugins/selection-tools.nvim"),
  name = "selection-tools.nvim",
  main = "selection_tools",
  lazy = true,
  opts = {},
}
```

`defer = true` delays the hint engine until `VimEnter` when `setup()` is called
earlier, including calls caused by another plugin's metadata registration.
Triggers are ready before the first input. The default is `false` for synchronous
setup. Explicit `show()`, `pick()`, and `refresh()` activate pending setup
synchronously; reconfiguring an active engine is synchronous as well.
`register()` loads only metadata storage and key normalization. `list()` does not
initialize hints or rendering, and the hint window module loads on first display.

## Use

- Pause after `<leader>`, `g`, `z`, `[`, `]`, or `<C-w>` for next-key hints.
- Pause after `d`, `c`, `y`, `gU`, or `g@` for operator motions and textobjects.
  Continue with `i` / `a` for inner/around objects. Counts, registers, forced
  motion types, native redo, and custom operator functions are retained.
- Press `"` for register previews; `<C-r>` works in Insert and command-line modes.
  Clipboard registers are listed without requesting their contents by default.
- Press `'`, backtick, `g'`, or g-backtick for marks. Native commands determine
  whether the jump is linewise or exact.
- Press `z=` for spelling suggestions, then type a displayed selector. Numbered
  commands such as `1z=` retain native behavior.
- `<C-d>` / `<C-u>` pages long hint lists, `<BS>` goes up, and `<Esc>` / `<C-c>`
  cancels. An actual candidate using a scrolling key takes precedence.
- `:KeymapTools` / `:KeymapTools pick` opens the executable mapping picker;
  `show`, `hide`, and `refresh` are also available as command arguments.

Existing exact user mappings are preserved. Unknown combinations replay normally.
Macros and rapid operator input retain Neovim's ordinary input path. Mapping
callbacks, expressions and `<Plug>` chains execute by replaying their original
keys. The picker restores the source window/Visual range and rejects a removed
or replaced mapping before execution.

## Configuration

```lua
require("keymap_tools").setup({
  defer = true, -- Defer startup initialization until VimEnter
  hints = {
    enabled = true, -- Automatic hints only; explicit show()/pick() remain usable
    delay = 200,
    operators = true, -- Start hints on entering operator-pending mode
    triggers = {
      { prefix = "<leader>", modes = { "n", "x", "o" } },
      { prefix = "<localleader>", modes = { "n", "x", "o" } },
      { prefix = "g", modes = { "n", "x", "o" } },
      { prefix = "z", modes = { "n", "x", "o" } },
      { prefix = "[", modes = { "n", "x", "o" } },
      { prefix = "]", modes = { "n", "x", "o" } },
      { prefix = "<C-w>", modes = { "n", "x", "o" } },
    },
  },
  window = { width = 80, height = 16, columns = 2, border = "rounded" },
  picker = {}, -- selection-tools options, e.g. layout = { width = 0.7 }
  presets = true,
  providers = {
    registers = true, -- Or { clipboard = true } to read clipboard previews
    marks = true,
    spelling = { suggestions = 20 }, -- 1..62 selector keys
  },
})
```

Trigger lists replace defaults as a whole, including an empty list. Provider
triggers are enabled by their own options, subject to `hints.enabled`; they do
not inherit modes from unrelated prefix rules. Set a provider to `false` or
`{ enabled = false }` to disable it. Trigger modes are `n/x/o/i/c`.

Set `presets = false`, or disable individual `motions`, `navigation`, `windows`,
`folds`, and `textobjects` catalogs in a presets table. These are descriptions;
actual Neovim mappings always take precedence.

`window.width` is the total hint width. `columns = 2` is the default; set it to
`1` for a single column. Paging covers both columns and displays the actual range
of candidates, including a partially filled final page. Space is displayed as `␣`.
Bordered hints show scrolling keys at the bottom left and the candidate range at
the bottom right, leaving all content rows available. Very narrow borders keep
the range; borderless hints use a content footer.

## Register metadata

Real mappings belong to `vim.keymap.set()`. Registration only supplies metadata:

```lua
local registration = require("keymap_tools").register("mini.ai", {
  modes = { "o", "x" }, -- Default: { "n" }
  priority = 0,
  groups = {
    { prefix = "i", label = "Inside" },
    { prefix = "a", label = "Around" },
  },
  hints = {
    { keys = "if", desc = "Inside function" },
    { keys = "af", desc = "Around function" },
  },
})

registration:replace({ modes = { "o", "x" }, hints = {
  { keys = "if", desc = "Inside function" },
} }) -- Entire replacement: the old groups/other hints are removed
registration:dispose() -- Idempotent; removes only this registration
```

`register(source, spec)` requires a nonempty source ID. A source may have one
registration per buffer scope, plus one global registration. `buf = 0` captures
the current buffer; omit `buf` for global metadata. Buffer registrations are
released on buffer wipe, even if `setup()` has not been called.

Registration and `list()` do not initialize hint windows or create key mappings.
A scoped registration installs only its buffer cleanup handler. Setup/registration
order is flexible. Pending trigger refreshes after metadata changes are coalesced.

For conflicting metadata: buffer scope wins, then higher `priority`, then the
most recently registered/replaced source. Other sources remain stored, so disposing
an override restores the previous source. Re-registering the same source/scope
invalidates its previous handle; that old handle cannot alter the replacement.
`replace()` preserves source/buffer identity and validates before changing data.

Each group/hint may override `modes` and provide `when` or `hidden`. A hidden
group hides its descendants in presentation, while native mappings remain intact.
`when` also works on the whole registration. `label`, `desc`, `when`, and `hidden`
may be functions receiving the source context:

```lua
require("keymap_tools").register("wrap-description", {
  hints = {
    { keys = "<leader>tw", desc = function(ctx)
      local enabled = vim.api.nvim_get_option_value("wrap", { win = ctx.win })
      return enabled and "Disable wrap" or "Enable wrap"
    end },
  },
})
```

Context fields: `buf`, `win`, `mode`, canonical `prefix`, `operator`, `count`, and
`register`. Callbacks receive isolated copies. A hidden/unshown buffer has no
`win`; integrations should handle that case. Use the supplied context rather
than assuming the currently focused window is the requested source. Dynamic
values are evaluated when data is queried/opened, not continuously while idle.
Callback failures are available in query diagnostics without crashing the menu.

A hint matching a real mapping decorates that mapping. A metadata-only hint
creates no executable action; it can describe input read by mini.ai or another
existing key reader. Empty groups are omitted from the resolved display model.

## Register toggles

Use `toggles` to describe an existing feature switch. Each entry requires `keys`,
`name` (a string or context callback), and `get(ctx)` returning `true`, `false`,
or `nil` when the state is unknown. For example, alongside a window-wrap mapping:

```lua
vim.keymap.set("n", "<leader>tw", function()
  vim.wo.wrap = not vim.wo.wrap
end, { desc = "Toggle wrap" }) -- Owned by the window feature

require("keymap_tools").register("window.wrap", {
  toggles = {
    {
      keys = "<leader>tw",
      name = "Wrap",
      get = function(ctx)
        if ctx.win then
          return vim.api.nvim_get_option_value("wrap", { win = ctx.win })
        end
      end,
    },
  },
})
```

Hints, the picker and `list()` share the description: `Enable Wrap` for `false`,
`Disable Wrap` for `true`, and `Toggle Wrap` for unknown state. Rows also expose
`toggle = { name = "Wrap", state = false }`; unknown state has no `state` value.
A toggle without a real mapping remains a non-executable `hint`. With a mapping,
it remains a `mapping` and the picker replays the owner's original keys. Even if
state changes while the picker is open, execution uses the owner's current logic.

`get` is read-only: registration never calls it, installs no mapping, and accepts
no setter. State is read afresh when querying/opening, without polling, caching,
or initializing a feature. Trigger discovery does not call `get`. A getter error
or non-boolean/non-nil result produces unknown state and an `info.errors` entry with
`field = "get"`. Return `nil` for an expected unavailable state to avoid an error.
An open display is a snapshot; reopen it to read changed state.

Toggles use the same `modes`, `when`, `hidden`, buffer scope, priority and
registration handles as hints. They compete with hints for the same metadata
slot, so an ordinary hint override removes the toggle state too. Within a single
registration, toggles take precedence over hints at the same key/mode.

For configuration migrations, register next to each feature's existing mapping:

```lua
require("keymap_tools").register("formatting", {
  toggles = {
    { keys = "<leader>tf", name = "Auto format", get = function()
      return vim.g.enable_autoformat -- Same session flag the formatter reads
    end },
  },
})

require("keymap_tools").register("diagnostics", {
  toggles = {
    { keys = "<leader>td", name = "Diagnostics", get = function()
      return vim.diagnostic.is_enabled()
    end },
    { keys = "<leader>th", name = "Inlay Hints", get = function()
      return vim.lsp.inlay_hint.is_enabled() -- Session-wide state
    end },
  },
})
```

Window options such as spell, relative numbers and conceal can read their values
through `ctx.win`; buffer features should use `ctx.buf`. Compare non-boolean
options explicitly, e.g. `conceallevel > 0` or `vim.o.background == "dark"`.
For lazy features, register after the owner loads or inspect `package.loaded`
and return `nil` until available. Do not require a lazy feature just to read its
status. Animation, scrolling, Markdown rendering, Git and UI switches should
read their owner's public state rather than mirror it in keymap-tools.

Existing Snacks switches can keep owning their mappings while an integration
registers `name = toggle.opts.name` and a context-aware getter calling
`toggle:get()`. For getters that use implicit current-window state, guard
`ctx.win` and call them with `vim.api.nvim_win_call(ctx.win, ...)`. There is no
automatic Snacks hook, configuration scan or built-in feature/key assignment.

## Query and display

```lua
local keymaps = require("keymap_tools")
local items, info = keymaps.list({
  buf = 0,
  mode = "n",
  prefix = "<leader>g",
  scope = "effective", -- "global" or "buffer" also available
  kinds = { "mapping", "hint", "group", "provider", "choice" },
})

keymaps.show({ prefix = "<leader>g" })
keymaps.pick({ scope = "buffer", layout = { width = 0.7 } })
keymaps.hide()
keymaps.refresh()
```

`list()` is read-only and returns detached rows with canonical `keys`, `kind`,
`source`, `metadata_source` (when decorating an actual map), `scope`, `buf`,
`mode`, `desc`, `hidden`, and `executable`. Only real mappings have
`executable = true`. Toggle registrations additionally supply `toggle` with
`name` and boolean-or-unknown `state`. Internal keycodes and map dictionaries are
not public data.
Use `kinds = { "mapping" }` for a mapping-only query; `<Plug>` targets are hidden
unless `plugs = true`. `include_hidden = true` includes hidden rows.

`scope = "effective"` resolves buffer overrides. `global` reads only the global
mapping/metadata scopes, including mappings shadowed in this buffer. `buffer`
reads only the buffer scope. Actual mappings identify their source as `neovim`;
registered hints/groups identify their source by the caller's ID. Native data
uses `builtin:` source IDs. `info.context` is the resolved source context, and
`info.errors` contains callback errors with source/field/message.

Pass `win` to inspect a particular window, or `buf` to inspect another buffer.
At an exact provider prefix (`"`, `z=`, etc.), queries return dynamic `choice`
rows using that source window, without showing a UI. Without a display window,
provider choices are omitted. Interactive show()/pick() use the active source
window; queries can inspect other windows without changing focus.

The picker uses the same query model but includes only actual, effective
mappings. Its optional `global`/`buffer` scope filters that effective set; it
never offers a shadowed global mapping that would replay a different local map.
Visual and Normal pickers retain their original execution semantics.

## API change

`add()`, `get_keymaps()`, positional mapping specs, and setup-owned picker
shortcuts have been removed. Use `register()` with named groups/hints, `list()`,
and explicit `vim.keymap.set()` bindings. Setup uses `hints` and `window`; group
labels belong to registrations. No compatibility aliases are provided.

## Validation

Run `sh tests/run.sh`. Checks include registration conflicts/cleanup, cross-window
contexts, read-only toggles and unknown states, query diagnostics, actual
selection-tools/mini.ai checkouts, and real terminal input for operator, provider
and picker workflows. Set
`SELECTION_TOOLS_DIR`, `MINI_AI_DIR` or `NVIM_BIN` to override local test paths.
Python 3, StyLua and the English spelling dictionary are required for the suite.
