# keymap-tools.nvim

Bottom-right Neovim keymap hints and an executable mapping picker powered by
selection-tools.nvim. Includes operator-pending motions/textobjects, register and
mark previews, spelling suggestions, dynamic descriptions, and list scrolling.
Hints use two columns by default, filling top to bottom and then left to right.
Narrow windows automatically fall back to one column.
Hints and the picker display readable key labels, separators and colored semantic
icons for every entry, with a `+` marker for groups (inspired by which-key.nvim).
Read-only toggle registrations supply live descriptions and structured state.
Explicit toggle actions can also share state inversion, error reporting and
notifications; feature owners supply state access and install their mappings.
An optional built-in key screencast displays recently typed keys for recordings
and demonstrations, without requiring showkeys.

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
    vim.keymap.set({ "n", "x", "i" }, "<C-/>", keymaps.pick,
      { desc = "Choose and execute buffer keymap" })
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
- `hints.delay` applies until the first hint window appears. Once visible,
  entering a subgroup or going back updates it immediately.
- `:KeymapTools` / `:KeymapTools pick` opens the executable mapping picker;
  `show`, `hide`, and `refresh` are also available as command arguments.
- `:KeymapTools showkeys` toggles the recent-key screencast (off by default).

Existing exact user mappings are preserved. Unknown combinations replay normally.
Macros and rapid operator input retain Neovim's ordinary input path. Mapping
callbacks, expressions and `<Plug>` chains execute by replaying their original
keys. The picker supports Normal, Visual and Insert modes, restores the source
window/Visual range or insertion position, and rejects a removed or replaced
mapping before execution. Cancelling an Insert picker resumes typing at the
original position. Completion popups and other transient Insert state are not
restored.

## Lifecycle

`setup(nil)` and `setup({})` start from fresh defaults. Options are copied before
use; dictionaries merge recursively and lists replace defaults, including empty
lists. Validation completes before any working configuration, listener or view
is replaced. Repeated setup does not accumulate triggers, timers or observers.

```lua
local tools = require("keymap_tools")
tools.disable() -- Release runtime resources; retain options and live screencast enablement.
tools.enable()  -- Restore that configuration, or defaults before the first setup.
print(tools.is_enabled()) -- Includes a deferred setup waiting for VimEnter.
tools.dispose() -- Release resources and forget configuration; safe when cold/repeated.
```

Both disable and dispose close owned hints/pickers/screencasts, detach automatic
prefix mappings and listeners, cancel pending startup/refresh/replay work, and
unsubscribe from themes. A pending Visual/operator hint is cancelled without
editing source text. User replacements and adopted windows/buffers are preserved.
External `register()`/`register_toggle()` handles and user mappings remain owned
by their callers; release those handles explicitly when their feature unloads.
The static `:KeymapTools` command remains available. Explicit `show()`, `pick()`
or `refresh()` enables the plugin again; `list()` and metadata registration never
activate it. After disposal, explicit use starts from defaults.

## Configuration

```lua
require("keymap_tools").setup({
  defer = true, -- Defer startup initialization until VimEnter
  hints = {
    enabled = true, -- Automatic hints only; explicit show()/pick() remain usable
    delay = 200, -- Initial display only, in milliseconds
    operators = true, -- Start hints on entering operator-pending mode
    filter = function(ctx) -- Automatic hints only; default excludes special buffers
      return ctx.buftype == ""
    end,
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
  icons = { enabled = true, rules = {} },
  picker = {}, -- selection-tools options, e.g. layout = { width = 0.7 }
  showkeys = { enabled = false }, -- Optional recent-key screencast; see below
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

`hints.filter(ctx)` decides which automatic triggers may attach, including provider
and operator-pending hints. It receives `buf`, `win`, `mode`, `prefix` (expanded
key notation such as `<Space>`), `buftype`, and `filetype`. Operator entry uses an
empty prefix. Return `true` to allow a trigger; errors and other return values
skip it. The filter is checked again when a trigger fires, and never changes
explicit `show()`, `pick()` or `list()` calls. Exact native mappings retain
precedence, including `<Nop>` bindings. For example, to opt a dashboard into
Normal-mode leader hints while retaining ordinary-buffer behavior:

```lua
hints = {
  filter = function(ctx)
    return ctx.buftype == ""
      or (ctx.buftype == "nofile" and ctx.filetype == "my_dashboard"
        and ctx.mode == "n" and vim.keycode(ctx.prefix) == vim.g.mapleader)
  end,
}
```

Set `presets = false`, or disable individual `motions`, `navigation`, `windows`,
`folds`, and `textobjects` catalogs in a presets table. These are descriptions;
actual Neovim mappings always take precedence.

`window.width` is the total hint width. `columns = 2` is the default; set it to
`1` for a single column. Paging covers both columns and displays the actual range
of candidates, including a partially filled final page. Space is displayed as `␣`.
Special keys use compact labels such as `↵`, `⇥`, `←` and `Ctrl+w`; query results
and mapping execution retain canonical key notation. Long descriptions end in `…`.
Bordered hints show scrolling keys at the bottom left and the candidate range at
the bottom right, leaving all content rows available. Very narrow borders keep
the range; borderless hints use a content footer.

### Entry icons

Icons use built-in rules matching English or Chinese descriptions (search, Git,
files, LSP, windows, etc.), toggle state, and a fallback for unmatched entries.
No icon plugin is required; the default glyphs need a Nerd Font. Set
`icons = { enabled = false }` to remove the icon column. To use custom glyphs,
add rules in order; patterns match the lowercased description:

```lua
require("keymap_tools").setup({
  icons = { rules = {
    { pattern = "search", icon = "", hl = "DiagnosticInfo" },
    { pattern = "build", icon = "⚒", hl = "Constant" },
  } },
})

