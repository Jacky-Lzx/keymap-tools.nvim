local M = {}

function M.raw(keys)
  keys = keys
    :gsub("<[Ll][Ee][Aa][Dd][Ee][Rr]>", function()
      return vim.g.mapleader or "\\"
    end)
    :gsub("<[Ll][Oo][Cc][Aa][Ll][Ll][Ee][Aa][Dd][Ee][Rr]>", function()
      return vim.g.maplocalleader or "\\"
    end)
  return vim.api.nvim_replace_termcodes(keys, true, true, true)
end

function M.label(raw)
  return vim.fn.keytrans(raw)
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
