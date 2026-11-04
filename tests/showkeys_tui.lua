vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = " "
vim.o.timeoutlen = 200
vim.o.ttimeoutlen = 30
local api = vim.api
local tools = require("keymap_tools")
local directory = assert(vim.env.KEYMAP_TOOLS_TEST_DIR)
local serial, step = 0, "startup"
local function wait_for(fn, label)
  step = label
  for _ = 1, 160 do
    if fn() then
      return
    end
    coroutine.yield()
  end
  local cast = package.loaded["keymap_tools.showkeys"]
  local line = cast
    and cast.buf
    and api.nvim_buf_is_valid(cast.buf)
    and api.nvim_buf_get_lines(cast.buf, 0, 1, false)[1]
  error("Timed out: " .. label .. "; cast=" .. tostring(line))
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
  local hits = 0
  vim.keymap.set("n", "<F2>", function() end)
  vim.keymap.set("n", "<C-l>", function() end)
  vim.keymap.set("n", "<leader>sa", function()
    hits = hits + 1
  end, { desc = "Screencast action" })
  local function setup(opts)
    tools.setup({
      hints = { delay = 30 },
      showkeys = vim.tbl_extend("force", { enabled = true, timeout = 1 }, opts or {}),
    })
  end
  setup()
  local cast = require("keymap_tools.showkeys")
  local view = require("keymap_tools.view")
  local origin, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, -1, false, { "sample" })
  local function text()
    return cast.buf and api.nvim_buf_is_valid(cast.buf) and api.nvim_buf_get_lines(cast.buf, 0, 1, false)[1] or ""
  end
  local function shown(expected)
    wait_for(function()
      return text() == expected
    end, "screencast " .. expected)
    vim.cmd.redraw()
    assert(api.nvim_get_current_win() == origin and api.nvim_get_current_buf() == buf, "screencast stole focus")
    local cfg = api.nvim_win_get_config(cast.win)
    assert(not cfg.focusable and cfg.height == 1)
    local pos = vim.fn.win_screenpos(cast.win)
    local screen = ""
    for col = pos[2] + 1, pos[2] + cfg.width do
      screen = screen .. vim.fn.screenstring(pos[1] + 1, col)
    end
    assert(screen == expected, "terminal frame differs: " .. screen)
  end
  send("\27OQ") -- Show the typed key rather than a callback mapping's RHS.
  shown(" F2 ")
  send("\12")
  shown(" F2   Ctrl + l ")
  send("i中<\27")
  shown(" Ctrl + l   i   中   <   Esc ") -- Five-key history evicts the oldest key.
  assert(api.nvim_get_current_line() == "中<sample", "screencast changed inserted input")
  wait_for(function()
    return not cast.win
  end, "inactivity timeout")
  assert(tools.showkeys.is_enabled(), "timeout disabled the listener")
  send(" s")
  wait_for(function()
    return view.win and cast.win
  end, "hints and screencast together")
  shown(" ␣   s ")
  assert(
    vim.fn.win_screenpos(cast.win)[1] + 2 < vim.fn.win_screenpos(view.win)[1],
    "screencast covers hints: "
      .. vim.inspect({
        cast = api.nvim_win_get_config(cast.win),
        hint = api.nvim_win_get_config(view.win),
        castpos = vim.fn.win_screenpos(cast.win),
        hintpos = vim.fn.win_screenpos(view.win),
      })
  )
  send("a")
  wait_for(function()
    return hits == 1 and not view.win
  end, "hint mapping replay")
  shown(" ␣   s   a ")
  wait_for(function()
    return not cast.win
  end, "clear before fast mapping")
  send(" sa")
  wait_for(function()
    return hits == 2
  end, "fast prefix mapping")
  shown(" ␣   s   a ")
  wait_for(function()
    return not cast.win
  end, "clear before input burst")
  send("iabcde\27")
  shown(" b   c   d   e   Esc ")
  setup({ show_count = true, timeout = 0.25 })
  send("jjj")
  shown(" 3 j ")
  wait_for(function()
    return not cast.win
  end, "count timeout")
  setup({ maxkeys = 1 })
  vim.keymap.set("n", "Q", "lll")
  send("Q")
  shown(" Q ")
  setup()
  vim.keymap.set("n", "<F3>", tools.showkeys.toggle)
  send("\27OR")
  wait_for(function()
    return not tools.showkeys.is_enabled() and not cast.win
  end, "disable from mapping with a queued render")
  send("\27ORj")
  shown(" j ")
  setup({ excluded_modes = { "i", "c" } })
  send("iHidden")
  wait_for(function()
    return api.nvim_get_current_line():find("Hidden", 1, true) and not cast.win
  end, "excluded Insert")
  send("\27")
  wait_for(function()
    return api.nvim_get_mode().mode == "n"
  end, "leave excluded Insert")
  send(":echo 'private'")
  wait_for(function()
    return api.nvim_get_mode().mode == "c" and vim.fn.getcmdline() == "echo 'private'" and not cast.win
  end, "excluded command line")
  send("\27")
  wait_for(function()
    return api.nvim_get_mode().mode == "n"
  end, "leave command line")
  setup({ keyformat = { ["<F2>"] = "测试", ["<C>"] = "Control" } })
  send("\27OQ\12")
  shown(" 测试   Control + l ")
  local ns = api.nvim_get_namespaces()["keymap_tools.showkeys"]
  local spans = api.nvim_buf_get_extmarks(cast.buf, ns, 0, -1, { details = true })
  assert(#spans == 2 and spans[2][4].hl_group == "KeymapToolsShowkeysActive")
  api.nvim_exec_autocmds("ColorScheme", {})
  for _, position in ipairs({ "top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right" }) do
    setup({ position = position })
    send("j")
    shown(" j ")
    local cfg = api.nvim_win_get_config(cast.win)
    assert((cfg.row < 2) == (position:sub(1, 3) == "top"), "wrong vertical position")
    if position:match("left$") then
      assert(cfg.col == 1)
    end
    if position:match("right$") then
      assert(cfg.col + cfg.width + 3 == vim.o.columns)
    end
  end
  vim.o.columns = 18
  api.nvim_exec_autocmds("VimResized", {})
  send("iabcdefghij\27")
  wait_for(function()
    return text():find("Esc", 1, true)
  end, "narrow terminal newest key")
  assert(vim.fn.strdisplaywidth(text()) <= 14)
  local oldbuf = cast.buf
  api.nvim_buf_delete(oldbuf, { force = true })
  send("j")
  wait_for(function()
    return cast.buf and cast.buf ~= oldbuf and api.nvim_buf_is_valid(cast.buf)
  end, "external buffer deletion recovery")
  vim.cmd.tabnew()
  assert(not cast.win and tools.showkeys.is_enabled())
  vim.cmd.tabclose()
  send("j")
  wait_for(function()
    return cast.win
  end, "new tab listener retained")
  tools.showkeys.disable()
  assert(not cast.win and not cast.buf)
  send("j")
  local until_time = vim.uv.hrtime() + 100000000
  wait_for(function()
    return vim.uv.hrtime() >= until_time
  end, "disabled idle")
  assert(not cast.win and not tools.showkeys.is_enabled())
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
              "PASS showkeys real terminal rendering, typed mappings, Unicode, bursts, hint replay, exclusion, timeout, positions, resize, tabs and cleanup",
            }
          or vim.split(tostring(err) .. "\nStep: " .. step .. "\n" .. debug.traceback(thread), "\n", { plain = true }),
        directory .. "/result"
      )
      vim.cmd(ok and "qa!" or "cquit 1")
    end
  end)
)
