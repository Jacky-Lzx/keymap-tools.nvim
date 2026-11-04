vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = " "
vim.o.timeoutlen = 300
vim.o.ttimeoutlen = 30
local api = vim.api
local tools = require("keymap_tools")
local view = require("keymap_tools.view")
local keys = require("keymap_tools.keys")
local directory = assert(vim.env.KEYMAP_TOOLS_TEST_DIR)
tools.setup({ hints = { delay = 40 }, window = { height = 32 }, showkeys = { enabled = true, timeout = 0.2 } })
local serial = 0
local current_step = "startup"
local function wait_for(fn, label)
  current_step = label
  for _ = 1, 200 do
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
  end, "terminal delivery " .. serial)
end
local function hint(text)
  wait_for(function()
    return view.buf
      and api.nvim_buf_is_valid(view.buf)
      and table.concat(api.nvim_buf_get_lines(view.buf, 0, -1, false), "\n"):find(text, 1, true)
  end, "hint " .. text)
end
local function reset(lines, cursor)
  assert(keys.mode() == "n", "test reset outside Normal mode")
  api.nvim_buf_set_lines(0, 0, -1, false, type(lines) == "table" and lines or { lines })
  api.nvim_win_set_cursor(0, cursor or { 1, 0 })
end
local function line(text)
  wait_for(function()
    return api.nvim_get_current_line() == text and not view.win and keys.mode() == "n"
  end, "line " .. text)
