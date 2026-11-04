vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = " "
local tools = require("keymap_tools")
local metadata = require("keymap_tools.metadata")
local catalog = require("keymap_tools.catalog")
local maps = require("keymap_tools.maps")
local buf = vim.api.nvim_get_current_buf()
local function find(items, raw)
  for _, item in ipairs(items) do
    if item.keys == raw then
      return item
    end
  end
end
local state = false
tools.add({
  mode = { "n", "o" },
  {
    "<leader>d",
    group = function()
      return state and "Enabled" or "Disabled"
    end,
  },
  {
    "<leader>dd",
    desc = function()
      return state and "Disable feature" or "Enable feature"
    end,
  },
  { "iQ", desc = "Custom object", mode = "o" },
})
local opts = { buf = buf, mode = "n" }
local config = { presets = true, groups = {} }
local items, groups = catalog.collect(opts, config)
assert(groups[" d"] == "Disabled")
assert(find(items, " dd").desc == "Enable feature" and find(items, " dd").virtual)
assert(not find(tools.get_keymaps({ mode = "n" }), " dd"), "metadata-only entries must not enter executable picker")
state = true
items, groups = catalog.collect(opts, config)
assert(groups[" d"] == "Enabled" and find(items, " dd").desc == "Disable feature")
tools.add({ { "<leader>dd", "<Nop>", desc = "Actual map" } })
assert(find(tools.get_keymaps({ mode = "n" }), " dd").map.noremap == 1)
tools.add({ buffer = true, { "<leader>dd", desc = "Local metadata" } })
assert(find(tools.get_keymaps({ mode = "n" }), " dd").desc == "Local metadata")
tools.add({
  { "<leader>hidden", desc = "Invisible", hidden = true },
  {
    "<leader>off",
    desc = "Disabled",
    cond = function()
      return false
    end,
  },
})
items = catalog.collect(opts, config)
assert(not find(items, " off"))
assert(#maps.children(items, " h", {}) == 0)
local other = vim.api.nvim_create_buf(false, true)
assert(metadata.get(other, "n")[" dd"].desc == "Actual map")
metadata.clear(buf)
assert(metadata.get(buf, "n")[" dd"].desc == "Actual map")
local op_items, op_groups = catalog.collect({ buf = buf, mode = "o", operator = "d" }, config)
assert(find(op_items, "iw") and find(op_items, "aw") and find(op_items, "d").desc == "Current line")
assert(op_groups.i == "Inside text object")
assert(find(op_items, "iQ").desc == "Custom object")
vim.keymap.set("n", "gg", "<Nop>", { desc = "My first line" })
items = catalog.collect(opts, config)
assert(find(items, "gg").desc == "My first line" and not find(items, "gg").virtual)
items = catalog.collect(opts, { presets = false, groups = {} })
assert(not find(items, "zz"))
tools.setup({ modes = { "o" } })
assert(vim.fn.exists("##ModeChanged") == 1)
print(
  "PASS dynamic metadata, scoped overrides, hidden/conditional entries, native presets and executable picker separation"
)
