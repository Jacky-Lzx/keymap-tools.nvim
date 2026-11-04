vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:prepend(vim.env.SELECTION_TOOLS_DIR or vim.fn.getcwd() .. "/../selection-tools.nvim")
vim.o.swapfile = false
vim.o.timeoutlen = 250
vim.o.ttimeoutlen = 30
vim.g.mapleader = " "
local tools = require("keymap_tools")
local view = require("keymap_tools.view")
local keys = require("keymap_tools.keys")
local directory = assert(vim.env.KEYMAP_TOOLS_TEST_DIR)
local last_notification
local notify = vim.notify
vim.notify = function(message, ...)
  last_notification = message
  return notify(message, ...)
end
local origin = vim.api.nvim_get_current_win()
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "first", "second", "third", "fourth", "fifth" })
local hits, global_hits, expr_hits, plug_hits, visual_hits = 0, 0, 0, 0, 0
local count
local function local_action()
  assert(vim.api.nvim_get_current_win() == origin and vim.api.nvim_get_current_buf() == buf)
  assert(vim.api.nvim_get_mode().mode == "n", "Normal mapping executed in wrong mode")
  hits = hits + 1
end
vim.keymap.set("n", "<leader>sa", function()
  global_hits = global_hits + 1
end, { desc = "Global action" })
vim.keymap.set("n", "<leader>sa", local_action, { buffer = true, desc = "Local action 中文" })
vim.keymap.set("n", "<leader>sb", function()
  expr_hits = expr_hits + 1
  return "<Ignore>"
end, { expr = true, desc = "Expression action" })
vim.keymap.set("n", "<Plug>(test-action)", function()
  plug_hits = plug_hits + 1
end)
vim.keymap.set("n", "<leader>sc", "<Plug>(test-action)", { remap = true, desc = "Remapped action" })
vim.keymap.set("n", "<leader>sj", function()
  count = vim.v.count
end, { desc = "Count action" })
vim.keymap.set("n", "<leader>sy", "yy", { desc = "Register action" })
vim.keymap.set("n", "gq", "<Nop>", { desc = "Custom g prefix" })
vim.keymap.set("n", "<leader><Space>", "<Nop>", { desc = "Space action" })
vim.keymap.set("x", "<leader>sv", function()
  assert(vim.api.nvim_get_current_win() == origin)
  assert(require("keymap_tools.keys").mode() == "x", "Visual mapping lost selection")
  assert(vim.fn.line("v") == 1 and vim.fn.line(".") == 2, "Visual range changed")
  visual_hits = visual_hits + 1
  vim.cmd.normal({ args = { keys.raw("<Esc>") }, bang = true })
end, { desc = "Visual action" })
require("selection_tools").setup({ item_icons = false, layout = { width = 0.7, height = 0.6 } })
local latest_picker
local select_items = require("selection_tools").select
require("selection_tools").select = function(...)
  latest_picker = select_items(...)
  return latest_picker
end
tools.setup({ defer = true, hints = { delay = 50 } })
tools.register("test", { groups = { { prefix = "<leader>s", label = "Search actions" } } })
vim.keymap.set({ "n", "x" }, "<leader>?", function()
  tools.pick()
end, { desc = "Choose buffer keymap" })
local stage, ticks, picker, finished = "start", 0, nil, false
local function mark(value)
  vim.fn.writefile({ value }, directory .. "/stage")
end
local function active()
  return latest_picker
end
local function screen(row, col, width)
  local text = ""
  for i = col, col + width - 1 do
    text = text .. vim.fn.screenstring(row, i)
  end
  return text
end
local function choose(query, next_stage)
  picker = active()
  if picker and vim.api.nvim_get_mode().mode == "i" then
    mark(query)
    stage = next_stage
  end
