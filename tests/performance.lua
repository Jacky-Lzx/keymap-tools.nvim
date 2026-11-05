vim.opt.runtimepath:prepend(vim.fn.getcwd())
local tools = require("keymap_tools")
local keys = require("keymap_tools.keys")
tools.setup({
  hints = { enabled = false },
  presets = false,
  providers = {
    registers = false,
    marks = false,
    spelling = false,
  },
})
for i = 1, 200 do
  vim.keymap.set("n", ("q%03d"):format(i), "<Nop>")
end
vim.keymap.set("n", "<F2>", "<Nop>")
vim.keymap.set("n", "中", "<Nop>")
local label, calls = keys.label, 0
keys.label = function(raw)
  calls = calls + 1
  return label(raw)
end
local rows = tools.list({ mode = "n", kinds = { "mapping" } })
keys.label = label
assert(#rows >= 202)
assert(calls <= 4 * #rows + 10, "display names must be converted linearly, not on every sort comparison")
for i = 2, #rows do
  assert(rows[i - 1].keys <= rows[i].keys, "public queries must retain display-key ordering")
end
print("PASS linear display-key conversion and sorted public queries with Unicode/special keys")

-- Repeated automatic refreshes should reuse canonical keycodes and read each
-- native buffer/mode only once, while still observing direct mapping changes.
tools.setup({ presets = true })
tools.refresh()
local replace, read = vim.api.nvim_replace_termcodes, vim.api.nvim_buf_get_keymap
local conversions, reads = 0, 0
vim.api.nvim_replace_termcodes = function(...)
  conversions = conversions + 1
  return replace(...)
end
vim.api.nvim_buf_get_keymap = function(...)
  reads = reads + 1
  return read(...)
end
for _ = 1, 10 do
  tools.refresh()
end
vim.api.nvim_replace_termcodes, vim.api.nvim_buf_get_keymap = replace, read
assert(conversions < 100, "unchanged native keycodes were repeatedly converted")
assert(reads <= 50, "ownership and trigger queries reread the same buffer/mode")
local leader = vim.g.mapleader
local localleader = vim.g.maplocalleader
vim.g.mapleader, vim.g.maplocalleader = ",", "-"
assert(keys.raw("<Leader>x") == ",x" and keys.raw("<LocalLeader>x") == "-x")
vim.g.mapleader, vim.g.maplocalleader = ";", "/"
assert(keys.raw("<Leader>x") == ";x" and keys.raw("<LocalLeader>x") == "/x")
vim.g.mapleader, vim.g.maplocalleader = leader, localleader
local hints = require("keymap_tools.hints")
local found = false
for _, trigger in ipairs(hints.triggers) do
  found = found or trigger.mode == "n" and trigger.raw == "g"
end
assert(found, "builtin g prefix missing before Vimscript override")
vim.cmd("nnoremap g <Nop>")
tools.refresh()
for _, trigger in ipairs(hints.triggers) do
  assert((trigger.mode ~= "n" or trigger.raw ~= "g"), "direct Vimscript mapping was hidden by the cache")
end
print("PASS bounded keycode reuse, shared native snapshots and live leader/Vimscript mapping changes")
