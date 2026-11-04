local keys = require("keymap_tools.keys")
local M = {}

function M.enabled(config, name)
  local option = config[name]
  return option ~= false and (type(option) ~= "table" or option.enabled ~= false)
end

function M.prefixes(mode, config)
  local result = {}
  if M.enabled(config, "registers") then
    if mode == "n" or mode == "x" then
      result['"'] = "Registers"
    elseif mode == "i" or mode == "c" then
      result[keys.raw("<C-r>")] = "Registers"
    end
  end
  if M.enabled(config, "marks") and (mode == "n" or mode == "x" or mode == "o") then
    for _, prefix in ipairs({ "'", "`", "g'", "g`" }) do
      result[prefix] = "Marks"
    end
  end
  if mode == "n" and M.enabled(config, "spelling") then
    result["z="] = "Spelling suggestions"
  end
  return result
end

local function entry(prefix, key, desc, execute)
  return { keys = prefix .. keys.raw(key), desc = desc, virtual = true, map = {}, execute = execute }
end

local function registers(prefix, config)
  local options = type(config.registers) == "table" and config.registers or {}
  local result = {}
  local labels = {
    ['"'] = "Unnamed",
    ["0"] = "Last yank",
    ["-"] = "Small delete",
    ["."] = "Last inserted text",
    [":"] = "Last command",
    ["%"] = "Current file",
    ["#"] = "Alternate file",
    ["/"] = "Last search",
  }
  for key in ('"0123456789abcdefghijklmnopqrstuvwxyz-:.%/#'):gmatch(".") do
    -- getreg(..., 1) reads the expression text without evaluating it.
    local ok, contents = pcall(vim.fn.getreg, key, 1)
    if ok and contents ~= "" then
      local preview = vim.fn.strtrans(vim.fn.strcharpart(contents, 0, 160)):gsub("%z", " ")
      result[#result + 1] = entry(prefix, key, (labels[key] and labels[key] .. " · " or "") .. preview)
    end
  end
  result[#result + 1] = entry(prefix, "_", "Black hole (discard text)")
  result[#result + 1] = entry(prefix, "=", "Expression register")
  for _, key in ipairs({ "+", "*" }) do
    local preview = "Clipboard (contents not read)"
    if options.clipboard then
      local ok, text = pcall(vim.fn.getreg, key, 1)
      if ok then
        preview = "Clipboard · " .. vim.fn.strtrans(vim.fn.strcharpart(text, 0, 160))
      end
    end
    result[#result + 1] = entry(prefix, key, preview)
  end
  return result
end

local function marks(prefix, state)
  local result, seen = {}, {}
  local list = vim.fn.getmarklist(state.buf)
  vim.list_extend(list, vim.fn.getmarklist())
  for _, mark in ipairs(list) do
    local key, pos = mark.mark:sub(2), mark.pos
    if pos[2] > 0 and not seen[key] then
      seen[key] = true
      local text = mark.file or ""
      if pos[1] > 0 and vim.api.nvim_buf_is_loaded(pos[1]) then
        text = vim.api.nvim_buf_get_lines(pos[1], pos[2] - 1, pos[2], false)[1] or text
      end
      result[#result + 1] = entry(prefix, key, ("%d:%d  %s"):format(pos[2], pos[3], text:gsub("[\r\n\t]", " ")))
    end
  end
  return result
end

local function spelling(prefix, state, config)
  -- A numeric prefix already asks Neovim to apply the numbered suggestion.
  if state.count > 0 then
    return {}
  end
  local option = type(config.spelling) == "table" and config.spelling or {}
  local word = vim.fn.expand("<cword>")
  if word == "" then
    return {}
  end
  local bad = vim.fn.spellbadword(word)
  local alphabet = "1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  local suggestions =
    vim.fn.spellsuggest(word, math.min(option.suggestions or 20, #alphabet), bad[2] == "caps" and 1 or 0)
  local result = {}
  for i, suggestion in ipairs(suggestions) do
    result[#result + 1] = entry(prefix, alphabet:sub(i, i), suggestion, keys.raw(tostring(i) .. "z="))
  end
  return result
end

function M.expand(prefix, state, config)
  if M.prefixes(state.mode, config)[prefix] == nil then
    return nil
  end
  if prefix == '"' or prefix == keys.raw("<C-r>") then
    return registers(prefix, config)
  end
  if prefix == "z=" then
    return spelling(prefix, state, config)
  end
  return marks(prefix, state)
end

return M
