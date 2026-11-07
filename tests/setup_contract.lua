vim.opt.rtp:prepend(vim.fn.getcwd())
local api, tools = vim.api, require("keymap_tools")
local early = vim.v.vim_did_enter == 0
local function wait()
  vim.wait(20, function()
    return false
  end)
end
local function cold()
  for _, name in ipairs({ "config", "hints", "showkeys", "picker", "theme", "view" }) do
    assert(not package.loaded["keymap_tools." .. name], "Cold release loaded " .. name)
  end
end
tools.disable()
tools.disable()
tools.dispose()
tools.dispose()
assert(not tools.is_enabled())
cold()
local baseline = vim.on_key()
local handle = tools.register("lifecycle", { hints = { { keys = "qz", desc = "Retained metadata" } } })
vim.keymap.set("n", "q1", "<Nop>", { desc = "User mapping" })
local state = false
local action, toggle = tools.register_toggle("lifecycle.toggle", {
  keys = "q2",
  name = "Lifecycle",
  notify = false,
  get = function()
    return state
  end,
  set = function(value)
    state = value
  end,
})
vim.keymap.set("n", "q2", action)
local options = {
  defer = true,
  hints = { delay = 37, triggers = { { prefix = "q", modes = { "n" } } } },
  icons = { rules = { { pattern = "test", icon = "*" } } },
  showkeys = { enabled = true, maxkeys = 7 },
}
local caller = vim.deepcopy(options)
tools.setup(options)
assert(vim.deep_equal(caller, options), "setup mutated caller options")
local config = require("keymap_tools.config")
options.icons.rules[1].pattern = "changed"
options.hints.triggers[1].prefix = "changed"
assert(config.get().icons.rules[1].pattern == "test" and config.get().hints.triggers[1].prefix == "q")
assert(tools.showkeys.is_enabled())
if early then
  assert(not package.loaded["keymap_tools.hints"])
