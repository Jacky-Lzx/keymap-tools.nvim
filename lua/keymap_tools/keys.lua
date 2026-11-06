local M = {}
local raw_cache, raw_count = {}, 0

function M.raw(keys)
  local cached = raw_cache[keys]
  if cached then
    return cached
  end
  local expanded, leaders = keys:gsub("<[Ll][Ee][Aa][Dd][Ee][Rr]>", function()
    return vim.g.mapleader or "\\"
  end)
  local locals
  expanded, locals = expanded:gsub("<[Ll][Oo][Cc][Aa][Ll][Ll][Ee][Aa][Dd][Ee][Rr]>", function()
    return vim.g.maplocalleader or "\\"
  end)
  local raw = vim.api.nvim_replace_termcodes(expanded, true, true, true)
  -- Native lhs spellings and presets are stable; leader expressions deliberately
  -- stay live so changing either leader immediately affects registrations/queries.
  if leaders == 0 and locals == 0 then
    if raw_count >= 2048 then
      raw_cache, raw_count = {}, 0
    end
    raw_cache[keys], raw_count = raw, raw_count + 1
  end
  return raw
end

function M.label(raw)
  return vim.fn.keytrans(raw)
end

-- Presentation only: canonical labels and raw keycodes still drive queries/replay.
function M.display(raw)
  local labels = {
    Space = "␣",
    CR = "↵",
    NL = "↵",
    Tab = "⇥",
    BS = "⌫",
    Esc = "Esc",
    Up = "↑",
    Down = "↓",
    Left = "←",
    Right = "→",
    Del = "Del",
    PageUp = "Page↑",
    PageDown = "Page↓",
  }
  local modifiers = { C = "Ctrl", M = "Alt", A = "Alt", D = "⌘", S = "Shift" }
  return (
    M.label(raw):gsub("<([^>]+)>", function(token)
      local prefix = ""
      while token:match("^[CMADS]%-") do
        prefix = prefix .. modifiers[token:sub(1, 1)] .. "+"
        token = token:sub(3)
      end
      if prefix:find("Ctrl+", 1, true) and token:match("^%u$") then
        token = token:lower()
      end
      return prefix .. (labels[token] or token)
    end)
  )
end

function M.matches_prefix(raw, prefixes)
  if not prefixes then
    return true
  end
  for _, prefix in ipairs(prefixes) do
    if raw:sub(1, #prefix) == prefix then
      return true
    end
  end
  return false
end

-- Convert each key once, rather than crossing into Vimscript in the comparator.
function M.sort(items, field)
  field = field or "keys"
  local labels = {}
  for _, item in ipairs(items) do
    local raw = item[field]
    if labels[raw] == nil then
      labels[raw] = M.label(raw)
    end
  end
  table.sort(items, function(a, b)
    if a[field] == b[field] then
      return (a.kind or "") < (b.kind or "")
    end
    return labels[a[field]] < labels[b[field]]
  end)
end

-- Split keytrans notation, retaining UTF-8 characters and special-key tokens.
function M.tokens(raw)
  local text, result = M.label(raw), {}
  while #text > 0 do
    local token = text:match("^<[^>]+>") or vim.fn.strcharpart(text, 0, 1)
    result[#result + 1] = M.raw(token)
    text = text:sub(#token + 1)
  end
  return result
end

function M.mode()
  local mode = vim.api.nvim_get_mode().mode
  if mode == "v" or mode == "V" or mode == "\22" then
    return "x"
  elseif mode:sub(1, 2) == "no" then
    return "o"
  end
  return mode:sub(1, 1)
end

function M.description(map)
  local text = map.desc or map.rhs or (map.callback and "Lua callback") or ""
  text = text:gsub("[\r\n\t]", " "):gsub("<[Cc][Mm][Dd]>", ""):gsub("<[Cc][Rr]>", "")
  return text ~= "" and text or "<Nop>"
end

return M