end
local function check()
  local hints = require("keymap_tools.hints")
  local refresh, idle_calls = hints.refresh, 0
  hints.refresh = function(...)
    idle_calls = idle_calls + 1
    return refresh(...)
  end
  local idle_until = vim.uv.hrtime() + 150 * 1000000
  wait_for(function()
    return vim.uv.hrtime() >= idle_until
  end, "idle without a self-scheduling refresh loop")
  hints.refresh = refresh
  assert(idle_calls < 24, "SafeState refreshes kept the idle event loop busy: " .. idle_calls)

  local burst = 0
  vim.keymap.set("n", "<leader>sx", function()
    burst = burst + 1
  end, { desc = "Repeated prefix action" })
  reset("burst")
  send(string.rep(" sx", 40))
  wait_for(function()
    return burst == 40 and not view.win
  end, "continuous rapid prefix input")
  send(" s")
  hint("Repeated prefix action")
  send("\27")
  wait_for(function()
    return not view.win
  end, "reattached prefix after rapid input")

  reset("one two three")
  send("d")
  hint("Around text object")
  send("w")
  line("two three")
  send(".")
  line("three")
  send("u")
  line("two three")

  reset("one two three four")
  send('"b2d')
  hint("Around text object")
  send("w")
  line("three four")
  assert(vim.fn.getreg("b") == "one two ", "operator count or register lost")

  reset("one two three")
  send("d")
  hint("Around text object")
  send("2w")
  line("three")

  reset("one two")
  send("d")
  hint("Around text object")
  send("\27")
  wait_for(function()
    return keys.mode() == "n" and not view.win
  end, "cancel pending operator")
  assert(api.nvim_get_current_line() == "one two")

  send("d")
  hint("Around text object")
  send("\3")
  wait_for(function()
    return keys.mode() == "n" and not view.win
  end, "interrupt pending operator")
  assert(api.nvim_get_current_line() == "one two")

  reset({ "remove", "keep" })
  send("d")
  hint("Current line")
  send("d")
  line("keep")

  reset("old value")
  send("c")
  hint("Around text object")
  send("i")
  hint("Inside word")
  send("w")
  wait_for(function()
    return keys.mode() == "i"
  end, "change enters Insert mode")
  send("new\27")
  line("new value")

  reset("hello world")
  send("gU")
  hint("Around text object")
  send("iw")
  line("HELLO world")

  reset({ "first", "second", "third" })
  send("d")
  hint("Around text object")
  send("Vj")
  line("third")

  local dynamic = "Dynamic object"
  vim.keymap.set("o", "iQ", "iw")
  tools.register("test-object", {
    modes = { "o" },
    hints = {
      {
        keys = "iQ",
        desc = function(ctx)
          assert(ctx.mode == "o")
          return dynamic
        end,
      },
    },
  })
  reset("custom value")
  send("d")
  hint("Around text object")
  send("i")
  hint("Dynamic object")
  dynamic = "Updated object"
  send("Q")
  line(" value")

  local operator_calls = 0
  _G.keymap_tools_test_operator = function(kind)
    assert(kind == "char")
    operator_calls = operator_calls + 1
  end
  vim.go.operatorfunc = "v:lua.keymap_tools_test_operator"
  reset("custom operator")
  send("g@")
  hint("Around text object")
  send("iw")
  wait_for(function()
    return operator_calls == 1
  end, "custom g@ operator")

  -- Use the real installed mini.ai checkout, including its expr/getchar maps.
  local mini = vim.env.MINI_AI_DIR or vim.fn.stdpath("data") .. "/lazy/mini.ai"
  assert(vim.fn.isdirectory(mini) == 1, "set MINI_AI_DIR to the real mini.ai checkout")
  vim.opt.runtimepath:prepend(mini)
  require("mini.ai").setup({ silent = true })
  reset("one (inner words) tail", { 1, 6 })
  send("d")
  hint("Around text object")
  send("i")
  hint("Inside parentheses")
  send("(")
  line("one () tail")

  -- Recording and replaying a macro must never open an interactive hint.
  reset("one two three four")
  send("qadwq")
  line("two three four")
  send("@a")
  line("three four")
  assert(not view.win)

  tools.setup({ hints = { delay = 40 }, window = { height = 6 } })
  local function provider(prefix)
    wait_for(function()
      return view.win and view.frame and view.frame.prefix == keys.raw(prefix)
    end, "provider " .. prefix)
  end
  local function border_position()
    vim.cmd.redraw()
    local cfg = api.nvim_win_get_config(view.win)
    local pos = vim.fn.win_screenpos(view.win)
    local position = ("%d-%d/%d"):format(
      view.offset + 1,
      math.min(#view.frame.children, view.offset + view.frame.page),
      #view.frame.children
    )
    local footer = ""
    for col = pos[2] + 1, pos[2] + cfg.width do
      footer = footer .. vim.fn.screenstring(pos[1] + cfg.height + 1, col)
    end
    assert(footer:sub(-#position - 1) == position .. " ", "page position missing from bottom-right border: " .. footer)
    assert(footer:sub(1, 13) == " <C-d>/<C-u> ", "scrolling controls missing from bottom-left border: " .. footer)
    assert(view.frame.rows == cfg.height, "border footer should leave every content row available")
  end
  for key in ("abcdefghijklmnopqrstuvwxyz"):gmatch(".") do
    vim.fn.setreg(key, "content " .. key)
  end
  vim.fn.setreg("z", "REGISTER")
  reset("x")
  send('"')
  provider('"')
  border_position()
  local until_time = vim.uv.hrtime() + 450 * 1000000
  wait_for(function()
    return vim.uv.hrtime() >= until_time
  end, "provider stays open beyond timeoutlen")
  assert(view.win, "register group timed out into a native prefix")
  send("\4")
  wait_for(function()
    return view.offset > 0
  end, "scroll register list down")
  border_position()
  send("\21")
  wait_for(function()
    return view.offset == 0
  end, "scroll register list up")
  border_position()
  send("z")
  wait_for(function()
    return not view.win
  end, "select register")
  send("p")
  line("xREGISTER")

  reset("x")
  send("i\18")
  provider("<C-r>")
  send("z")
  wait_for(function()
    return api.nvim_get_current_line() == "REGISTERx"
  end, "insert register")
  send("\18")
  provider("<C-r>")
  send("z")
  wait_for(function()
    return api.nvim_get_current_line() == "REGISTERREGISTERx"
  end, "repeat insert register")
  send("\27")
  line("REGISTERREGISTERx")

  send(":\18")
  provider("<C-r>")
  send("z")
  wait_for(function()
    return vim.fn.getcmdline() == "REGISTER"
  end, "command-line register")
  send("\27")
  wait_for(function()
    return keys.mode() == "n"
  end, "cancel command line")

  reset("x")
  send("i\18")
  provider("<C-r>")
  send("\27")
  wait_for(function()
    return not view.win
  end, "cancel insert-register hint")
  assert(keys.mode() == "i", "cancelling register hint left Insert mode")
  send("\27")
  line("x")

  reset({ "origin", "target marker" })
  api.nvim_buf_set_mark(0, "a", 2, 3, {})
  send("'")
  provider("'")
  send("a")
  wait_for(function()
    return api.nvim_win_get_cursor(0)[1] == 2
  end, "linewise mark")
  assert(api.nvim_win_get_cursor(0)[2] == 0)
  api.nvim_win_set_cursor(0, { 1, 0 })
  send("`")
  provider("`")
  send("a")
  wait_for(function()
    return api.nvim_win_get_cursor(0)[1] == 2 and api.nvim_win_get_cursor(0)[2] == 3
  end, "exact mark")

  vim.bo.spelllang = "en"
  vim.wo.spell = true
  reset("teh")
  vim.cmd.normal({ args = { "1z=" }, bang = true })
  local corrected = api.nvim_get_current_line()
  assert(corrected ~= "teh", "native spelling baseline missing")
  reset("teh")
  send("z=")
  provider("z=")
  send("1")
  line(corrected)
  send("u")
  line("teh")
  send("1z=")
  line(corrected)
end
local thread = coroutine.create(check)
local timer = vim.uv.new_timer()
local finished = false
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
              "PASS operator hints, custom/mini.ai textobjects, counts/registers, dot/undo, change, forced motion, g@, macros, scrolling, register hints in n/i/c, exact/linewise marks and native spelling",
            }
          or vim.split(
            tostring(err) .. "\nStep: " .. current_step .. "\n" .. debug.traceback(thread),
            "\n",
            { plain = true }
          ),
        directory .. "/result"
      )
      vim.cmd(ok and "qa!" or "cquit 1")
    end
  end)
)
