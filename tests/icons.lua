vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api, tools = vim.api, require("keymap_tools")
local keys = require("keymap_tools.keys")
vim.g.mapleader = " "
local original = { icon = "界", hl = "DiagnosticWarn" }
local handle = tools.register("icons", {
  groups = { { prefix = "<leader>s", label = "Search", icon = original } },
  hints = {
    { keys = "<leader>sa", desc = "Find file", icon = "★" },
    { keys = "<leader>sb", desc = "Find buffer", icon = false },
  },
  toggles = {
    {
      keys = "<leader>sc",
      name = "Wrap",
      icon = "✓",
      get = function()
        return true
      end,
    },
  },
})
original.icon = "mutated"
assert(not package.loaded["keymap_tools.icons"], "metadata registration loaded presentation")
vim.keymap.set("n", "<leader>sa", "<Nop>", { desc = "Owner mapping" })
local function row(lhs)
  for _, item in ipairs(tools.list({ mode = "n", prefix = "<leader>s" })) do
    if item.keys == lhs then
      return item
    end
  end
  error("missing row: " .. lhs)
end
assert(row("<Space>sa").icon == "★" and row("<Space>sa").kind == "mapping")
assert(row("<Space>sb").icon == false, "an explicit opt-out was lost")
assert(row("<Space>sc").icon == "✓" and row("<Space>sc").toggle.state)
local group = row("<Space>s")
assert(group.icon.icon == "界", "registration retained caller-owned metadata")
group.icon.icon = "changed"
assert(row("<Space>s").icon.icon == "界", "queries leaked mutable icon metadata")
assert(not package.loaded["keymap_tools.icons"], "read-only queries loaded icon rendering")
local override = tools.register("icons.local", {
  buf = 0,
  hints = { { keys = "<leader>sa", desc = "Local override", icon = false } },
})
assert(row("<Space>sa").icon == false)
override:dispose()
assert(row("<Space>sa").icon == "★")

local config = require("keymap_tools.config")
local query = require("keymap_tools.query")
local items, groups = query.hints({ mode = "n" }, config.get())
local child = require("keymap_tools.maps").children(items, " ", groups)
local found
for _, candidate in ipairs(child) do
  if candidate.key == "s" then
    found = candidate
  end
end
assert(found and found.group and found.icon.icon == "界", "group icon did not reach the hint model")
local icons = require("keymap_tools.icons")
assert(icons.resolve({ desc = "Search files" }) == icons.resolve({ desc = "搜索文件" }))
assert(icons.resolve({ desc = "Unclassified action" }) ~= "", "ordinary entries need a fallback icon")
assert(icons.resolve({ group = true, desc = "Unclassified" }) ~= icons.resolve({ desc = "Unclassified" }))
assert(icons.resolve({ desc = "File", icon = false }) == "")
assert(icons.resolve({ desc = "File", icon = "★" }) == "★")
local glyph, hl = icons.resolve({ desc = "File", icon = { icon = "界", hl = "DiagnosticWarn" } })
assert(glyph == "界" and hl == "DiagnosticWarn")
assert(icons.resolve({ desc = "Disable wrap", toggle = { state = true } }) ~= icons.resolve({
  desc = "Enable wrap",
  toggle = { state = false },
}))
local custom = config.normalize({ icons = { rules = { { pattern = "file", icon = "F", hl = "Title" } } } }).icons
assert(icons.resolve({ desc = "Find file" }, custom) == "F", "custom rules must override built-in rules")
assert(icons.resolve({ desc = "Find file", icon = "★" }, custom) == "★")
assert(icons.resolve({ icon = "★" }, { enabled = false, rules = {} }) == "")
for _, option in ipairs({
  { enabled = "yes" },
  { unknown = true },
  { rules = { { pattern = "[", icon = "x" } } },
  { rules = { { pattern = "x", icon = "\n" } } },
  { rules = "bad" },
}) do
  assert(not pcall(config.normalize, { icons = option }), "invalid icon options accepted")
end
for _, icon in ipairs({ true, { icon = "x", color = "red" }, { hl = "Title" }, "x\ny" }) do
  assert(not pcall(tools.register, "bad-icon", { hints = { { keys = "x", desc = "X", icon = icon } } }))
end

assert(keys.display(keys.raw("<C-w><Space><CR><Tab><Left><M-x>")) == "Ctrl+w␣↵⇥←Alt+x")
assert(keys.display(keys.raw("中<F2>")) == "中F2")
assert(keys.label(keys.raw("<C-w>")) == "<C-W>", "display formatting changed canonical labels")
local view = require("keymap_tools.view")
vim.o.columns, vim.o.lines = 120, 36
api.nvim_set_hl(0, "KeymapToolsIcon", { fg = 0x123456 })
view.highlights()
assert(api.nvim_get_hl(0, { name = "KeymapToolsIcon" }).fg == 0x123456, "setup overwrote a user highlight")
view.show({
  { key = keys.raw("<CR>"), desc = "中文 é description", icon = "界" },
  { key = "b", desc = "Second", icon = "★" },
  { key = "c", desc = "No icon", icon = false },
  { key = "d", desc = "Group", group = true, icon = { icon = "✓", hl = "DiagnosticWarn" } },
}, "", "n", { width = 80, height = 2, columns = 2, border = "rounded" })
local lines = api.nvim_buf_get_lines(view.buf, 0, -1, false)
local desc1, desc2 = lines[1]:find("中文", 1, true), lines[2]:find("Second", 1, true)
assert(
  vim.fn.strdisplaywidth(lines[1]:sub(1, desc1 - 1)) == vim.fn.strdisplaywidth(lines[2]:sub(1, desc2 - 1)),
  "icons of different widths shifted descriptions"
)
for _, mark in
  ipairs(api.nvim_buf_get_extmarks(view.buf, api.nvim_create_namespace("keymap_tools.view"), 0, -1, { details = true }))
do
  assert(mark[4].end_col <= #lines[mark[2] + 1], "highlight extends beyond UTF-8 row")
end
config.set(config.normalize({ icons = { enabled = false } }))
view.show({ { key = "a", desc = "Find file" } }, "", "n", { width = 40, height = 2, border = "rounded" })
assert(
  api.nvim_buf_get_lines(view.buf, 0, 1, false)[1] == " a › Find file",
  "disabled icons retained an empty gutter"
)
view.hide()
handle:dispose()
print("PASS icon metadata ownership/precedence, lazy queries, semantic/custom icons, key labels and Unicode layout")