require("keymap_tools").register("project", {
  groups = { { prefix = "<leader>p", label = "Project", icon = "󰉋" } },
  hints = { { keys = "<leader>pb", desc = "Build", icon = {
    icon = "⚒", ascii = "B", hl = "DiagnosticWarn",
  } } },
})
```

Groups, hints and toggles accept a static `icon` string, `{ icon = "…", hl = "…", ascii = "B" }`,
or `false` to suppress that entry's icon. Explicit icons take precedence over
custom rules, then toggle state, built-in rules and the fallback. Registration
icons are also returned by `list()` as detached metadata; inferred icons are
resolved only for presentation. An icon on a group decorates that group row.

Highlights link to the active theme by default: `KeymapToolsKey`,
`KeymapToolsSeparator`, `KeymapToolsGroup`, `KeymapToolsMuted`, `KeymapToolsIcon`,
and `KeymapToolsIconBlue/Cyan/Green/Orange/Purple/Red/Yellow`. Setup and colorscheme
handlers apply defaults without overwriting existing definitions.

When theme-tools is loaded, automatic icons use `theme_tools.icons.get("ui", name)`
and its returned highlight. Shared overrides and provider changes apply to open
hints and pickers: `none` hides all entry icons; `ascii` uses shared text labels,
including an explicit icon's optional `ascii` label. Custom icons without an
ASCII label use the shared `keymap` fallback. The palette subscription supplies
hint surfaces, key/group colors and separators. Private defaults refresh on theme
changes while public `KeymapTools*` overrides remain untouched. Picker refreshes
preserve the query, selected mapping and input focus. This integration never
loads theme-tools just to register metadata, query keys or render standalone hints.

## Recent-key screencast

The built-in screencast covers the functionality of
[nvzone/showkeys](https://github.com/nvzone/showkeys): recent-key history, automatic
timeout, repeated-key counts, mode exclusions, six screen positions, custom key
labels, and active/inactive highlighting. It has no external dependency and
does not create a shortcut. Enable it on demand:

```vim
:KeymapTools showkeys
:KeymapTools showkeys enable
:KeymapTools showkeys disable
```

Lua actions are separate from the interactive hint `show()` / `hide()` API:

```lua
local tools = require("keymap_tools")
vim.keymap.set("n", "<leader>uk", tools.showkeys.toggle,
  { desc = "Toggle key screencast" })
