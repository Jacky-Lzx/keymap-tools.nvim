vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = " "
local api = vim.api
local tools = require("keymap_tools")
local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
local before = #api.nvim_get_autocmds({})
local function rows(opts)
  return tools.list(vim.tbl_extend("force", { mode = "n", prefix = "<leader>" }, opts or {}))
end
local function find(items, lhs, kind)
  for _, item in ipairs(items) do
    if item.keys == lhs and (not kind or item.kind == kind) then
      return item
    end
  end
end

local base = tools.register("base", {
  groups = { { prefix = "<leader>a", label = "Actions" } },
  hints = {
    { keys = "<leader>aa", desc = "Base" },
  },
})
assert(#api.nvim_get_autocmds({}) == before, "registration must not initialize UI")
assert(vim.fn.maparg(" aa", "n") == "", "metadata must not create a keymap")
local override = tools.register("override", { hints = { { keys = "<leader>aa", desc = "Override" } } })
assert(find(rows(), "<Space>aa").source == "override")
assert(override:dispose() and not override:dispose())
assert(find(rows(), "<Space>aa").desc == "Base", "disposing must reveal the lower-priority source")
local local_handle =
  tools.register("local", { buf = buf, priority = -100, hints = { { keys = "<leader>aa", desc = "Local" } } })
assert(find(rows(), "<Space>aa").source == "local", "buffer metadata wins before priority")
local_handle:dispose()
local high = tools.register("high", { priority = 10, hints = { { keys = "<leader>aa", desc = "High" } } })
tools.register("low", { priority = -1, hints = { { keys = "<leader>aa", desc = "Low" } } })
assert(find(rows(), "<Space>aa").source == "high")
high:dispose()
base:replace({ hints = { { keys = "<leader>ab", desc = "Replacement" } } })
assert(not find(rows(), "<Space>a", "group"), "replace must remove old groups")
assert(find(rows(), "<Space>ab").source == "base")
assert(not pcall(base.replace, base, { hints = { { keys = "bad" } } }))
assert(find(rows(), "<Space>ab"), "failed replacement must retain previous data")
local fresh = tools.register("base", { hints = { { keys = "<leader>ac", desc = "Fresh" } } })
assert(not base:dispose() and not pcall(base.replace, base, {}), "stale handle must not modify a replacement")
assert(not find(rows(), "<Space>ab") and find(rows(), "<Space>ac"))
fresh:dispose()

local state = false
tools.register("dynamic", {
  hints = {
    {
      keys = "<leader>dd",
      desc = function(ctx)
        assert(ctx.buf == buf and ctx.win == win and ctx.mode == "n" and ctx.prefix == "<Space>")
        ctx.buf = -1
        return state and "Disable" or "Enable"
      end,
    },
  },
})
assert(find(rows(), "<Space>dd").desc == "Enable")
state = true
assert(find(rows(), "<Space>dd").desc == "Disable")
tools.register("hidden", {
  hints = {
    { keys = "<leader>hh", desc = "Hidden", hidden = true },
    {
      keys = "<leader>off",
      desc = "Conditional",
      when = function(ctx)
        return ctx.mode == "o"
      end,
    },
    {
      keys = "<leader>broken",
      desc = function()
        error("callback failure")
      end,
    },
  },
})
local items, info = rows()
assert(not find(items, "<Space>hh") and not find(items, "<Space>off") and not find(items, "<Space>broken"))
assert(find(rows({ include_hidden = true }), "<Space>hh"))
assert(#info.errors == 1 and info.errors[1].source == "hidden")
assert(info.context.buf == buf, "callbacks must receive isolated contexts")

vim.keymap.set("n", "<leader>ma", "<Nop>", { desc = "Global" })
vim.keymap.set("n", "<leader>ma", function() end, { buffer = buf, desc = "Buffer" })
tools.register("annotation", { hints = { { keys = "<leader>ma", desc = "Annotated" } } })
local map = find(rows({ kinds = { "mapping" } }), "<Space>ma")
assert(map.kind == "mapping" and map.executable and map.scope == "buffer")
assert(map.source == "neovim" and map.metadata_source == "annotation" and map.map == nil and map.virtual == nil)
assert(find(rows({ kinds = { "mapping" }, scope = "global" }), "<Space>ma").scope == "global")
assert(not find(rows({ kinds = { "mapping" } }), "<Space>dd"))
local scoped = tools.register("buffer-cleanup", { buf = buf, hints = { { keys = "<leader>only", desc = "Scoped" } } })
tools.setup({ hints = { enabled = false } })
local other = api.nvim_create_buf(false, true)
assert(not find(rows({ buf = other }), "<Space>only"))
api.nvim_buf_delete(buf, { force = true })
assert(not scoped:dispose(), "buffer wipe must release scoped handles")
assert(tools.add == nil and tools.get_keymaps == nil, "obsolete APIs must be removed")
assert(not pcall(tools.register, "legacy", { { "<leader>x", "<Nop>" } }))
assert(not pcall(tools.setup, { enabled = false }))
assert(not pcall(tools.setup, { picker = { key = "<leader>?" } }))
tools.setup({ hints = { triggers = {} }, providers = { registers = false, marks = false, spelling = false } })
assert(#require("keymap_tools.hints").triggers == 0, "empty triggers must replace defaults")
print(
  "PASS source ownership, priority/fallback, replacement/disposal, isolated contexts, unified query and explicit setup"
)
