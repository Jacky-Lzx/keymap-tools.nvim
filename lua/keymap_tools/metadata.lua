local keys = require("keymap_tools.keys")
local M = { entries = {} }

local function value(item)
  if type(item) ~= "function" then
    return item
  end
  local ok, result = pcall(item)
  if ok then
    return result
  end
end

-- A small explicit spec API, shared by static descriptions and lazy integrations.
function M.add(spec, inherited)
  assert(type(spec) == "table", "keymap-tools: add() expects a spec table")
  local opts = vim.tbl_extend("force", {}, inherited or {})
  for _, field in ipairs({ "mode", "buffer", "group", "hidden", "cond" }) do
    if spec[field] ~= nil then
      opts[field] = spec[field]
    end
  end
  if type(spec[1]) == "string" then
    local modes = opts.mode or "n"
    modes = type(modes) == "table" and modes or { modes }
    local buf = opts.buffer
    if buf == true or buf == 0 then
      buf = vim.api.nvim_get_current_buf()
    end
    for _, mode in ipairs(modes) do
      for _, actual in ipairs(mode == "v" and { "x", "s" } or { mode }) do
        local raw = keys.raw(spec[1])
        M.entries[actual .. ":" .. (buf or 0) .. ":" .. raw] = {
          keys = raw,
          mode = actual,
          buf = buf,
          desc = spec.desc,
          group = opts.group,
          hidden = opts.hidden,
          cond = opts.cond,
        }
        if spec[2] ~= nil and value(opts.cond) ~= false then
          local map_opts = { buffer = buf, desc = type(spec.desc) == "string" and spec.desc or nil }
          for _, field in ipairs({ "expr", "remap", "silent", "nowait", "replace_keycodes" }) do
            map_opts[field] = spec[field]
          end
          vim.keymap.set(actual, spec[1], spec[2], map_opts)
        end
      end
    end
  else
    for _, child in ipairs(spec) do
      M.add(child, opts)
    end
  end
end

function M.get(buf, mode)
  local result = {}
  for _, entry in pairs(M.entries) do
    if entry.mode == mode and (not entry.buf or entry.buf == buf) and value(entry.cond) ~= false then
      local previous = result[entry.keys]
      if not previous or entry.buf then
        result[entry.keys] = vim.tbl_extend("force", {}, entry, {
          desc = value(entry.desc),
          group = value(entry.group),
          hidden = value(entry.hidden),
        })
      end
    end
  end
  return result
end

function M.clear(buf)
  for id, entry in pairs(M.entries) do
    if entry.buf == buf then
      M.entries[id] = nil
    end
  end
end

return M