tools.showkeys.enable()
tools.showkeys.disable()
print(tools.showkeys.is_enabled()) -- Listener state, including while hidden
```

To configure it, include `showkeys` in the plugin's existing `setup()` call:

```lua
require("keymap_tools").setup({
  showkeys = {
    enabled = false, -- true starts listening during setup, even with defer=true
    timeout = 3, -- Inactivity timeout in seconds, not milliseconds
    maxkeys = 5, -- Maximum number of recent entries
    show_count = false, -- Consecutive identical keys become e.g. "3 j"
    excluded_modes = {}, -- e.g. { "i", "c", "t" }
    position = "bottom-right",
    keyformat = { ["<Space>"] = "␣", ["<C>"] = "Ctrl", ["<M>"] = "Alt" },
    winopts = { border = "single", zindex = 60 },
    winhl = "Normal:NormalFloat,FloatBorder:FloatBorder",
  },
})
```

Positions are `top-left`, `top-center`, `top-right`, `bottom-left`,
`bottom-center`, and `bottom-right`. The float preserves editor focus and moves
above an overlapping hint window. Narrow screens retain the newest entries.
The window hides after inactivity; listening continues until disabled. Tab
changes clear history. Re-running `setup()` resets history and applies
`showkeys.enabled` afresh. Disabled setup and state queries do not load the module;
enabling it does not activate deferred hints or load the picker.

Labels use `keytrans()` notation, such as `<CR>` and `<F2>`. `keyformat` merges
with the built-in Unicode labels; an empty label hides that key. Modifier labels
use `<C>`, `<M>`, `<S>`, and `<D>`. Complete chord labels take precedence over
modifier formatting. Mode exclusions replace the whole list, matching either
the exact Neovim mode or a one-letter prefix (e.g. `i` also excludes `ic`).
Mouse/scroll/drag/release events and mapping-generated keys are ignored. Hints'
own typed-key replay is excluded so it does not duplicate the displayed history.

Highlights are `KeymapToolsShowkeysActive` (default `PmenuSel`) and
`KeymapToolsShowkeysInactive` (default `Visual`); custom definitions survive setup
and are restored as defaults after a colorscheme change.

For migration, move the previous showkeys options into `setup().showkeys` and
replace `:ShowkeysToggle` with `:KeymapTools showkeys`, then remove the old plugin
spec. The integrated `winopts` accepts `border` and `zindex`; dimensions,
position, and focus are managed automatically. Defaults use five history entries
and standard Unicode symbols that do not require a Nerd Font.

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

## Register toggle actions

`register_toggle(source, spec)` registers metadata and returns a callback plus
the metadata registration handle. Bind the returned callback explicitly:

```lua
local callback, registration = require("keymap_tools").register_toggle("window.wrap", {
  keys = "<leader>tw",
  name = "Wrap",
  get = function(ctx)
    if ctx.win then
      return vim.api.nvim_get_option_value("wrap", { win = ctx.win })
    end
  end,
  set = function(enabled, ctx)
    vim.api.nvim_set_option_value("wrap", enabled, { win = ctx.win })
  end,
})
vim.keymap.set("n", "<leader>tw", callback, { desc = "Toggle wrap" })
```

`name` must be a nonempty string. `get(ctx)` returns a boolean or `nil` for an
unavailable state; `set(enabled, ctx)` applies the requested state. The callback
reads current state on invocation, calls `set`, then reads back the actual state.
It returns that final state and sends `Name: Enabled/Disabled` through
`vim.notify`. Set `notify = false` to suppress successful state messages. Getter
or setter errors, invalid state and unavailable initial state produce one error
notification and return `nil`; an unavailable initial state never calls `set`.
If state becomes unknown after switching, the callback returns `nil` silently.

`keys`, `buf`, `modes`, `priority`, `when`, `hidden` and `icon` follow metadata
registration rules. Match the actual mapping's buffer and modes. A scoped action
captures `buf = 0` at registration. Callbacks receive detached source contexts.
Registration and queries never execute setters, show notifications, install
mappings, initialize hints or load feature owners. Lazy owners can supply a
known cold state and load themselves inside `set`.

The second return value manages metadata only; replacing or disposing it does
not change the callback or remove its mapping. Re-register to change an action's
getter/setter, and manage the mapping alongside its feature. The existing
`register(..., { toggles = ... })` remains read-only and rejects setters.

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
`mode`, `desc`, `hidden`, and `executable`, plus `icon` when explicitly registered.
Only real mappings have
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
Normal, Visual and Insert pickers execute in their original mode.
The default `scope = "effective"` shows both scopes, with buffer-local mappings
before globals, including filtered search results. `Alt+b` independently shows or
hides buffer mappings; `Alt+g` does the same for globals. The title displays both
states, and toggling preserves the query and any still-visible selection. Both
may be hidden without closing the window. These settings reset on the next open.
Set `picker.scope = "buffer"` or `"global"` for another initial view. Customize
`picker.keys.toggle_buffer` / `picker.keys.toggle_global` (lists of keys), or pass
`scope` / `keys` directly to `pick()`.

## API change

`add()`, `get_keymaps()`, positional mapping specs, and setup-owned picker
shortcuts have been removed. Use `register()` with named groups/hints, `list()`,
and explicit `vim.keymap.set()` bindings. Setup uses `hints` and `window`; group
labels belong to registrations. No compatibility aliases are provided.

## Validation

Run `sh tests/run.sh`. Checks include registration conflicts/cleanup, cross-window
contexts, read-only toggles and unknown states, query diagnostics, actual
selection-tools/motion-tools checkouts, and real terminal input for operator, provider
and picker workflows, plus screencast rendering, input bursts, hint replay,
timeouts, exclusions and lifecycle cleanup. Set
`SELECTION_TOOLS_DIR`, `MOTION_TOOLS_DIR` or `NVIM_BIN` to override local test paths.
Python 3, StyLua and the English spelling dictionary are required for the suite.
When the sibling theme-tools checkout exists, the suite also tests real terminal
theme/icon switching; set `THEME_TOOLS_DIR` to override its location.

## Command ownership

Commands belong to the plugin; choose global entry keys and short aliases in
your configuration. Registration reports same-name conflicts without replacing
user commands. Reconfiguration refreshes only commands still owned by this
plugin, and cleanup preserves subsequent user replacements.

`:checkhealth keymap_tools` checks picker and optional theme providers without
loading them. Core hints do not require selection-tools; the execution picker does.
