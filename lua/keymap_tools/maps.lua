local keys = require("keymap_tools.keys")
local M = {}
local plug = keys.raw("<Plug>")

-- Trigger callbacks are private implementation details, never picker candidates.
M.internal = {}

function M.collect(opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  local mode, merged = opts.mode or keys.mode(), {}
  local function add(list, scope)
    for _, map in ipairs(list) do
      if not M.internal[map.callback] then
        local raw = keys.raw(map.lhs)
        if keys.matches_prefix(raw, opts.prefixes) and (opts.plugs or raw:sub(1, #plug) ~= plug) then
          merged[raw] = {
            lhs = map.lhs,
            keys = raw,
            mode = mode,
            scope = scope,
            desc = not opts.minimal and keys.description(map) or nil,
            map = not opts.minimal and map or nil,
            buf = buf,
          }
        end
      end
    end
  end
  if opts.scope ~= "buffer" then
    add(opts.native_maps and opts.native_maps.global or vim.api.nvim_get_keymap(mode), "global")
  end
  -- Local maps win even when their spelling differs (<Space> versus a literal space).
  if opts.scope ~= "global" then
    add(opts.native_maps and opts.native_maps.buffer or vim.api.nvim_buf_get_keymap(buf, mode), "buffer")
  end
  return vim.tbl_values(merged)
end

function M.same(a, b)
  if not b or a.scope ~= b.scope then
    return false
  end
  for _, field in ipairs({ "callback", "rhs", "expr", "noremap", "script", "sid", "nowait" }) do
    if a.map[field] ~= b.map[field] then
      return false
    end
  end
  return true
end

function M.match(items, prefix)
  local matches, exact = {}, nil
  for _, item in ipairs(items) do
    if item.keys:sub(1, #prefix) == prefix then
      matches[#matches + 1] = item
      if item.keys == prefix then
        exact = item
      end
    end
  end
  return matches, exact
end

function M.children(items, prefix, groups)
  local children = {}
  for _, item in ipairs(items) do
    local suffix = item.keys:sub(#prefix + 1)
    if item.keys:sub(1, #prefix) == prefix and suffix ~= "" and not item.hidden then
      local token = keys.tokens(suffix)[1]
      local child = children[token] or { key = token, count = 0 }
      children[token] = child
      child.count = child.count + 1
      if suffix == token then
        child.item = item
      end
    end
  end
  local result = {}
  for _, child in pairs(children) do
    local group = groups[prefix .. child.key]
    local metadata = type(group) == "table" and group or child.item
    child.desc = (type(group) == "table" and group.desc or group)
      or (child.item and child.item.desc)
      or ("%d mappings"):format(child.count)
    child.group = group ~= nil or child.count > (child.item and 1 or 0)
    child.icon = metadata and metadata.icon
    child.toggle = metadata and metadata.toggle
    result[#result + 1] = child
  end
  keys.sort(result, "key")
  return result
end

return M
