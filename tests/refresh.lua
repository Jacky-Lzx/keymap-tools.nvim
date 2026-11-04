vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = " "
local api, tools = vim.api, require("keymap_tools")
local hints = require("keymap_tools.hints")
local function callback(lhs)
  return vim.fn.maparg(lhs, "n", false, true).callback
end
vim.keymap.set("n", " aa", "<Nop>")
vim.keymap.set("n", "gq", "<Nop>")
tools.setup({
  presets = false,
  providers = { registers = false, marks = false, spelling = false },
  hints = { triggers = { { prefix = "<leader>", modes = { "n" } }, { prefix = "g", modes = { "n" } } } },
})
local leader, g = callback(" "), callback("g")
assert(leader and g)
local set, del, read = vim.keymap.set, vim.keymap.del, api.nvim_buf_get_keymap
local sets, deletes, reads = 0, 0, 0
vim.keymap.set = function(...)
  sets = sets + 1
  return set(...)
end
vim.keymap.del = function(...)
  deletes = deletes + 1
  return del(...)
end
api.nvim_buf_get_keymap = function(...)
  reads = reads + 1
  return read(...)
end
hints.refresh()
vim.keymap.set, vim.keymap.del, api.nvim_buf_get_keymap = set, del, read
assert(sets == 0 and deletes == 0, "unchanged triggers must not be reinstalled")
assert(reads <= 6, "ownership must be read once per buffer/mode")
assert(callback(" ") == leader and callback("g") == g)

-- A new exact global mapping must displace our existing local prefix trigger.
local user = function() end
vim.keymap.set("n", " ", user)
hints.refresh()
assert(callback(" ") == user and callback("g") == g and #hints.triggers == 1)
vim.keymap.del("n", " ")
hints.refresh()
assert(callback(" ") and #hints.triggers == 2)
vim.keymap.set("n", " ", user, { buffer = true })
hints.refresh()
assert(callback(" ") == user and #hints.triggers == 1, "refresh replaced another owner's local map")

hints.detach()
hints.suspended = true
api.nvim_exec_autocmds("SafeState", { group = "KeymapToolsHints" })
assert(not hints.suspended and callback("g"), "replay recovery must reattach synchronously before the next key")

local refresh, calls = hints.refresh, 0
hints.refresh = function(...)
  calls = calls + 1
  return refresh(...)
end
for _, event in ipairs({ "BufEnter", "FileType" }) do
  api.nvim_exec_autocmds(event, { group = "KeymapToolsHints", buffer = 0 })
end
assert(calls == 0, "automatic events must defer their scan")
assert(vim.wait(100, function()
  return calls > 0
end))
assert(calls == 1, "automatic events in one turn must share a scan")
hints.request_refresh()
api.nvim_exec_autocmds("SafeState", { group = "KeymapToolsHints" })
assert(calls == 2, "SafeState must flush pending work synchronously without scheduling another idle cycle")
vim.wait(10, function()
  return false
end)
assert(calls == 2, "SafeState left a queued duplicate scan")
hints.request_refresh()
tools.refresh()
vim.wait(10, function()
  return false
end)
assert(calls == 3, "explicit refresh must cancel the queued duplicate")
hints.request_refresh()
hints.detach()
vim.wait(10, function()
  return false
end)
assert(calls == 3 and #hints.triggers == 0, "detach must cancel pending reattachment")
hints.refresh = refresh
hints.refresh()
local first = api.nvim_get_current_buf()
vim.cmd("enew")
tools.refresh()
assert(callback("g"), "new buffer did not receive its triggers")
for _, map in ipairs(api.nvim_buf_get_keymap(first, "n")) do
  assert(map.callback ~= g, "old buffer retained its trigger")
end
tools.setup({ hints = { enabled = false } })
assert(#hints.triggers == 0 and not callback("g"))
print("PASS trigger reuse, grouped ownership checks, exact-map displacement, event coalescing and cancellation")