end
local startup = api.nvim_get_autocmds({ event = "VimEnter" })
if early then
  assert(#startup == 1)
end
for _, invalid in ipairs({
  false,
  { hints = { delay = -1 } },
  { hints = { filter = true } },
  { hints = { delay = math.huge } },
  { window = { width = math.huge } },
  { window = { border = "bad" } },
  { window = { border = { "a", "b", "c" } } },
  { showkeys = { winopts = { border = { { "x", 7 } } } } },
  { providers = false },
}) do
  local before = vim.deepcopy(config.get())
  local commands, handlers = api.nvim_get_commands({}), api.nvim_get_autocmds({})
  assert(not pcall(tools.setup, invalid), "Invalid setup was accepted")
  assert(vim.deep_equal(before, config.get()), "Invalid setup replaced configuration")
  assert(vim.deep_equal(commands, api.nvim_get_commands({})), "Invalid setup replaced commands")
  assert(vim.deep_equal(handlers, api.nvim_get_autocmds({})), "Invalid setup replaced handlers")
  assert(tools.showkeys.is_enabled() and vim.on_key() == baseline + 1)
end
tools.dispose()
tools.setup(caller)
if early then
  startup[1].callback()
  assert(not package.loaded["keymap_tools.hints"], "A stale startup callback activated a new instance")
end
api.nvim_exec_autocmds("VimEnter", {})
local hints = require("keymap_tools.hints")
local function trigger()
  for _, entry in ipairs(hints.triggers) do
    if entry.raw == "q" and entry.mode == "n" then
      return entry.callback
    end
  end
end
local old_trigger = assert(trigger(), "Configured prefix trigger was not installed")
local handlers = #api.nvim_get_autocmds({})
tools.setup(caller)
assert(#api.nvim_get_autocmds({}) == handlers, "Repeated setup accumulated handlers")
hints.request_refresh()
handle:replace({ hints = { { keys = "qz", desc = "Updated metadata" } } })
tools.disable()
tools.disable()
wait()
assert(not tools.is_enabled() and not tools.showkeys.is_enabled() and vim.on_key() == baseline)
assert(#hints.triggers == 0 and vim.fn.exists("#KeymapToolsHints") == 0)
local rows = tools.list({ mode = "n", prefix = "qz" })
assert(
  rows[1].desc == "Updated metadata" and not tools.is_enabled(),
  "Inspection reactivated hints or removed metadata"
)
tools.enable()
tools.refresh()
assert(tools.is_enabled() and tools.showkeys.is_enabled())
assert(config.get().hints.delay == 37 and config.get().showkeys.maxkeys == 7)
old_trigger()
assert(not hints.session, "Captured trigger from an old setup became active again")

-- Retain a user change to mapping options even when the callback is unchanged.
local callback = assert(trigger())
vim.keymap.set("n", "q", callback, { buffer = true, nowait = false, desc = "User options" })
local replacement = vim.fn.maparg("q", "n", false, true)
tools.refresh()
assert(vim.deep_equal(replacement, vim.fn.maparg("q", "n", false, true)))
tools.dispose()
assert(vim.deep_equal(replacement, vim.fn.maparg("q", "n", false, true)))
assert(vim.fn.maparg("q2", "n", false, true).callback == action)
assert(action() == true and state, "Disposal removed an external toggle action")
assert(vim.deep_equal(config.get(), config.normalize()), "Disposal retained setup options")
vim.keymap.del("n", "q", { buffer = true })

-- Registry cleanup belongs to its subscription; newer listeners survive.
tools.setup(caller)
local registry, changes = require("keymap_tools.registry"), 0
local stop = registry.on_change(function()
  changes = changes + 1
end)
tools.dispose()
handle:replace({ hints = { { keys = "qz", desc = "After disposal" } } })
wait()
assert(changes == 1, "Disposal removed a newer registry listener")
stop()
local stale = registry.on_change(function()
  error("Stale listener ran")
end)
handle:replace({ hints = { { keys = "qz", desc = "Queued" } } })
local current = registry.on_change(function()
  changes = changes + 1
end)
stale()
wait()
assert(changes == 1, "Old notification ran against a new subscription")
handle:replace({ hints = { { keys = "qz", desc = "Current" } } })
wait()
assert(changes == 2)
current()

-- Confirmation can already be queued when disposal closes the picker.
local original_selection = package.loaded.selection_tools
local original_components = package.loaded["selection_tools.components"]
package.loaded["selection_tools.components"] = {
  text = function(opts)
    return opts
  end,
}
local confirm, session
package.loaded.selection_tools = {
  current = function()
    return nil
  end,
  select = function(items, opts, on_choice)
    confirm = function()
      on_choice(items[1])
    end
    session = { closed = false }
    function session:close()
      self.closed = true
      opts.on_close(self, { reason = "dispose" })
    end
    return session
  end,
}
tools.setup(caller)
local replay, replays = hints.replay, 0
hints.replay = function()
  replays = replays + 1
end
assert(tools.pick({ prefix = "q" }) == session)
confirm()
tools.dispose()
wait()
assert(session.closed and replays == 0, "Disposed picker replayed a queued mapping")
hints.replay = replay
package.loaded.selection_tools = original_selection
package.loaded["selection_tools.components"] = original_components

-- An adopted window/buffer must not be forced closed or wiped.
local view = require("keymap_tools.view")
view.show({ { key = "a", desc = "Owned hint" } }, "q", "n", config.get().window)
local win, buf = view.win, view.buf
vim.bo[buf].buftype, vim.bo[buf].filetype, vim.bo[buf].bufhidden = "", "text", "hide"
vim.bo[buf].modifiable = true
api.nvim_buf_set_lines(buf, 0, -1, false, { "User content" })
view.redraw()
assert(view.buf ~= buf and view.win ~= win, "Redraw reused an adopted buffer")
tools.dispose()
assert(api.nvim_win_is_valid(win) and api.nvim_buf_is_valid(buf))
assert(api.nvim_buf_get_lines(buf, 0, -1, false)[1] == "User content")
api.nvim_win_close(win, true)
api.nvim_buf_delete(buf, { force = true })

tools.enable()
assert(config.get().hints.delay == config.normalize().hints.delay and not tools.showkeys.is_enabled())
tools.dispose()
assert(handle:dispose() and toggle:dispose())
io.stdout:write(
  "PASS setup isolation/validation, deferred cancellation, retained disable, cold/repeated disposal, stale replay, subscription and user ownership\n"
)
