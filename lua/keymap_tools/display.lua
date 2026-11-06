local M = {}

function M.clip(text, width)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  if width <= 0 then
    return ""
  end
  local result = ""
  for _, char in ipairs(vim.fn.split(text, "\\zs")) do
    if vim.fn.strdisplaywidth(result .. char) > width - 1 then
      break
    end
    result = result .. char
  end
  return result .. "…"
end

-- Track bytes for highlights independently of terminal-cell padding.
function M.row(item, opts)
  local text, spans, cells = "", {}, 0
  local function append(value, hl)
    value = M.clip(value, opts.width - cells)
    if #value > 0 then
      if hl then
        spans[#spans + 1] = { #text, #text + #value, hl = hl }
      end
      text, cells = text .. value, cells + vim.fn.strdisplaywidth(value)
    end
  end
  append(opts.padding or "")
  local label = M.clip(opts.label, opts.key_width)
  append(label, "KeymapToolsKey")
  append(string.rep(" ", opts.key_width - vim.fn.strdisplaywidth(label)))
  append(" › ", "KeymapToolsSeparator")
  if opts.icon_width > 0 then
    append(opts.icon, opts.icon_hl)
    append(string.rep(" ", math.max(0, opts.icon_width - vim.fn.strdisplaywidth(opts.icon)) + 1))
  end
  if opts.scope then
    append(("%-6s  "):format(item.scope), "KeymapToolsMuted")
  end
  append((item.group and "+" or "") .. item.desc, item.group and "KeymapToolsGroup" or nil)
  return text, spans
end

return M
