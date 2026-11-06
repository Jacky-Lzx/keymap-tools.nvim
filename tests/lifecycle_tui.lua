vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:prepend(vim.env.SELECTION_TOOLS_DIR or vim.fn.getcwd() .. "/../selection-tools.nvim")
vim.g.mapleader = " "
local api, tools = vim.api, require("keymap_tools")
local directory = assert(vim.env.KEYMAP_TOOLS_TEST_DIR)
local serial, step = 0, "startup"
local function wait_for(fn, label)
  step = label
  for _ = 1, 180 do
    if fn() then
      return
    end
    coroutine.yield()
  end
  error("Timed out: " .. label .. "; mode=" .. api.nvim_get_mode().mode)
end
local function send(raw)
  serial = serial + 1
  local file = assert(io.open(directory .. "/input", "wb"))
  file:write(raw)
  file:close()
  vim.fn.writefile({ tostring(serial) }, directory .. "/stage")
  wait_for(function()
    return vim.fn.filereadable(directory .. "/ack") == 1 and vim.fn.readfile(directory .. "/ack")[1] == tostring(serial)
  end, "delivery " .. serial)
end
local function check()
  local source, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
  local content = { "alpha beta", "second line", "third line" }
  api.nvim_buf_set_lines(source, 0, -1, false, content)
  local view, hints = require("keymap_tools.view"), require("keymap_tools.hints")
  local baseline = vim.on_key()
  local state = false
  local action, registration = tools.register_toggle("lifecycle", {
    keys = "<leader>tw",
    name = "Lifecycle toggle",
    notify = false,
    get = function()
      return state
    end,
    set = function(value)
      state = value
    end,
  })
  vim.keymap.set("n", "<leader>tw", action, { desc = "Toggle owned by the user" })
  vim.keymap.set("n", "<leader>tt", "<Nop>", { desc = "Another action" })
  local options = { hints = { delay = 20 }, showkeys = { enabled = true, maxkeys = 7, timeout = 1 } }
  tools.setup(options)
  send(" ")
  wait_for(function()
    return view.win and hints.session
  end, "normal hint window")
  assert(api.nvim_get_current_win() == win, "Hints stole source focus")
  tools.disable()
  tools.disable()
  wait_for(function()
    return not hints.session and not view.win
  end, "disable active hints")
  assert(not tools.is_enabled() and not tools.showkeys.is_enabled() and vim.on_key() == baseline)
  send("j")
  wait_for(function()
    return api.nvim_win_get_cursor(win)[1] == 2
  end, "native input after disable")
  tools.enable()
  assert(tools.showkeys.is_enabled() and require("keymap_tools.config").get().showkeys.maxkeys == 7)
  send("d")
  wait_for(function()
    return view.win and hints.session and hints.session.mode == "o"
  end, "operator hint window")
  tools.dispose()
  wait_for(function()
    return api.nvim_get_mode().mode == "n" and not hints.session
  end, "dispose pending operator")
  assert(vim.deep_equal(content, api.nvim_buf_get_lines(source, 0, -1, false)), "Disposal executed a pending operator")
  tools.enable()
  assert(not tools.showkeys.is_enabled(), "Full disposal retained screencast configuration")
  tools.setup(options)

  local picker = assert(tools.pick({ prefix = "<leader>t" }))
  wait_for(function()
    return api.nvim_get_mode().mode == "i"
  end, "keymap picker input")
  tools.dispose()
  wait_for(function()
    return picker.closed and api.nvim_get_mode().mode == "n" and api.nvim_get_current_win() == win
  end, "close owned picker")
  local selection = require("selection_tools")
  local unrelated = selection.select(
    { "Other owner's item" },
    { prompt = "Unrelated picker", preview = { enabled = false } },
    function() end
  )
  tools.dispose()
  assert(not unrelated.closed and api.nvim_win_is_valid(unrelated.input_win), "Disposal closed another owner's picker")
  unrelated:close()
  wait_for(function()
    return api.nvim_get_mode().mode == "n" and api.nvim_get_current_win() == win
  end, "return from unrelated picker")

  tools.setup(options)
  send("j")
  local cast = require("keymap_tools.showkeys")
  wait_for(function()
    return cast.win and cast.buf
  end, "screencast window")
  local cast_win, cast_buf = cast.win, cast.buf
  vim.bo[cast_buf].buftype, vim.bo[cast_buf].filetype, vim.bo[cast_buf].bufhidden = "", "text", "hide"
  vim.bo[cast_buf].modifiable = true
  api.nvim_buf_set_lines(cast_buf, 0, -1, false, { "Adopted screencast" })
  cast.redraw()
  assert(cast.buf ~= cast_buf and cast.win ~= cast_win, "Redraw reused an adopted screencast")
  tools.dispose()
  assert(api.nvim_win_is_valid(cast_win) and api.nvim_buf_is_valid(cast_buf))
  assert(api.nvim_buf_get_lines(cast_buf, 0, -1, false)[1] == "Adopted screencast")
  api.nvim_win_close(cast_win, true)
  api.nvim_buf_delete(cast_buf, { force = true })

  tools.setup({ hints = { delay = 20 } })
  send(" ")
  wait_for(function()
    return view.win and hints.session
  end, "hint before window adoption")
  local hint_win = view.win
  local adopted = api.nvim_create_buf(true, false)
  api.nvim_buf_set_lines(adopted, 0, -1, false, { "Different user buffer" })
  api.nvim_win_set_buf(hint_win, adopted)
  view.redraw()
  assert(view.win ~= hint_win, "Redraw reused an adopted hint window")
  tools.dispose()
  wait_for(function()
    return not hints.session
  end, "dispose adopted hint window")
  assert(api.nvim_win_is_valid(hint_win) and api.nvim_win_get_buf(hint_win) == adopted)
  assert(api.nvim_buf_get_lines(adopted, 0, -1, false)[1] == "Different user buffer")
  api.nvim_win_close(hint_win, true)
  api.nvim_buf_delete(adopted, { force = true })

  send(" tw")
  wait_for(function()
    return state
  end, "external toggle still executes after disposal")
  assert(not tools.is_enabled() and vim.on_key() == baseline)
  assert(api.nvim_get_current_win() == win and api.nvim_get_current_buf() == source)
  assert(vim.deep_equal(content, api.nvim_buf_get_lines(source, 0, -1, false)))
  assert(registration:dispose())
end
local thread = coroutine.create(check)
local timer, finished = vim.uv.new_timer(), false
timer:start(
  20,
  20,
  vim.schedule_wrap(function()
    if finished or coroutine.status(thread) == "running" then
      return
    end
    local ok, err = coroutine.resume(thread)
    if not ok or coroutine.status(thread) == "dead" then
      finished = true
      timer:stop()
      timer:close()
      vim.fn.writefile(
        ok
            and {
              "PASS lifecycle PTY: active normal/operator hints, native input, retained enable, owned/unrelated pickers, adopted windows/buffers and external toggle action",
            }
          or vim.split(tostring(err) .. "\nStep: " .. step .. "\n" .. debug.traceback(thread), "\n", { plain = true }),
        directory .. "/result"
      )
      vim.cmd(ok and "qa!" or "cquit 1")
    end
  end)
)
