local maps = require("keymap_tools.maps")
local keys = require("keymap_tools.keys")
local metadata = require("keymap_tools.metadata")
local M = {}

function M.collect(opts, config)
  local result, groups = require("keymap_tools.presets").collect(opts.mode, config.presets, opts.operator)
  local merged = {}
  for _, item in ipairs(result) do
    merged[item.keys] = item
  end
  for raw, desc in pairs(require("keymap_tools.providers").prefixes(opts.mode, config.providers or {})) do
    merged[raw] = { keys = raw, lhs = keys.label(raw), desc = desc, provider = true, virtual = true, map = {} }
  end
  for _, item in ipairs(maps.available(opts)) do
    merged[item.keys] = item
  end
  for lhs, label in pairs(config.groups) do
    groups[keys.raw(lhs)] = type(label) == "function" and label() or label
  end
  for raw, entry in pairs(metadata.get(opts.buf, opts.mode)) do
    if entry.group then
      groups[raw] = entry.group
    end
    local item = merged[raw]
    if not item and entry.desc then
      item = { keys = raw, lhs = keys.label(raw), map = {}, virtual = true }
      merged[raw] = item
    end
    if item then
      item.desc = entry.desc or item.desc
      item.hidden = entry.hidden
    end
  end
  return vim.tbl_values(merged), groups
end

return M