end
local timer = vim.uv.new_timer()
timer:start(
  20,
  20,
  vim.schedule_wrap(function()
    if finished then
      return
    end
    local ok, err = xpcall(function()
      ticks = ticks + 1
      assert(ticks < 700, "TUI timeout at " .. stage)
      if stage == "start" then
        mark("prefix")
        stage = "root"
      elseif stage == "root" and view.win then
        vim.cmd.redraw()
        local pos = vim.fn.win_screenpos(view.win)
        local cfg = vim.api.nvim_win_get_config(view.win)
        assert(pos[2] + cfg.width + 1 == vim.o.columns - 1 and pos[1] > 8, "hint is not in bottom-right")
        assert(view.frame.columns == 2, "default hint should use two columns")
        local visible = ""
        for row = 0, cfg.height - 1 do
          visible = visible .. screen(pos[1] + row + 1, pos[2] + 1, cfg.width)
        end
        assert(visible:find("Search actions", 1, true), "group missing from terminal")
        assert(visible:find("␣  Space action", 1, true), "Space glyph missing from terminal")
        assert(screen(pos[1], pos[2] + 1, cfg.width):find("n · ␣", 1, true), "Space glyph missing from title")
        mark("subgroup")
        stage = "nested"
      elseif stage == "nested" and view.buf then
        local lines = table.concat(vim.api.nvim_buf_get_lines(view.buf, 0, -1, false), "\n")
        if lines:find("Local action", 1, true) then
          mark("back")
          stage = "back"
        end
      elseif stage == "back" and view.buf then
        if table.concat(vim.api.nvim_buf_get_lines(view.buf, 0, -1, false), "\n"):find("Search actions", 1, true) then
          mark("resize")
          stage = "resized"
        end
      elseif stage == "resized" and vim.o.columns == 32 and view.win and vim.api.nvim_win_get_width(view.win) <= 28 then
        assert(view.frame.columns == 1, "narrow terminal should use one column")
        mark("escape")
        stage = "cancel_hint"
      elseif stage == "cancel_hint" and not view.win then
        assert(hits == 0)
        mark("fast")
        stage = "fast"
      elseif stage == "fast" and hits == 1 then
        assert(global_hits == 0)
        mark("count")
        stage = "count"
      elseif stage == "count" and count then
        assert(count == 3, "count lost in hint replay")
        mark("register")
        stage = "register"
      elseif stage == "register" and vim.fn.getreg("a") ~= "" then
        assert(vim.fn.getreg("a") == "first\n", "register lost")
        vim.api.nvim_win_set_cursor(origin, { 4, 0 })
        mark("builtin")
        stage = "builtin"
      elseif stage == "builtin" and vim.api.nvim_win_get_cursor(origin)[1] == 1 then
        mark("pick")
        stage = "pick_local"
      elseif stage == "pick_local" then
        choose("filter_local", "filtered_local")
      elseif stage == "filtered_local" and picker.query == "Local action" then
        assert(#picker.matches == 1)
        mark("confirm_local")
        stage = "executed_local"
      elseif stage == "executed_local" and hits == 2 then
        mark("pick_expr")
        stage = "pick_expr"
      elseif stage == "pick_expr" then
        choose("filter_expr", "filtered_expr")
      elseif stage == "filtered_expr" and picker.query == "Expression action" then
        mark("confirm_expr")
        stage = "executed_expr"
      elseif stage == "executed_expr" and expr_hits == 1 then
        mark("pick_plug")
        stage = "pick_plug"
      elseif stage == "pick_plug" then
        choose("filter_plug", "filtered_plug")
      elseif stage == "filtered_plug" and picker.query == "Remapped action" then
        mark("confirm_plug")
        stage = "executed_plug"
      elseif stage == "executed_plug" and plug_hits == 1 then
        mark("visual")
        stage = "pick_visual"
      elseif stage == "pick_visual" then
        choose("filter_visual", "filtered_visual")
      elseif stage == "filtered_visual" and picker.query == "Visual action" then
        mark("confirm_visual")
        stage = "executed_visual"
      elseif stage == "executed_visual" and visual_hits == 1 then
        vim.keymap.set("n", "<leader>sx", "<Nop>", { buffer = true, desc = "Stale action" })
        picker = tools.pick()
        stage = "stale_open"
      elseif stage == "stale_open" and picker and vim.api.nvim_get_mode().mode == "i" then
        mark("filter_stale")
        stage = "stale_filtered"
      elseif stage == "stale_filtered" and picker.query == "Stale action" then
        vim.keymap.del("n", "<leader>sx", { buffer = buf })
        mark("confirm_stale")
        stage = "stale_rejected"
      elseif stage == "stale_rejected" and last_notification and last_notification:find("Mapping changed", 1, true) then
        assert(not picker.closed, "stale mapping should be rejected")
        mark("cancel_picker")
        stage = "done"
      elseif stage == "done" and picker.closed then
        assert(vim.api.nvim_get_current_win() == origin)
        assert(hits == 2 and global_hits == 0 and expr_hits == 1 and plug_hits == 1 and visual_hits == 1)
        tools.setup({ hints = { enabled = false } })
        assert(#require("keymap_tools.hints").triggers == 0)
        finished = true
        timer:stop()
        timer:close()
        vim.fn.writefile({
          "PASS TUI prefix/group/backspace/resize/Escape, rapid input, counts/registers, builtin fallback, real selection-tools search/execute, expression/remap, Visual range and stale rejection",
        }, directory .. "/result")
        vim.cmd("qa!")
      end
    end, debug.traceback)
    if not ok then
      finished = true
      timer:stop()
      timer:close()
      vim.fn.writefile(vim.split(err, "\n", { plain = true }), directory .. "/result")
      vim.cmd("cquit 1")
    end
  end)
)
