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
  vim.o.mouse = "a"
  local selection = require("selection_tools")
  if vim.env.KEYMAP_TOOLS_CONFIGURED ~= "1" then
    selection.setup({ item_icons = false })
    tools.setup({ hints = { delay = 20 } })
    vim.keymap.set({ "n", "i" }, "<C-/>", function()
      tools.pick()
    end)
    vim.keymap.set({ "n", "i" }, "<C-_>", function()
      tools.pick()
    end)
  end
  local editor = api.nvim_get_current_win()
  local global_hits, local_hits = 0, 0
  vim.keymap.set({ "n", "i" }, "<F10>", function()
    global_hits = global_hits + 1
  end, { desc = "Editor-only global test action" })
  local latest
  local select_items = selection.select
  selection.select = function(...)
    latest = select_items(...)
    return latest
  end
  -- Ordinary editor buffers still expose their global mappings.
  local ordinary = tools.pick()
  wait_for(function()
    return api.nvim_get_mode().mode == "i" and not ordinary.closed
  end, "ordinary editor keymap picker")
  assert(
    vim.iter(ordinary.matches):any(function(entry)
      return entry.item.scope == "global" and entry.item.keys == vim.keycode("<F10>")
    end),
    "Ordinary buffer lost its global mappings"
  )
  send("\27")
  wait_for(function()
    return ordinary.closed and api.nvim_get_current_win() == editor and api.nvim_get_mode().mode == "n"
  end, "return to ordinary editor")
  local chosen, cancels, source
  local items = {}
  for i = 1, 40 do
    items[i] = { key = tostring(i), text = ("entry %03d"):format(i) }
  end
  local function parent_open()
    source = selection.open({
      items = items,
      multi = true,
      prompt = "Parent results",
      layout = { width = 0.85, height = 0.85 },
      format_item = function(item)
        return item.text
      end,
      preview = { enabled = true },
      previewer = function(ctx)
        local lines = {}
        for i = 1, 100 do
          lines[i] = ctx.item.text .. " preview " .. i
        end
        ctx.set_lines(lines)
        return true
      end,
      keys = { preview_down = { "<C-d>" }, select_next = { "<Tab>" } },
      on_choice = function(item)
        if item then
          chosen = item
        else
          cancels = (cancels or 0) + 1
        end
      end,
    })
    local owner = source
    vim.keymap.set("i", "<F11>", function()
      assert(api.nvim_get_current_win() == owner.input_win and api.nvim_get_mode().mode == "i")
      local_hits = local_hits + 1
    end, { buffer = owner.input_buf, desc = "Picker-local test action" })
    wait_for(function()
      return api.nvim_get_mode().mode == "i" and source.preview.displayed_item
    end, "parent input")
    send("entry")
    wait_for(function()
      return source.query == "entry" and not source.matching
    end, "parent query")
    source:move(4)
    source:toggle()
    wait_for(function()
      return source.preview.displayed_item == source:current()
    end, "parent preview")
    source:scroll_preview(1, 10)
  end
  local function open()
    local previous = latest
    send("\27[47;5u")
    wait_for(function()
      return latest and latest ~= previous and not latest.closed and api.nvim_get_mode().mode == "i"
    end, "child input")
    assert(not source.closed and latest.parent == source and source.child == latest)
    assert(api.nvim_buf_is_valid(source.input_buf) and selection.current() == latest)
    for _, entry in ipairs(latest.matches) do
      assert(
        entry.item.scope == "buffer",
        "Nested search included a global editor/completion mapping: " .. entry.item.desc
      )
    end
    assert(api.nvim_win_get_config(latest.frame_win).zindex > api.nvim_win_get_config(source.list_win).zindex)
    return latest
  end
  local function restored(child)
    wait_for(function()
      return child.closed
        and not source.closed
        and selection.current() == source
        and api.nvim_get_current_win() == source.input_win
        and api.nvim_get_mode().mode == "i"
    end, "return to parent input")
  end
  local function choose(desc, key)
    local child = open()
    send(desc)
    wait_for(function()
      return child.query == desc and not child.matching and #child.matches > 0
    end, "child search " .. desc)
    local target
    for i, entry in ipairs(child.matches) do
      if entry.item.keys == vim.keycode(key) then
        target = i
      end
    end
    assert(target, "Mapping absent: " .. desc)
    child:move(target - child.index)
    vim.cmd.redraw()
    local pos, text = vim.fn.win_screenpos(child.list_win), ""
    for row = pos[1], pos[1] + api.nvim_win_get_height(child.list_win) - 1 do
      for col = pos[2], pos[2] + api.nvim_win_get_width(child.list_win) - 1 do
        text = text .. vim.fn.screenstring(row, col)
      end
    end
    assert(text:find(desc, 1, true), "Child action missing from terminal")
    send("\r")
    return child
  end
  parent_open()
  local input, list, current, marks, index =
    source.input_buf, source.list_buf, source:current(), vim.deepcopy(source.marks), source.index
  local top = api.nvim_win_call(source.preview_win, vim.fn.winsaveview).topline
  local cursor = api.nvim_win_get_cursor(source.input_win)
  local child = open()
  send("Scroll preview")
  wait_for(function()
    return child.query == "Scroll preview"
  end, "independent child query")
  send("\27")
  restored(child)
  assert(source.input_buf == input and source.list_buf == list and source.query == "entry")
  assert(source:current() == current and source.index == index and vim.deep_equal(source.marks, marks))
  assert(vim.deep_equal(api.nvim_win_get_cursor(source.input_win), cursor))
  assert(api.nvim_win_call(source.preview_win, vim.fn.winsaveview).topline == top)
  -- Explicit effective scope remains available for callers asking for all maps.
  child = tools.pick({ scope = "effective" })
  wait_for(function()
    return not child.closed and api.nvim_get_mode().mode == "i"
  end, "explicit effective scope")
  assert(
    vim.iter(child.matches):any(function(entry)
      return entry.item.scope == "global" and entry.item.keys == vim.keycode("<F10>")
    end),
    "Explicit effective scope lost global mappings"
  )
  send("\27")
  restored(child)
  child = choose("Picker-local test action", "<F11>")
  restored(child)
  wait_for(function()
    return local_hits == 1
  end, "custom input-local mapping")
  assert(global_hits == 0 and source.query == "entry")
  -- Resize both live layouts while the child owns focus.
  child = open()
  vim.fn.writefile({ "70" }, directory .. "/resize")
  send("")
  wait_for(function()
    return vim.o.columns == 70
  end, "terminal resize with child")
  assert(not source.closed and not child.closed and selection.current() == child)
  assert(api.nvim_win_get_config(child.frame_win).zindex > api.nvim_win_get_config(source.list_win).zindex)
  send("\27")
  restored(child)
  assert(source.query == "entry" and source:current() == current and vim.deep_equal(source.marks, marks))
  vim.fn.writefile({ "110" }, directory .. "/resize")
  send("")
  wait_for(function()
    return vim.o.columns == 110
  end, "restore terminal width")
  -- Ctrl+/ inside help returns to the parent; it never opens a third picker.
  for attempt = 1, 3 do
    child = open()
    send(attempt == 2 and "\31" or "\27[47;5u")
    restored(child)
  end
  child = choose("Next result", "<C-n>")
  restored(child)
  wait_for(function()
    return source.index == index + (source.opts.layout.reverse and -1 or 1)
  end, "execute parent navigation")
  assert(source.query == "entry" and source.marks[index])
  wait_for(function()
    return source.preview.displayed_item == source:current()
  end, "navigated preview")
  top = api.nvim_win_call(source.preview_win, vim.fn.winsaveview).topline
  child = choose("Scroll preview down", "<C-d>")
  restored(child)
  wait_for(function()
    return api.nvim_win_call(source.preview_win, vim.fn.winsaveview).topline > top
  end, "execute parent preview scroll")
  local expected = source:current()
  child = choose("Confirm selection", "<CR>")
  wait_for(function()
    return child.closed and source.closed and chosen == expected and api.nvim_get_current_win() == editor
  end, "confirm parent from help")
  assert(not cancels)
  parent_open()
  child = choose("Close picker", "<Esc>")
  wait_for(function()
    return child.closed and source.closed and cancels == 1
  end, "close parent from help")
  parent_open()
  child = open()
  send("\27[<0;2;2M\27[<0;2;2m")
  wait_for(function()
    return child.closed and source.closed and api.nvim_get_current_win() == editor and api.nvim_get_mode().mode == "n"
  end, "outside mouse cancels chain")
  parent_open()
  child = open()
  api.nvim_win_close(source.input_win, true)
  wait_for(function()
    return child.closed and source.closed and selection.current() == nil
  end, "parent destruction cancels child")
  -- Real file-source callbacks must open the parent's chosen file in the editor.
  local files = directory .. "/files"
  vim.fn.mkdir(files, "p")
  vim.fn.writefile({ "first file" }, files .. "/entry-one.txt")
  vim.fn.writefile({ "second file" }, files .. "/entry-two.txt")
  source = selection.files({ cwd = files, preview = { enabled = true } })
  wait_for(function()
    return api.nvim_get_mode().mode == "i" and not source.loading and #source.matches == 2
  end, "real file source")
  send("entry")
  wait_for(function()
    return source.query == "entry" and not source.matching
  end, "real file query")
  local first_file = source:current().file
  child = choose("Next result", "<C-n>")
  restored(child)
  wait_for(function()
    return source:current().file ~= first_file
  end, "navigate real files from help")
  local selected_file = source:current().file
  child = choose("Confirm selection", "<CR>")
  wait_for(function()
    return child.closed
      and source.closed
      and api.nvim_get_current_win() == editor
      and vim.uv.fs_realpath(api.nvim_buf_get_name(0)) == vim.uv.fs_realpath(selected_file)
  end, "open real file from help")
  parent_open()
  child = open()
  selection.dispose()
  wait_for(function()
    return child.closed and source.closed and api.nvim_get_current_win() == editor and api.nvim_get_mode().mode == "n"
  end, "dispose whole chain")
  if _G.config_test_errors then
    assert(#_G.config_test_errors == 0, table.concat(_G.config_test_errors, "\n"))
  end
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
              "PASS nested picker PTY: context-local defaults, explicit global inclusion, custom local replay, live parent state, rendered action search, Ctrl+/ toggle, parent navigation/preview/confirm/close, real file source, resize, outside mouse, parent destruction and disposal",
            }
          or vim.split(tostring(err) .. "\nStep: " .. step .. "\n" .. debug.traceback(thread), "\n", { plain = true }),
        vim.env.KEYMAP_TOOLS_RESULT or directory .. "/result"
      )
      vim.cmd(ok and "qa!" or "cquit 1")
    end
  end)
)
