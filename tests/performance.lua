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
