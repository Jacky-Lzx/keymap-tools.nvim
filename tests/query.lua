vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api, tools = vim.api, require("keymap_tools")
vim.g.mapleader = " "
local function find(items, key, kind)
  for _, item in ipairs(items) do
    if item.keys == key and (not kind or item.kind == kind) then
      return item
    end
  end
end
local first_buf, first_win = api.nvim_get_current_buf(), api.nvim_get_current_win()
api.nvim_buf_set_name(first_buf, "/tmp/keymap-query-first.txt")
vim.wo.wrap = true
vim.cmd("vnew")
local second_buf, second_win = api.nvim_get_current_buf(), api.nvim_get_current_win()
api.nvim_buf_set_name(second_buf, "/tmp/keymap-query-second.txt")
vim.wo.wrap = false
tools.register("windows", {
  hints = {
    {
      keys = "<leader>w",
      desc = function(ctx)
        return api.nvim_get_option_value("wrap", { win = ctx.win }) and "Disable wrap" or "Enable wrap"
      end,
    },
  },
})
assert(find(tools.list({ win = first_win, mode = "n" }), "<Space>w").desc == "Disable wrap")
assert(find(tools.list({ win = second_win, mode = "n" }), "<Space>w").desc == "Enable wrap")
assert(api.nvim_get_current_win() == second_win, "query changed source focus")
vim.fn.setreg("z", "register value")
local choices = tools.list({ win = first_win, mode = "n", prefix = '"', kinds = { "choice" } })
assert(find(choices, '"z').desc == "register value")
assert(
  find(choices, '"%').desc:find("keymap-query-first.txt", 1, true),
  "provider used the active window instead of query window"
)
assert(api.nvim_get_current_win() == second_win)
assert(not find(choices, '"z').executable, "provider choices are not standalone keymaps")
local entries = tools.list({ mode = "o", operator = "d", prefix = "i" })
assert(find(entries, "iw", "hint") and find(entries, "i", "group"))
assert(#tools.list({ prefix = "not-a-real-prefix" }) == 0)

tools.register("group-hide", {
  groups = { { prefix = "<leader>h", label = "Hidden group", hidden = true } },
  hints = {
    { keys = "<leader>ha", desc = "Hidden descendant" },
  },
})
assert(not find(tools.list({ mode = "n" }), "<Space>ha"))
assert(find(tools.list({ mode = "n", include_hidden = true }), "<Space>ha").hidden)
tools.register("condition-base", { hints = { { keys = "<leader>c", desc = "Base" } } })
tools.register("condition-error", {
  priority = 10,
  when = function()
    error("condition failed")
  end,
  hints = { { keys = "<leader>c", desc = "Must not appear" } },
})
local rows, info = tools.list({ mode = "n" })
assert(find(rows, "<Space>c").desc == "Base" and #info.errors == 1)

local hidden = api.nvim_create_buf(false, true)
local handle = tools.register("early-buffer", { buf = hidden, hints = { { keys = "x", desc = "early" } } })
api.nvim_buf_delete(hidden, { force = true })
assert(not handle:dispose(), "buffer cleanup must work before setup")
assert(not pcall(tools.list, { global = false }))
assert(not pcall(tools.list, { kinds = "mapping" }))
assert(not pcall(tools.setup, { providers = { spelling = { suggestions = 0 } } }))
assert(not pcall(tools.setup, { hints = { triggers = { { prefix = "x", modes = { "t" } } } } }))
print(
  "PASS cross-window context, provider inspection, hidden groups, callback diagnostics and pre-setup buffer cleanup"
)
