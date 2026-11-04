vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api, tools = vim.api, require("keymap_tools")
vim.g.mapleader = " "
local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
local function row(opts, key)
  local items, info = tools.list(vim.tbl_extend("force", { mode = "n", prefix = "<leader>t" }, opts or {}))
  for _, item in ipairs(items) do
    if item.keys == (key or "<Space>tw") then
      return item, info
    end
  end
  return nil, info
end

local reads, writes = 0, 0
vim.wo.wrap = false
local function switch()
  writes = writes + 1
  vim.wo.wrap = not vim.wo.wrap
end
vim.keymap.set("n", "<leader>tw", switch, { desc = "Owner's wrap mapping" })
local handle = tools.register("window.wrap", {
  toggles = {
    {
      keys = "<leader>tw",
      name = "Wrap",
      get = function(ctx)
        reads = reads + 1
        assert(ctx.mode == "n")
        if not ctx.win then
          return nil
        end
        return api.nvim_get_option_value("wrap", { win = ctx.win })
      end,
    },
  },
})
assert(reads == 0 and writes == 0, "registration must not read or change owner state")
assert(not package.loaded["keymap_tools.hints"] and not package.loaded["keymap_tools.view"])
assert(vim.fn.maparg("<leader>tw", "n", false, true).callback == switch, "registration replaced the owner mapping")
local item = row()
assert(item.desc == "Enable Wrap" and item.toggle.name == "Wrap" and item.toggle.state == false)
assert(item.kind == "mapping" and item.executable and item.metadata_source == "window.wrap")
item.toggle.name, item.toggle.state = "Mutated", true
assert(row().toggle.name == "Wrap" and row().toggle.state == false, "query rows must be detached")
assert(writes == 0, "query must never switch a feature")
switch()
assert(row().desc == "Disable Wrap" and row().toggle.state == true, "state must be read fresh")

vim.cmd("vnew")
local other_win = api.nvim_get_current_win()
vim.wo.wrap = false
assert(row({ win = win }).toggle.state == true)
assert(row({ win = other_win }).toggle.state == false)
assert(api.nvim_get_current_win() == other_win, "reading another window changed focus")
local hidden_buf = api.nvim_create_buf(false, true)
item = row({ buf = hidden_buf })
assert(item.desc == "Toggle Wrap" and item.toggle.state == nil)

tools.register("session", {
  toggles = {
    {
      keys = "<leader>td",
      name = "Diagnostics",
      get = function()
        return vim.diagnostic.is_enabled()
      end,
    },
  },
})
vim.diagnostic.enable(false)
assert(row(nil, "<Space>td").toggle.state == false)
vim.diagnostic.enable(true)
assert(row(nil, "<Space>td").toggle.state == true)

local scoped = tools.register("window.wrap", {
  buf = buf,
  priority = -100,
  toggles = { {
    keys = "<leader>tw",
    name = "Local Wrap",
    get = function()
      return false
    end,
  } },
})
assert(row({ win = win }).desc == "Enable Local Wrap", "buffer metadata must take precedence")
assert(row({ win = win, scope = "global" }).desc == "Disable Wrap")
scoped:replace({ hints = { { keys = "<leader>tw", desc = "Ordinary description" } } })
assert(row({ win = win }).toggle == nil, "ordinary override must remove toggle metadata")
scoped:dispose()
assert(row({ win = win }).desc == "Disable Wrap")

local extra = tools.register("extra", {
  toggles = {
    {
      keys = "<leader>tx",
      name = function(ctx)
        ctx.buf = -1
        return "Unmapped feature"
      end,
      get = function(ctx)
        assert(ctx.buf == api.nvim_win_get_buf(ctx.win), "get must receive its own context copy")
        return nil
      end,
    },
    {
      keys = "<leader>th",
      name = "Hidden",
      hidden = true,
      get = function()
        return true
      end,
    },
    {
      keys = "<leader>to",
      name = "Operator",
      modes = { "o" },
      get = function()
        return false
      end,
    },
    {
      keys = "<leader>tn",
      name = "Inactive",
      when = false,
      get = function()
        error("inactive getter")
      end,
    },
  },
})
item = row(nil, "<Space>tx")
assert(item.kind == "hint" and not item.executable and item.desc == "Toggle Unmapped feature")
assert(not row({ kinds = { "mapping" } }, "<Space>tx"), "unmapped toggle entered executable results")
assert(vim.fn.maparg("<leader>tx", "n") == "", "metadata installed a mapping")
assert(not row(nil, "<Space>th") and row({ include_hidden = true }, "<Space>th").toggle.state == true)
assert(not row(nil, "<Space>to") and row({ mode = "o" }, "<Space>to").desc == "Enable Operator")
assert(not row(nil, "<Space>tn"))
local _, info = row()
assert(#info.errors == 0)

for _, invalid in ipairs({
  { keys = "x", name = "Missing getter" },
  { keys = "x", name = "Snapshot", get = false },
  {
    keys = "x",
    get = function()
      return true
    end,
  },
  {
    keys = "x",
    name = "Setter",
    get = function()
      return true
    end,
    set = function() end,
  },
}) do
  assert(not pcall(extra.replace, extra, { toggles = { invalid } }))
  assert(row(nil, "<Space>tx"), "failed validation changed registration")
end
extra:replace({
  toggles = {
    {
      keys = "<leader>te",
      name = "Unavailable",
      get = function()
        error("owner unavailable")
      end,
    },
    {
      keys = "<leader>ti",
      name = "Invalid",
      get = function()
        return 0
      end,
    },
  },
})
item, info = row(nil, "<Space>te")
assert(item.desc == "Toggle Unavailable" and item.toggle.state == nil)
assert(#info.errors == 2)
for _, err in ipairs(info.errors) do
  assert(err.source == "extra" and err.field == "get")
end
assert(row(nil, "<Space>ti").desc == "Toggle Invalid", "non-boolean state must not be treated as enabled")
extra:dispose()

-- Trigger discovery needs key presence, never a feature's state.
local before = reads
require("keymap_tools.query").triggers(
  require("keymap_tools.context").resolve({ win = win, mode = "n" }),
  require("keymap_tools.config").get(),
  { " " }
)
assert(reads == before, "trigger discovery must not read toggle state")
handle:dispose()
assert(row().toggle == nil and row().desc == "Owner's wrap mapping")
assert(vim.fn.maparg("<leader>tw", "n", false, true).callback == switch)
local cleanup = tools.register("cleanup", {
  buf = hidden_buf,
  toggles = { {
    keys = "x",
    name = "Temporary",
    get = function()
      return true
    end,
  } },
})
api.nvim_buf_delete(hidden_buf, { force = true })
assert(not cleanup:dispose())
print("PASS read-only toggle registration, fresh/unknown state, contexts, ownership, scopes, validation and cleanup")
