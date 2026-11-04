local keys = require("keymap_tools.keys")
local M = {}
local ns = vim.api.nvim_create_namespace("keymap_tools.view")

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
  local height = math.max(1, math.min(#children, config.height, bottom - 3))
  local key_width = 1
  for _, child in ipairs(children) do
    key_width = math.max(key_width, vim.fn.strdisplaywidth(keys.label(child.key)))
  end
  key_width = math.min(key_width, math.max(1, math.floor(width / 3)))
  local lines, spans = {}, {}
  for i = 1, height do
    local child = children[i]
    local label = clip(keys.label(child.key), key_width)
    local left = " " .. label .. string.rep(" ", key_width - vim.fn.strdisplaywidth(label)) .. "  "
    local desc = child.desc
    if i == height and #children > height then
      desc = ("… %d more; type a key to narrow"):format(#children - height + 1)
    end
    lines[i] = clip(left .. desc, width)
    spans[i] = { key_end = math.min(#lines[i], #left), group = child.group }
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
  for i, span in ipairs(spans) do
    vim.api.nvim_buf_set_extmark(M.buf, ns, i - 1, 0, { end_col = span.key_end, hl_group = "KeymapToolsKey" })
    if span.group and #lines[i] > span.key_end then
      vim.api.nvim_buf_set_extmark(
        M.buf,
        ns,
        i - 1,
        span.key_end,
        { end_col = #lines[i], hl_group = "KeymapToolsGroup" }
      )
    end
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
  if width >= 16 then
    win_config.title = clip(" " .. mode .. " · " .. (prefix == "" and "Keymaps" or keys.label(prefix)) .. " ", width)
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

return M
