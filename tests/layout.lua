vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local view = require("keymap_tools.view")
local config = require("keymap_tools.config")
local defaults = config.normalize({})
assert(defaults.window.columns == 2 and defaults.window.width == 80)
vim.o.columns, vim.o.lines = 120, 36
view.highlights()
local options = { width = 80, height = 3, columns = 2, border = "rounded" }
local children = {
  { key = "a", desc = "中文 é 界" },
  { key = "b", desc = "Second" },
  { key = "c", desc = "Third" },
  { key = "d", desc = "Right group 中文", group = true },
  { key = "e", desc = string.rep("Long description ", 10) },
}
view.show(children, "", "n", options)
local lines = api.nvim_buf_get_lines(view.buf, 0, -1, false)
assert(#lines == 3 and lines[1]:find(" a 中文", 1, true) == 1 and lines[2]:find(" b Second", 1, true) == 1)
local right = assert(lines[1]:find(" d Right", 1, true), "right column is missing")
assert(vim.fn.strdisplaywidth(lines[1]:sub(1, right - 1)) == 41, "wide/combining text shifted the right column")
assert(lines[2]:find(" e Long", 1, true), "columns should fill from top to bottom")
assert(not lines[3]:find("Long", 1, true), "odd final item duplicated into an empty cell")
for _, line in ipairs(lines) do
  assert(vim.fn.strdisplaywidth(line) <= 80)
end
local spans =
  api.nvim_buf_get_extmarks(view.buf, api.nvim_create_namespace("keymap_tools.view"), 0, -1, { details = true })
local highlighted = false
for _, span in ipairs(spans) do
  if span[2] == 0 and span[3] == right - 1 + 3 and span[4].hl_group == "KeymapToolsGroup" then
    highlighted = true
  end
end
assert(highlighted, "right-column group highlight used cell offsets as byte positions")

local many = {}
for i = 1, 15 do
  many[i] = { key = string.char(96 + i), desc = "item " .. i }
end
view.show(many, "page", "n", options)
local seen = {}
for page = 1, 3 do
  lines = api.nvim_buf_get_lines(view.buf, 0, -1, false)
  for row = 1, #lines do
    for _, cell in ipairs({ lines[row]:sub(1, 38), lines[row]:sub(42) }) do
      local key = cell:match("^ (.) ")
      if key then
        assert(not seen[key], "paging duplicated " .. key)
        seen[key] = true
      end
    end
  end
  if page < 3 then
    view.scroll(1)
  end
end
assert(vim.tbl_count(seen) == 15, "paging omitted candidates")
local cfg = api.nvim_win_get_config(view.win)
assert(cfg.footer_pos == "left" and cfg.footer[1][1] == " <C-d>/<C-u> ", "controls should start at bottom-left")
assert(cfg.footer[3][1] == " 13-15/15 ", "last-page count includes empty cells")
assert(vim.fn.strdisplaywidth(cfg.footer[1][1] .. cfg.footer[2][1] .. cfg.footer[3][1]) == 80)
assert(view.frame.page == 6 and #lines == 3, "border controls should free the last content row")
view.scroll(1)
assert(view.offset == 12, "scrolling beyond the last page changed its start")
view.scroll(-1)
assert(view.offset == 6)

vim.o.columns = 40
view.show(children, "", "n", options)
assert(view.frame.columns == 1 and api.nvim_win_get_width(view.win) <= 36)
vim.o.columns = 120
view.show(children, "", "n", vim.tbl_extend("force", options, { columns = 1 }))
assert(view.frame.columns == 1)
view.show(many, "tiny", "n", vim.tbl_extend("force", options, { height = 1 }))
assert(api.nvim_win_get_height(view.win) == 1 and view.frame.page == 2)
view.show({ { key = " ", desc = "Space action" }, { key = "a", desc = "Letter action" } }, " g", "n", options)
assert(api.nvim_win_get_config(view.win).footer == nil, "short lists should not have a page position")
lines = api.nvim_buf_get_lines(view.buf, 0, -1, false)
assert(lines[1]:find(" ␣ Space action", 1, true) == 1, "Space should use a compact visible glyph")
assert(api.nvim_win_get_config(view.win).title[1][1] == " n · ␣g ", "prefix should use the same Space glyph")
assert(require("keymap_tools.keys").label(" ") == "<Space>", "canonical key notation must remain replayable")
for _, border in ipairs({ "none", "", "double", { "+", "-", "+", "|" } }) do
  view.show(many, "border", "n", vim.tbl_extend("force", options, { border = border }))
  cfg = api.nvim_win_get_config(view.win)
  lines = api.nvim_buf_get_lines(view.buf, 0, -1, false)
  if border == "none" or border == "" then
    assert(cfg.footer == nil and view.frame.page == 4, "borderless hints should retain a content footer")
    assert(lines[3] == " 1-4/15  <C-d>/<C-u>")
  else
    assert(cfg.footer[2][1] == string.rep(border == "double" and "═" or "-", 59))
  end
end
view.show(many, "narrow", "n", vim.tbl_extend("force", options, { width = 16 }))
cfg = api.nvim_win_get_config(view.win)
assert(cfg.footer_pos == "right" and cfg.footer[1][1] == " 1-3/15 ", "narrow borders should keep the page position")
view.hide()
assert(not pcall(config.normalize, { window = { columns = 3 } }))
print(
  "PASS two-column ordering, Unicode alignment/highlights, complete paging, narrow fallback and single-column override"
)
