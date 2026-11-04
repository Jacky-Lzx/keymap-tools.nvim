vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local tools = require("keymap_tools")
assert(not tools.showkeys.is_enabled())
assert(not tools.showkeys.disable())
assert(not package.loaded["keymap_tools.showkeys"], "inactive state queries must stay lazy")
tools.setup({ defer = true })
assert(not package.loaded["keymap_tools.showkeys"], "default setup must not load the screencast")
local baseline = vim.on_key()
for _ = 1, 3 do
  assert(tools.showkeys.enable())
  assert(tools.showkeys.enable())
  assert(vim.on_key() == baseline + 1, "enable installed duplicate listeners")
  assert(not package.loaded["keymap_tools.hints"], "screencast activated deferred hints")
  assert(not tools.showkeys.disable())
  assert(not tools.showkeys.disable())
  assert(vim.on_key() == baseline, "disable leaked a listener")
end
assert(not pcall(api.nvim_get_autocmds, { group = "KeymapToolsShowkeys" }), "disable retained its augroup")
for _, opts in ipairs({
  { enabled = "yes" },
  { timeout = 0 },
  { timeout = math.huge },
  { maxkeys = 0 },
  { maxkeys = 1.5 },
  { position = "center" },
  { show_count = 1 },
  { excluded_modes = { true } },
  { keyformat = { a = "\n" } },
  { winopts = { focusable = true } },
  { winopts = { zindex = 0 } },
  { winopts = { border = "bad" } },
  { typo = true },
}) do
  assert(not pcall(tools.setup, { showkeys = opts }), "invalid showkeys configuration accepted")
end
assert(not tools.showkeys.is_enabled(), "failed setup changed state")
tools.setup({ defer = true, showkeys = { enabled = true } })
assert(tools.showkeys.is_enabled() and not package.loaded["keymap_tools.hints"])
tools.setup({ defer = true })
assert(not tools.showkeys.is_enabled())
vim.cmd.runtime("plugin/keymap_tools.lua")
vim.cmd("KeymapTools showkeys")
assert(tools.showkeys.is_enabled())
vim.cmd("KeymapTools showkeys disable")
assert(not tools.showkeys.is_enabled())
vim.cmd("KeymapTools showkeys enable")
assert(tools.showkeys.is_enabled())
vim.cmd("KeymapTools showkeys toggle")
assert(not tools.showkeys.is_enabled())
assert(vim.deep_equal(vim.fn.getcompletion("KeymapTools showkeys ", "cmdline"), { "enable", "disable", "toggle" }))
assert(not package.loaded["selection_tools"] and not package.loaded["keymap_tools.picker"])
io.stdout:write("PASS showkeys lazy startup, lifecycle, setup validation, command/API and deferred hint independence\n")
