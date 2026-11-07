vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api, tools = vim.api, require("keymap_tools")
vim.g.mapleader = " "
local notices = {}
vim.notify = function(message, level, opts)
  notices[#notices + 1] = { message = message, level = level, title = opts.title }
end
local function row(key, opts)
  local rows, info = tools.list(vim.tbl_extend("force", { mode = "n" }, opts or {}))
  assert(#info.errors == 0, vim.inspect(info.errors))
  for _, item in ipairs(rows) do
    if vim.keycode(item.keys) == vim.keycode(key) then
      return item
    end
  end
end
local reads, writes = 0, 0
local first = api.nvim_get_current_win()
vim.wo.wrap = false
local callback, registration = tools.register_toggle("wrap.action", {
  keys = "<leader>tw",
  name = "Wrap",
  get = function(ctx)
    reads = reads + 1
    return ctx.win and api.nvim_get_option_value("wrap", { win = ctx.win })
  end,
  set = function(state, ctx)
    writes = writes + 1
    api.nvim_set_option_value("wrap", state, { win = ctx.win })
    ctx.win = -1 -- The next getter must receive a fresh context.
  end,
})
assert(reads == 0 and writes == 0 and #notices == 0)
assert(vim.fn.maparg("<leader>tw", "n") == "", "Action registration must not install mappings")
assert(not package.loaded["keymap_tools.hints"] and not package.loaded["keymap_tools.view"])
assert(row("<leader>tw").desc == "Enable Wrap" and writes == 0 and #notices == 0)
vim.keymap.set("n", "<leader>tw", callback)
assert(callback() == true and vim.wo.wrap and writes == 1)
assert(notices[1].message == "Wrap: Enabled" and notices[1].level == vim.log.levels.INFO)
assert(callback() == false and not vim.wo.wrap and writes == 2)
assert(notices[2].message == "Wrap: Disabled" and notices[2].title == "Toggle")
vim.cmd("vnew")
local second = api.nvim_get_current_win()
vim.wo.wrap = true
assert(not row("<leader>tw", { win = first }).toggle.state)
assert(row("<leader>tw", { win = second }).toggle.state)
assert(api.nvim_get_current_win() == second)
callback()
assert(not vim.wo.wrap and not vim.wo[first].wrap)
local before = #notices
local unchanged = tools.register_toggle("unchanged", {
  keys = "<leader>tu",
  name = "Unchanged",
  get = function()
    return true
  end,
  set = function() end,
})
assert(unchanged() == true and notices[#notices].message == "Unchanged: Enabled")
local muted = tools.register_toggle("muted", {
  keys = "<leader>tm",
  name = "Muted",
  notify = false,
  get = function()
    return false
  end,
  set = function() end,
})
assert(muted() == false and #notices == before + 1)
for _, value in ipairs({ "unknown", "invalid", "getter", "setter" }) do
  local changed = false
  local run = tools.register_toggle(value, {
    keys = "<leader>te",
    name = value,
    get = function()
      if value == "unknown" then
        return nil
      elseif value == "invalid" then
        return 1
      elseif value == "getter" then
        error("getter unavailable")
      end
      return false
    end,
    set = function()
      if value == "setter" then
        error("setter unavailable")
      end
      changed = true
    end,
  })
  before = #notices
  assert(run() == nil and not changed)
  assert(#notices == before + 1 and notices[#notices].level == vim.log.levels.ERROR)
end
local bad = { keys = "x", name = "Invalid", get = function() end, set = function() end }
for key, value in pairs({ set = false, get = false, name = false, notify = "yes", extra = true }) do
  assert(not pcall(tools.register_toggle, "wrap.action", vim.tbl_extend("force", bad, { [key] = value })))
end
assert(registration:dispose(), "Invalid registrations replaced existing metadata")
assert(vim.fn.maparg("<leader>tw", "n", false, true).callback == callback, "Disposal removed the owner's map")
local buffer = api.nvim_create_buf(false, true)
local _, scoped = tools.register_toggle("scoped", {
  keys = "x",
  name = "Scoped",
  buf = buffer,
  get = function()
    return false
  end,
  set = function() end,
})
api.nvim_buf_delete(buffer, { force = true })
assert(not scoped:dispose())
print("PASS explicit toggle actions, read-only queries, live state, errors, contexts, scopes and mapping ownership")

local cold_state, action_calls = nil, 0
local action = tools.register_toggle("cold.action", {
  keys = "<F15>",
  name = "Cold",
  get = function()
    return cold_state
  end,
  action = function(ctx)
    action_calls = action_calls + 1
    ctx.buf = -1
    cold_state = not cold_state
  end,
})
assert(action_calls == 0)
assert(action() == true and action_calls == 1)
assert(action() == false and action_calls == 2)
local rejected = tools.register_toggle("reject.action", {
  keys = "<F14>",
  name = "Rejected",
  get = function()
    return nil
  end,
  action = function()
    return false, "provider refused"
  end,
})
assert(rejected() == nil and notices[#notices].message:find("provider refused", 1, true))
assert(not pcall(tools.register_toggle, "both", {
  keys = "x",
  name = "Both",
  get = function()
    return true
  end,
  set = function() end,
  action = function() end,
}))
