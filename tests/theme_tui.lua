vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:prepend(vim.env.THEME_TOOLS_DIR or vim.fn.getcwd() .. "/../theme-tools.nvim")
vim.opt.runtimepath:prepend(vim.env.SELECTION_TOOLS_DIR or vim.fn.getcwd() .. "/../selection-tools.nvim")
local api, tools = vim.api, require("keymap_tools")
local directory = assert(vim.env.KEYMAP_TOOLS_TEST_DIR)
local serial, step = 0, "startup"
local function wait_for(fn, label)
  step = label
  for _ = 1, 200 do
    if fn() then
      return
    end
    coroutine.yield()
  end
  error("Timed out: " .. label)
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
local function screen(win)
  vim.cmd.redraw()
  local pos, lines = vim.fn.win_screenpos(win), {}
  local border = api.nvim_win_get_config(win).border
  local inset = border and #border > 0 and 1 or 0
  for row = 0, api.nvim_win_get_height(win) - 1 do
    local text = ""
    for col = pos[2] + inset, pos[2] + inset + api.nvim_win_get_width(win) - 1 do
      text = text .. vim.fn.screenstring(pos[1] + inset + row, col)
    end
    lines[#lines + 1] = text
  end
  return table.concat(lines, "\n")
end
local function check()
  tools.setup({
    hints = { enabled = false },
    presets = false,
    providers = { registers = false, marks = false, spelling = false },
  })
  local hits = 0
  vim.keymap.set("n", "q1", function()
    hits = 1
  end, { desc = "Find first" })
  vim.keymap.set("n", "q2", function()
    hits = 2
  end, { desc = "Find second" })
  tools.register(
    "theme-test",
    { hints = { { keys = "q2", desc = "Find second", icon = { icon = "★", ascii = "A" } } } }
  )
  tools.list({ mode = "n" })
  assert(not package.loaded.theme_tools and not package.loaded["theme_tools.icons"], "queries loaded theme-tools")
  local view = require("keymap_tools.view")
  view.highlights()
  local origin = api.nvim_get_current_win()
  local children = {
    { key = "a", desc = "Find files 中文" },
    { key = "b", desc = "Unclassified", icon = { icon = "★", ascii = "A" } },
    { key = "c", desc = "Group", group = true },
  }
  view.show(children, "live", "n", { width = 64, height = 2, columns = 2, border = "rounded" })
  assert(screen(view.win):find("", 1, true), "standalone fallback missing")
  assert(not package.loaded.theme_tools, "rendering loaded an optional theme manager")
  local themes = require("theme_tools")
  themes.setup({
    persist = false,
    catppuccin = false,
    dracula = false,
    default = "theme-tools-mocha",
    themes = { "theme-tools-mocha", "theme-tools-dracula", "morning" },
    icons = {
      persist = false,
      default = "ascii",
      overrides = { ui = {
        search = { icon = "⌕", ascii = "S", hl = "DiagnosticWarn" },
      } },
    },
  })
  local function has(text)
    return screen(view.win):find(text, 1, true)
  end
  wait_for(function()
    return has("S Find files") and has("A Unclassified")
  end, "late theme integration and ASCII")
  local icon, hl = require("keymap_tools.icons").resolve(children[1])
  assert(icon == "S" and hl == "DiagnosticWarn", "shared icon override/highlight ignored")
  assert(api.nvim_get_current_win() == origin, "hint redraw stole focus")
  local offset = view.offset
  themes.icons.set("none")
  wait_for(function()
    return has("a › Find files") and has("b › Unclassified")
  end, "hidden icons remove gutter")
  assert(view.offset == offset)
  themes.icons.setup({
    persist = false,
    default = "devicons",
    overrides = { ui = {
      search = { icon = "⌕", ascii = "S", hl = "DiagnosticWarn" },
    } },
  })
  wait_for(function()
    return has("⌕ Find files") and has("★ Unclassified")
  end, "glyph mode and overrides")
  local function foreground(group)
    return api.nvim_get_hl(0, { name = group, link = false }).fg
  end
  api.nvim_set_hl(0, "KeymapToolsKey", { fg = "#123456" })
  themes.refresh_palette()
  assert(foreground("KeymapToolsKey") == 0x123456, "palette refresh overwrote a public override")
  for _, name in ipairs({ "theme-tools-dracula", "morning", "theme-tools-mocha" }) do
    themes.set(name)
    local palette = themes.palette()
    wait_for(function()
      return foreground("KeymapToolsKey") == tonumber(palette.ui.accent:sub(2), 16)
    end, "palette " .. name)
    assert(foreground("KeymapToolsIconBlue") == tonumber(palette.palette.blue:sub(2), 16))
    assert(foreground("ThemeToolsIconBlue") == tonumber(palette.palette.blue:sub(2), 16))
    assert(has("⌕ Find files"), "theme change lost hint icons")
    assert(api.nvim_get_current_win() == origin)
  end
  local override = api.nvim_create_autocmd("ColorScheme", {
    pattern = "theme-tools-dracula",
    callback = function()
      api.nvim_set_hl(0, "KeymapToolsKey", { fg = "#123456" })
    end,
  })
  themes.set("theme-tools-dracula")
  require("theme_tools.palette").setup({ overrides = { palette = { blue = "#345678" }, ui = { accent = "#987654" } } })
  themes.refresh_palette()
  assert(foreground("KeymapToolsKey") == 0x123456, "palette replaced a ColorScheme override")
  assert(
    foreground("KeymapToolsIconBlue") == 0x345678 and foreground("ThemeToolsIconBlue") == 0x345678,
    "semantic icon colors ignored palette overrides"
  )
  api.nvim_del_autocmd(override)
  view.hide()
  local picker = tools.pick({ prefix = "q" })
  wait_for(function()
    return vim.api.nvim_get_mode().mode == "i"
  end, "picker Insert mode")
  send("Find")
  wait_for(function()
    return picker.query == "Find" and #picker.matches == 2 and not picker.matching
  end, "filtered picker")
  send("\14")
  wait_for(function()
    return picker:current().keys == "q2"
  end, "selected second mapping")
  local input = api.nvim_get_current_win()
  local cursor = api.nvim_win_get_cursor(input)
  themes.icons.set("none")
  wait_for(function()
    return not picker.matching and not screen(picker.list_win):find("★", 1, true)
  end, "live picker hides icons")
  assert(picker.query == "Find" and picker:current().keys == "q2", "icon refresh lost picker query/selection")
  assert(
    api.nvim_get_current_win() == input and vim.deep_equal(api.nvim_win_get_cursor(input), cursor),
    "refresh moved input focus/cursor"
  )
  themes.icons.set("ascii")
  wait_for(function()
    return not picker.matching and screen(picker.list_win):find("A", 1, true)
  end, "live picker ASCII")
  assert(picker.query == "Find" and picker:current().keys == "q2")
  themes.set("theme-tools-dracula")
  wait_for(function()
    return not picker.matching and screen(picker.list_win):find("Find second", 1, true)
  end, "live picker theme switch")
  assert(picker:current().keys == "q2")
  send("\r")
  wait_for(function()
    return picker.closed and hits == 2
  end, "original mapping executes after refresh")
  assert(
    not package.loaded["nvim-web-devicons"] and not package.loaded["mini.icons"],
    "semantic actions loaded an icon provider"
  )
  themes.icons.set("none") -- Closed pickers must have released their refresh state.
  assert(api.nvim_get_current_win() == origin)
end
local thread = coroutine.create(check)
local timer = vim.uv.new_timer()
timer:start(
  20,
  20,
  vim.schedule_wrap(function()
    if coroutine.status(thread) == "running" then
      return
    end
    local ok, err = coroutine.resume(thread)
    if not ok or coroutine.status(thread) == "dead" then
      timer:stop()
      timer:close()
      vim.fn.writefile(
        ok
            and {
              "PASS shared icon modes/overrides, late theme loading, live palette and picker focus/query/selection/execution",
            }
          or vim.split(tostring(err) .. "\nStep: " .. step .. "\n" .. debug.traceback(thread), "\n", { plain = true }),
        directory .. "/result"
      )
      vim.cmd(ok and "qa!" or "cquit 1")
    end
  end)
)
