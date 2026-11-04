vim.opt.runtimepath:prepend(vim.fn.getcwd())
local tools = require("keymap_tools")
local keys = require("keymap_tools.keys")
local maps = require("keymap_tools.maps")
local view = require("keymap_tools.view")
vim.g.mapleader = " "
vim.g.maplocalleader = ","
local buf = vim.api.nvim_get_current_buf()
local function find(items, lhs)
  for _, item in ipairs(items) do
    if item.keys == keys.raw(lhs) then
      return item
    end
  end
end

vim.keymap.set("n", "<leader>aa", "<Nop>", { desc = "global" })
local local_action = function() end
vim.keymap.set("n", "<Space>aa", local_action, { buffer = buf, desc = "local 中文" })
vim.keymap.set("n", "<leader>ab", "<Cmd>echo 'second'<CR>")
vim.keymap.set("n", "<Plug>(private)", "<Nop>")
vim.keymap.set("v", "<leader>vv", "<Nop>", { desc = "visual" })
local items = maps.collect({ mode = "n" })
assert(find(items, " aa").scope == "buffer")
assert(find(items, " aa").map.callback == local_action)
assert(find(items, " aa").desc == "local 中文")
assert(not find(items, "<Plug>(private)"))
assert(find(maps.collect({ mode = "n", plugs = true }), "<Plug>(private)"))
assert(find(maps.collect({ mode = "n", scope = "global" }), " aa").scope == "global")
assert(not find(maps.collect({ mode = "n", scope = "buffer" }), " ab"))
assert(find(maps.collect({ mode = "x" }), " vv"))
local before = find(items, " aa")
vim.keymap.set("n", " aa", "<Nop>", { buffer = buf })
assert(not maps.same(before, find(maps.collect({ mode = "n" }), " aa")))
assert(keys.raw("<localleader>") == ",")
assert(#keys.tokens(keys.raw("中<F2><lt>")) == 3)
local children = maps.children(items, " ", { [" a"] = "Actions" })
assert(children[1].desc == "Actions" and children[1].count == 2)

tools.setup({ hints = { delay = 0 } })
assert(vim.fn.maparg(" ?", "n") == "", "setup must not install a global picker shortcut")
assert(vim.fn.maparg(" ", "n", false, true).desc == "keymap-tools prefix hint")
assert(not find(maps.collect({ mode = "n" }), " "))
tools.setup({ hints = { enabled = false } })
assert(vim.fn.maparg(" ", "n") == "")
assert(vim.fn.maparg(" ?", "n") == "")
local user = function() end
vim.keymap.set("n", " ?", user)
tools.setup()
assert(vim.fn.maparg(" ?", "n", false, true).callback == user)
-- Replacing an installed trigger must survive refresh and disable.
vim.keymap.set("n", " ", user, { buffer = true })
tools.refresh()
tools.setup({ hints = { enabled = false } })
assert(vim.fn.maparg(" ", "n", false, true).callback == user)

view.highlights()
view.show(children, " ", "n", { width = 48, height = 16, border = "rounded" })
local cfg = vim.api.nvim_win_get_config(view.win)
assert(cfg.relative == "editor" and cfg.anchor == "SE" and cfg.focusable == false)
assert(vim.api.nvim_get_current_win() ~= view.win)
vim.o.columns = 20
view.show(
  { { key = "中", desc = string.rep("中文", 40) } },
  "",
  "n",
  { width = 48, height = 16, border = "rounded" }
)
local line = vim.api.nvim_buf_get_lines(view.buf, 0, 1, false)[1]
assert(vim.fn.strdisplaywidth(line) <= 16, "wide characters overflow narrow float")
view.hide()
assert(view.win == nil and view.buf == nil)
assert(tools.pick() == false, "missing optional dependency should not crash")
print("PASS effective maps, overrides, special keys, setup ownership, narrow float and missing dependency")
