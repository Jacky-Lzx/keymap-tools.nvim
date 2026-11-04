vim.opt.runtimepath:prepend(vim.fn.getcwd())
local providers = require("keymap_tools.providers")
local state = require("keymap_tools.context").resolve({ mode = "n", count = 0 })
local original, clipboard_reads = vim.fn.getreg, 0
vim.fn.getreg = function(key, ...)
  if key == "+" or key == "*" then
    clipboard_reads = clipboard_reads + 1
    return "private clipboard"
  end
  return original(key, ...)
end
vim.fn.setreg("a", "中文\nsecond line")
local list = providers.expand('"', state, {})
assert(#list > 0 and clipboard_reads == 0, "default previews must not request the system clipboard")
local found = false
for _, item in ipairs(list) do
  if item.keys == '"a' then
    found = item.desc:find("中文", 1, true) ~= nil
  end
end
assert(found)
providers.expand('"', state, { registers = { clipboard = true } })
assert(clipboard_reads == 2)
vim.fn.getreg = original
assert(providers.expand('"', state, { registers = false }) == nil)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "line", "mark target" })
vim.api.nvim_buf_set_mark(0, "a", 2, 2, {})
list = providers.expand("`", state, {})
found = false
for _, item in ipairs(list) do
  if item.keys == "`a" then
    found = item.desc:find("mark target", 1, true) ~= nil
  end
end
assert(found)
state.count = 1
assert(#providers.expand("z=", state, {}) == 0, "numbered native spelling must bypass suggestion UI")
local tools = require("keymap_tools")
local callback = function() end
vim.keymap.set("i", "<C-r>", callback, { buffer = true })
vim.keymap.set("n", "'", callback, { buffer = true })
tools.setup()
assert(vim.fn.maparg("<C-r>", "i", false, true).callback == callback)
assert(vim.fn.maparg("'", "n", false, true).callback == callback)
tools.setup({ hints = { enabled = false } })
assert(vim.fn.maparg("<C-r>", "c") == "", "disabling must remove provider triggers too")
print("PASS register contents, clipboard opt-in, mark positions, numbered spelling and existing mapping ownership")
