vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:prepend(vim.env.SELECTION_TOOLS_DIR or "../selection-tools.nvim")
vim.g.mapleader = " "
local api, tools = vim.api, require("keymap_tools")
local hints = require("keymap_tools.hints")
local function trigger(lhs, mode)
  return vim.fn.maparg(lhs, mode or "n", false, true).callback
end
local hits = 0
vim.keymap.set("n", "<leader>aa", function()
  hits = hits + 1
end, { desc = "Panel test action" })
local buf = api.nvim_get_current_buf()
vim.bo.buftype, vim.bo.filetype = "nofile", "test-panel"
tools.setup()
assert(#hints.triggers == 0, "default must continue excluding nofile buffers")
local enabled, contexts = true, {}
local function filter(ctx)
  contexts[#contexts + 1] = vim.deepcopy(ctx)
  local allowed = enabled
    and ctx.buftype == "nofile"
    and ctx.filetype == "test-panel"
    and ctx.mode == "n"
    and ctx.prefix == "<Space>"
  ctx.buf = -1 -- The callback receives detached state.
  return allowed
end
tools.setup({ hints = { filter = filter } })
assert(#hints.triggers == 1 and trigger("<Space>"))
assert(not trigger("g") and not trigger("'", "n") and not trigger("<C-r>", "i"))
assert(not trigger("<Space>", "x"), "filter must apply per mode")
assert(contexts[1].buf == buf and contexts[1].win == api.nvim_get_current_win())
local panel_trigger = trigger("<Space>")
enabled = false
-- Trigger eligibility is rechecked before display; rejected input is replayed.
panel_trigger()
api.nvim_feedkeys("aa", "xt", false)
assert(hits == 1, "a newly rejected prefix swallowed the original mapping")
api.nvim_exec_autocmds("SafeState", { group = "KeymapToolsHints" })
assert(not trigger("<Space>"))
enabled = true
tools.refresh()
assert(trigger("<Space>"))
local function native() end
vim.keymap.set("n", "<Space>", native, { buffer = buf })
tools.refresh()
assert(trigger("<Space>") == native, "filter must not replace native prefix actions")
vim.keymap.set("n", "<Space>", "<Nop>", { buffer = buf })
tools.refresh()
assert(vim.fn.maparg("<Space>", "n", false, true).rhs == "<Nop>")
vim.keymap.del("n", "<Space>", { buffer = buf })
vim.bo.filetype = "test-preview"
tools.refresh()
assert(#hints.triggers == 0, "filetype changes must remove automatic triggers")
tools.setup({ hints = {
  filter = function()
    error("owner unavailable")
  end,
} })
assert(#hints.triggers == 0, "filter failures must skip automatic hints")
assert(not hints.show({ mode = "n", automatic = true }), "operator-style empty prefixes bypassed filter")
-- Explicit inspection and display remain usable even with a rejecting filter.
assert(#tools.list({ mode = "n" }) > 0)
vim.schedule(hints.hide)
assert(tools.show({ prefix = "<leader>", mode = "n" }))
local picker = tools.pick({ mode = "n" })
assert(picker and not picker.closed, "manual picker was blocked by hints.filter")
picker:close()
tools.dispose()
print("PASS automatic filter defaults, contexts, per-mode/provider rules, replay, ownership and explicit actions")
