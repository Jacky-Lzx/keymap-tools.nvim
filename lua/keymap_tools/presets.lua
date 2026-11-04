-- Descriptions only: every action is still interpreted by Neovim itself.
local keys = require("keymap_tools.keys")
local M = {}
local motions = {
  w = "Next word",
  W = "Next WORD",
  b = "Previous word",
  B = "Previous WORD",
  e = "End of word",
  E = "End of WORD",
  ge = "Previous end of word",
  h = "Left",
  j = "Down",
  k = "Up",
  l = "Right",
  ["0"] = "Start of line",
  ["^"] = "First nonblank character",
  ["$"] = "End of line",
  gg = "First line",
  G = "Last line",
  ["%"] = "Matching bracket",
  ["{"] = "Previous paragraph",
  ["}"] = "Next paragraph",
  f = "Find next character",
  F = "Find previous character",
  t = "Before next character",
  T = "After previous character",
  ["/"] = "Search forward",
  ["?"] = "Search backward",
  n = "Next search match",
  N = "Previous search match",
}
local windows = {
  h = "Focus left window",
  j = "Focus lower window",
  k = "Focus upper window",
  l = "Focus right window",
  w = "Next window",
  p = "Previous window",
  s = "Split horizontally",
  v = "Split vertically",
  q = "Close window",
  o = "Keep only this window",
  ["="] = "Equalize window sizes",
  ["+"] = "Increase height",
  ["-"] = "Decrease height",
  [">"] = "Increase width",
  ["<"] = "Decrease width",
  H = "Move window left",
  J = "Move window down",
  K = "Move window up",
  L = "Move window right",
  T = "Move to a new tab",
}
local folds = {
  a = "Toggle fold",
  A = "Toggle nested folds",
  c = "Close fold",
  C = "Close nested folds",
  o = "Open fold",
  O = "Open nested folds",
  R = "Open all folds",
  M = "Close all folds",
  r = "Reduce folding",
  m = "Increase folding",
  d = "Delete fold",
  E = "Delete all folds",
  z = "Center cursor line",
  t = "Cursor line at top",
  b = "Cursor line at bottom",
  ["="] = "Spelling suggestions",
  g = "Accept word spelling",
  w = "Mark word misspelled",
}
local navigation = {
  gt = "Next tab",
  gT = "Previous tab",
  gf = "Open file under cursor",
  gi = "Resume last insertion",
  gv = "Restore Visual selection",
  gU = "Make uppercase",
  gu = "Make lowercase",
  ["g~"] = "Toggle case",
  gq = "Format text",
  gw = "Format and retain cursor",
  gc = "Comment text",
  ["[s"] = "Previous spelling error",
  ["]s"] = "Next spelling error",
  ["[("] = "Previous unmatched (",
  ["])"] = "Next unmatched )",
  ["[{"] = "Previous unmatched {",
  ["]}"] = "Next unmatched }",
}

function M.collect(mode, options, operator, projection)
  if options == false then
    return {}, {}
  end
  options = type(options) == "table" and options or {}
  local items, groups = {}, {}
  local function add(lhs, desc)
    local raw = keys.raw(lhs)
    if keys.matches_prefix(raw, projection and projection.prefixes) then
      items[#items + 1] = { keys = raw, lhs = lhs, desc = desc, mode = mode, virtual = true, map = {} }
    end
  end
  local function catalog(name, prefix, source)
    if options[name] ~= false then
      for lhs, desc in pairs(source) do
        add(prefix .. lhs, desc)
      end
    end
  end
  if mode == "n" or mode == "x" or mode == "o" then
    catalog("motions", "", motions)
    catalog("navigation", "", navigation)
  end
  if mode == "n" or mode == "x" then
    catalog("windows", "<C-w>", windows)
    catalog("folds", "z", folds)
    groups[keys.raw("<C-w>")] = "Windows"
  end
  if (mode == "o" or mode == "x") and options.textobjects ~= false then
    groups.a, groups.i = "Around text object", "Inside text object"
    for lhs, desc in pairs({
      w = "word",
      W = "WORD",
      s = "sentence",
      p = "paragraph",
      b = "parentheses",
      B = "braces",
      t = "tag",
      ["("] = "parentheses",
      [")"] = "parentheses",
      ["["] = "brackets",
      ["]"] = "brackets",
      ["{"] = "braces",
      ["}"] = "braces",
      ['"'] = "double quotes",
      ["'"] = "single quotes",
      ["`"] = "backticks",
      ["<"] = "angle brackets",
      [">"] = "angle brackets",
    }) do
      add("i" .. lhs, "Inside " .. desc)
      add("a" .. lhs, "Around " .. desc)
    end
  end
  if mode == "o" and operator and #operator > 0 then
    -- Repeating an operator selects complete lines (dd, yy, gUU, ...).
    add(operator:sub(-1), "Current line")
    add("v", "Force characterwise motion")
    add("V", "Force linewise motion")
    add("<C-v>", "Force blockwise motion")
  end
  return items, groups
end

return M
