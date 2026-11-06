-- Real PTY input exercises insertion positions and native mapping replay.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:prepend(vim.env.SELECTION_TOOLS_DIR or vim.fn.getcwd() .. "/../selection-tools.nvim")
vim.o.swapfile = false
local api, tools = vim.api, require("keymap_tools")
local directory = assert(vim.env.KEYMAP_TOOLS_TEST_DIR)
local serial, step = 0, "startup"
local function wait_for(fn, label)
  step = label
  for _ = 1, 150 do
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
  local latest, hits, global_hits, expr_hits, plug_hits = nil, 0, 0, 0, 0
  local selection = require("selection_tools")
  selection.setup({ item_icons = false })
  local select_items = selection.select
  selection.select = function(...)
    latest = select_items(...)
    return latest
  end
  tools.setup({ hints = { delay = 20 } })
  vim.keymap.set({ "n", "x", "i" }, "<C-/>", function()
    tools.pick()
  end, { desc = "Choose keymap" })
  vim.keymap.set("n", "<F6>", "<Nop>", { desc = "Normal only action" })
  vim.keymap.set("i", "<F6>", function()
    global_hits = global_hits + 1
  end, { desc = "Shadowed Insert action" })
  vim.keymap.set("i", "<F6>", function()
    assert(api.nvim_get_current_win() == win and api.nvim_get_current_buf() == source)
    assert(api.nvim_get_mode().mode == "i", "Insert callback executed in wrong mode")
    hits = hits + 1
  end, { buffer = source, desc = "Local Insert callback" })
  vim.keymap.set("i", "<F7>", function()
    assert(api.nvim_get_mode().mode == "i", "Insert expression executed in wrong mode")
    expr_hits = expr_hits + 1
    return "EXPR"
  end, { expr = true, desc = "Insert expression action" })
  vim.keymap.set("i", "<Plug>(insert-test)", function()
    assert(api.nvim_get_mode().mode == "i", "Insert Plug executed in wrong mode")
    plug_hits = plug_hits + 1
  end)
  vim.keymap.set("i", "<F8>", "<Plug>(insert-test)", { remap = true, desc = "Insert remapped action" })
  vim.keymap.set("i", "<F9>", "TEXT", { desc = "Insert RHS action" })
  local function prepare(line, col, enter)
    send("\27")
    wait_for(function()
      return api.nvim_get_mode().mode == "n"
    end, "normal preparation")
    api.nvim_buf_set_lines(source, 0, -1, false, { line })
    api.nvim_win_set_cursor(win, { 1, col })
    send(enter or "i")
    wait_for(function()
      return api.nvim_get_mode().mode == "i"
    end, "source Insert mode")
  end
  local function open()
    local previous = latest
    send("\27[47;5u") -- CSI-u Ctrl+/ through the terminal decoder.
    wait_for(function()
      return latest ~= previous and latest and not latest.closed and api.nvim_get_mode().mode == "i"
    end, "Insert picker input")
    assert(latest.opts.prompt == "Buffer keymaps · i")
    for _, entry in ipairs(latest.matches) do
      assert(entry.item.desc ~= "Normal only action" and entry.item.desc ~= "Shadowed Insert action")
    end
    return latest
  end
  local function choose(query)
    local picker = open()
    send(query)
    wait_for(function()
      return picker.query == query and not picker.matching and #picker.matches == 1
    end, "filtered " .. query)
    vim.cmd.redraw()
    local pos = vim.fn.win_screenpos(picker.list_win)
    local text = ""
    for col = pos[2], pos[2] + api.nvim_win_get_width(picker.list_win) - 1 do
      text = text .. vim.fn.screenstring(pos[1], col)
    end
    assert(text:find(query, 1, true), "Search result absent from rendered terminal")
    send("\r")
    wait_for(function()
      return picker.closed and api.nvim_get_current_win() == win and api.nvim_get_mode().mode == "i"
    end, "restored Insert after " .. query)
  end
  for _, case in ipairs({
    { "abcd", 0, "i", "!abcd" },
    { "abcd", 2, "i", "ab!cd" },
    { "abcd", 0, "A", "abcd!" },
    { "", 0, "i", "!" },
    { "中文ab", 3, "i", "中!文ab" },
    { "中文", 0, "A", "中文!" },
  }) do
    prepare(case[1], case[2], case[3])
    local cursor = api.nvim_win_get_cursor(win)
    local picker = open()
    send("\27")
    wait_for(function()
      return picker.closed and api.nvim_get_current_win() == win and api.nvim_get_mode().mode == "i"
    end, "cancel restores Insert")
    assert(vim.deep_equal(cursor, api.nvim_win_get_cursor(win)), "Cancellation shifted insertion cursor")
    send("!")
    wait_for(function()
      return api.nvim_get_current_line() == case[4]
    end, "typing at restored position " .. case[4])
  end
  prepare("abcd", 2)
  choose("Local Insert callback")
  wait_for(function()
    return hits == 1
  end, "Insert callback replay")
  assert(global_hits == 0)
  send("!")
  wait_for(function()
    return api.nvim_get_current_line() == "ab!cd"
  end, "callback preserved position")
  prepare("abcd", 2)
  choose("Insert expression action")
  wait_for(function()
    return api.nvim_get_current_line() == "abEXPRcd" and expr_hits == 1
  end, "Insert expression result")
  prepare("abcd", 0, "A")
  choose("Insert RHS action")
  wait_for(function()
    return api.nvim_get_current_line() == "abcdTEXT"
  end, "Insert RHS at EOL")
  prepare("abcd", 2)
  choose("Insert remapped action")
  wait_for(function()
    return plug_hits == 1
  end, "Insert Plug chain")
  -- A stale Insert mapping remains rejected, then cancellation resumes typing.
  local picker = open()
  send("Insert RHS action")
  wait_for(function()
    return not picker.matching and #picker.matches == 1 and picker.query == "Insert RHS action"
  end, "stale Insert filter")
  vim.keymap.del("i", "<F9>")
  local notification
  vim.notify = function(message)
    notification = message
  end
  send("\r")
  wait_for(function()
    return notification and notification:find("Mapping changed", 1, true)
  end, "stale Insert rejection")
  assert(not picker.closed)
  send("\27")
  wait_for(function()
    return picker.closed and api.nvim_get_mode().mode == "i" and api.nvim_get_current_win() == win
  end, "cancel stale Insert picker")
  -- Disposal must cancel the pending restore, even for an Insert origin.
  picker = open()
  tools.dispose()
  wait_for(function()
    return picker.closed and api.nvim_get_mode().mode == "n" and api.nvim_get_current_win() == win
  end, "dispose Insert picker")
  assert(hits == 1 and global_hits == 0 and expr_hits == 1 and plug_hits == 1)
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
              "PASS Insert picker PTY: Ctrl+/, rendered search, local overrides, callback/expression/RHS/Plug replay, cancel at start/middle/EOL/empty/UTF-8, stale rejection and disposal",
            }
          or vim.split(tostring(err) .. "\nStep: " .. step .. "\n" .. debug.traceback(thread), "\n", { plain = true }),
        directory .. "/result"
      )
      vim.cmd(ok and "qa!" or "cquit 1")
    end
  end)
)
