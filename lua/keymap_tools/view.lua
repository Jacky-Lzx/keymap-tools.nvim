local keys = require("keymap_tools.keys")
local icons = require("keymap_tools.icons")
local display = require("keymap_tools.display")
local M = {}
local ns = vim.api.nvim_create_namespace("keymap_tools.view")

local key_label, clip = keys.display, display.clip

local function footer_padding(border, width)
  local char, hl = "─", "KeymapToolsBorder"
  if type(border) == "table" and #border > 0 then
    local edge = border[5 % #border + 1]
    char = type(edge) == "table" and edge[1] or edge
    hl = type(edge) == "table" and edge[2] or hl
    char = char ~= "" and char or " "
  elseif border == "double" then
    char = "═"
  elseif border == "solid" or border == "shadow" then
    char = " "
  end
  return { string.rep(char, width), hl }
end

local function owned_buffer(buf, tick)
  return buf
    and vim.api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buftype == "nofile"
    and vim.bo[buf].filetype == "keymap-tools"
    and vim.api.nvim_buf_get_changedtick(buf) == tick
end

function M.hide()
  local win, buf, tick = M.win, M.buf, M.tick
  M.win, M.buf, M.tick = nil, nil, nil
  local owned = owned_buffer(buf, tick)
  if owned and win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
    vim.api.nvim_win_close(win, true)
  end
  if owned and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  M.prefix, M.offset, M.frame = nil, 0, nil
  local showkeys = package.loaded["keymap_tools.showkeys"]
  if showkeys then
    showkeys.redraw()
  end
end

function M.highlights()
  icons.highlights()
end

function M.redraw()
  if M.win and vim.api.nvim_win_is_valid(M.win) and M.frame then
    local frame = M.frame
    M.show(frame.children, frame.prefix, frame.mode, frame.config)
  end
end

function M.show(children, prefix, mode, config)
  if
    M.buf
    and (
      not owned_buffer(M.buf, M.tick)
      or M.win and vim.api.nvim_win_is_valid(M.win) and vim.api.nvim_win_get_buf(M.win) ~= M.buf
    )
  then
    M.hide()
  end
  if #children == 0 then
    M.hide()
    return
  end
  local bottom = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
  local width = math.max(1, math.min(config.width, vim.o.columns - 4))
  local gap = 3
  local columns = config.columns or 2
  -- Each column needs enough room for a key and a useful description.
  if columns == 2 and width < 2 * 24 + gap then
    columns = 1
  end
  local column_width = math.floor((width - gap * (columns - 1)) / columns)
  local height = math.max(1, math.min(math.ceil(#children / columns), config.height, bottom - 3))
  local bordered = config.border ~= "none" and config.border ~= ""
  local overflow = #children > height * columns
  local footer = overflow and not bordered and height > 1
  local rows = height - (footer and 1 or 0)
  local page = rows * columns
  M.offset = M.prefix == prefix and (M.offset or 0) or 0
  M.offset = math.min(M.offset, math.floor((#children - 1) / page) * page)
  M.prefix = prefix
  local position = ("%d-%d/%d"):format(M.offset + 1, math.min(#children, M.offset + page), #children)
  M.frame = {
    children = children,
    prefix = prefix,
    mode = mode,
    config = config,
    page = page,
    columns = columns,
    column_width = column_width,
    rows = rows,
    gap = gap,
  }
  local key_width, icon_width, decorations = 1, 0, {}
  for i, child in ipairs(children) do
    local label = key_label(child.key)
    local icon, hl = icons.resolve(child)
    decorations[i] = { label = label, icon = icon, icon_hl = hl }
    key_width = math.max(key_width, vim.fn.strdisplaywidth(label))
    icon_width = math.max(icon_width, vim.fn.strdisplaywidth(icon))
  end
  key_width = math.min(key_width, math.max(1, math.floor(column_width / 3)))
  local lines, spans = {}, {}
  for row = 1, rows do
    local line = ""
    for column = 1, columns do
      local index = M.offset + (column - 1) * rows + row
      local child = children[index]
      local cell = ""
      if child then
        local ranges
        cell, ranges = display.row(
          child,
          vim.tbl_extend("force", {}, decorations[index], {
            key_width = key_width,
            icon_width = icon_width,
            width = column_width,
            padding = " ",
          })
        )
        for _, range in ipairs(ranges) do
          spans[#spans + 1] = { row = row - 1, start = #line + range[1], finish = #line + range[2], hl = range.hl }
        end
      end
      line = line .. cell
      if column < columns then
        line = line .. string.rep(" ", column_width - vim.fn.strdisplaywidth(cell) + gap)
      end
    end
    lines[row] = line
  end
  if footer then
    lines[height] = clip(" " .. position .. "  Ctrl+d / Ctrl+u", width)
    spans[#spans + 1] = { row = height - 1, start = 0, finish = #lines[height], hl = "KeymapToolsGroup" }
  end
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    M.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M.buf].bufhidden = "wipe"
    vim.bo[M.buf].filetype = "keymap-tools"
  end
  vim.bo[M.buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  M.tick = vim.api.nvim_buf_get_changedtick(M.buf)
  vim.bo[M.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(M.buf, ns, 0, -1)
  for _, span in ipairs(spans) do
    vim.api.nvim_buf_set_extmark(M.buf, ns, span.row, span.start, { end_col = span.finish, hl_group = span.hl })
  end
  local win_config = {
    relative = "editor",
    anchor = "SE",
    row = math.max(height + 2, bottom - 1),
    col = math.max(width + 2, vim.o.columns - 1),
    width = width,
    height = height,
    focusable = false,
    style = "minimal",
    border = config.border,
    title = "",
    footer = "",
    zindex = 60,
  }
  if bordered and overflow then
    local counter = clip(" " .. position .. " ", width)
    local controls = " Ctrl+d / Ctrl+u "
    local padding = width - vim.fn.strdisplaywidth(counter) - #controls
    win_config.footer = { { counter, "KeymapToolsGroup" } }
    win_config.footer_pos = "right"
    if padding >= 1 then
      win_config.footer = {
        { controls, "KeymapToolsGroup" },
        footer_padding(config.border, padding),
        { counter, "KeymapToolsGroup" },
      }
      win_config.footer_pos = "left"
    end
  end
  if width >= 16 and bordered then
    win_config.title = clip(" " .. mode .. " · " .. (prefix == "" and "Keymaps" or key_label(prefix)) .. " ", width)
    win_config.title_pos = "right"
  end
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_set_config(M.win, win_config)
  else
    M.win = vim.api.nvim_open_win(M.buf, false, win_config)
    vim.wo[M.win].winhighlight = "Normal:KeymapToolsNormal,FloatBorder:KeymapToolsBorder"
    vim.wo[M.win].wrap = false
  end
  local showkeys = package.loaded["keymap_tools.showkeys"]
  if showkeys then
    showkeys.redraw()
  end
  vim.cmd.redraw()
end

function M.scroll(direction)
  if not M.frame then
    return
  end
  local frame = M.frame
  M.offset = math.max(0, (M.offset or 0) + direction * frame.page)
  M.show(frame.children, frame.prefix, frame.mode, frame.config)
end

return M
