local keys = require("keymap_tools.keys")
local M = {}
local ns = vim.api.nvim_create_namespace("keymap_tools.view")

local function key_label(raw)
  return (keys.label(raw):gsub("<Space>", "␣"))
end

local function clip(text, width)
  local result = ""
  for _, char in ipairs(vim.fn.split(text, "\\zs")) do
    if vim.fn.strdisplaywidth(result .. char) > width then
      break
    end
    result = result .. char
  end
  return result
end

function M.hide()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
  end
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    vim.api.nvim_buf_delete(M.buf, { force = true })
  end
  M.win, M.buf = nil, nil
  M.prefix, M.offset, M.frame = nil, 0, nil
end

function M.highlights()
  for name, link in pairs({ Normal = "NormalFloat", Border = "FloatBorder", Key = "Special", Group = "Title" }) do
    vim.api.nvim_set_hl(0, "KeymapTools" .. name, { default = true, link = link })
  end
end

function M.show(children, prefix, mode, config)
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
  local footer = #children > height * columns and height > 1
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
  local key_width = 1
  for _, child in ipairs(children) do
    key_width = math.max(key_width, vim.fn.strdisplaywidth(key_label(child.key)))
  end
  key_width = math.min(key_width, math.max(1, math.floor(column_width / 3)))
  local lines, spans = {}, {}
  for row = 1, rows do
    local line = ""
    for column = 1, columns do
      local child = children[M.offset + (column - 1) * rows + row]
      local cell, left = "", ""
      if child then
        local label = clip(key_label(child.key), key_width)
        left = " " .. label .. string.rep(" ", key_width - vim.fn.strdisplaywidth(label)) .. " "
        cell = clip(left .. child.desc, column_width)
        local key_end = math.min(#cell, #left)
        spans[#spans + 1] = { row = row - 1, start = #line, finish = #line + key_end, hl = "KeymapToolsKey" }
        if child.group and #cell > key_end then
          spans[#spans + 1] =
            { row = row - 1, start = #line + key_end, finish = #line + #cell, hl = "KeymapToolsGroup" }
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
    lines[height] = clip(bordered and " <C-d>/<C-u>" or (" " .. position .. "  <C-d>/<C-u>"), width)
    spans[#spans + 1] = { row = height - 1, start = 0, finish = #lines[height], hl = "KeymapToolsGroup" }
  end
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    M.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M.buf].bufhidden = "wipe"
    vim.bo[M.buf].filetype = "keymap-tools"
  end
  vim.bo[M.buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
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
    zindex = 60,
  }
  if bordered then
    win_config.footer = footer and { { clip(" " .. position .. " ", width), "KeymapToolsGroup" } } or ""
    win_config.footer_pos = "right"
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
