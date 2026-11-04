local keys = require("keymap_tools.keys")
local context = require("keymap_tools.context")
local M = { revision = 0 }
local records, serial, listener, scheduled = {}, 0, nil, false
local Handle = {}
Handle.__index = Handle
local cleanup_installed = false

local function changed()
  M.revision = M.revision + 1
  if listener and not scheduled then
    scheduled = true
    vim.schedule(function()
      scheduled = false
      if listener then
        listener()
      end
    end)
  end
end

function M.on_change(callback)
  listener = callback
end

local function fields(value, allowed, name)
  assert(type(value) == "table", "keymap-tools: " .. name .. " must be a table")
  for field in pairs(value) do
    assert(allowed[field], "keymap-tools: unknown " .. name .. " field: " .. tostring(field))
  end
end

local function modes(value)
  value = value or { "n" }
  assert(vim.islist(value) and #value > 0, "keymap-tools: modes must be a nonempty list")
  local result, seen = {}, {}
  for _, mode in ipairs(value) do
    assert(type(mode) == "string" and mode:match("^[nxoisct]$"), "keymap-tools: invalid registration mode")
    if not seen[mode] then
      result[#result + 1], seen[mode] = mode, true
    end
  end
  return result
end

local function normalize(spec, fixed_buf)
  fields(spec, { buf = true, modes = true, priority = true, groups = true, hints = true, when = true }, "registration")
  local buf = spec.buf
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  if fixed_buf ~= nil then
    assert(buf == nil or buf == fixed_buf, "keymap-tools: replace() cannot change registration scope")
    buf = fixed_buf ~= false and fixed_buf or nil
  end
  assert(
    buf == nil or (type(buf) == "number" and buf > 0 and vim.api.nvim_buf_is_valid(buf)),
    "keymap-tools: invalid registration buffer"
  )
  local priority = spec.priority or 0
  assert(type(priority) == "number", "keymap-tools: priority must be a number")
  local default_modes, entries = modes(spec.modes), {}
  for _, kind in ipairs({ "groups", "hints" }) do
    local list = spec[kind] or {}
    assert(vim.islist(list), "keymap-tools: " .. kind .. " must be a list")
    for _, item in ipairs(list) do
      local group = kind == "groups"
      fields(
        item,
        group and { prefix = true, label = true, modes = true, when = true, hidden = true }
          or { keys = true, desc = true, modes = true, when = true, hidden = true },
        kind .. " entry"
      )
      local lhs, text = group and item.prefix or item.keys, group and item.label or item.desc
      assert(
        type(lhs) == "string" and #lhs > 0,
        "keymap-tools: entry requires nonempty " .. (group and "prefix" or "keys")
      )
      assert(type(text) == "string" or type(text) == "function", "keymap-tools: entry requires a label/description")
      for _, field in ipairs({ "when", "hidden" }) do
        assert(
          item[field] == nil or type(item[field]) == "boolean" or type(item[field]) == "function",
          "keymap-tools: invalid " .. field
        )
      end
      for _, mode in ipairs(item.modes and modes(item.modes) or default_modes) do
        entries[#entries + 1] = {
          kind = group and "group" or "hint",
          raw = keys.raw(lhs),
          text = text,
          mode = mode,
          when = item.when,
          hidden = item.hidden,
        }
      end
    end
  end
  assert(
    spec.when == nil or type(spec.when) == "boolean" or type(spec.when) == "function",
    "keymap-tools: invalid registration when"
  )
  return { buf = buf, priority = priority, entries = entries, when = spec.when }
end

function Handle:replace(spec)
  assert(records[self.id] == self, "keymap-tools: registration is no longer active")
  local data = normalize(spec, self.data.buf or false)
  serial = serial + 1
  self.data, self.serial = data, serial
  changed()
  return self
end

function Handle:dispose()
  if records[self.id] ~= self then
    return false
  end
  records[self.id] = nil
  changed()
  return true
end

function M.register(source, spec)
  assert(type(source) == "string" and source:match("%S"), "keymap-tools: source must be a nonempty string")
  local data = normalize(spec)
  if data.buf and not cleanup_installed then
    local group = vim.api.nvim_create_augroup("KeymapToolsRegistry", { clear = true })
    vim.api.nvim_create_autocmd("BufWipeout", {
      group = group,
      callback = function(ev)
        M.clear_buffer(ev.buf)
      end,
    })
    cleanup_installed = true
  end
  serial = serial + 1
  local id = source .. "\0" .. (data.buf or 0)
  local handle = setmetatable({ source = source, id = id, data = data, serial = serial }, Handle)
  records[id] = handle
  changed()
  return handle
end

function M.resolve(ctx, scope, errors)
  local matching = {}
  for _, handle in pairs(records) do
    local data = handle.data
    if
      (not data.buf or data.buf == ctx.buf)
      and (scope ~= "global" or not data.buf)
      and (scope ~= "buffer" or data.buf)
    then
      local enabled, valid = context.evaluate(data.when, ctx, errors, handle.source, "when")
      if valid and enabled ~= false then
        matching[#matching + 1] = handle
      end
    end
  end
  table.sort(matching, function(a, b)
    if (a.data.buf ~= nil) ~= (b.data.buf ~= nil) then
      return a.data.buf == nil
    end
    if a.data.priority ~= b.data.priority then
      return a.data.priority < b.data.priority
    end
    return a.serial < b.serial
  end)
  local result = { hint = {}, group = {} }
  for _, handle in ipairs(matching) do
    for _, entry in ipairs(handle.data.entries) do
      local enabled, valid = true, true
      if entry.mode == ctx.mode then
        enabled, valid = context.evaluate(entry.when, ctx, errors, handle.source, "when")
      end
      if entry.mode == ctx.mode and valid and enabled ~= false then
        local text =
          context.evaluate(entry.text, ctx, errors, handle.source, entry.kind == "group" and "label" or "desc")
        if type(text) == "string" then
          result[entry.kind][entry.raw] = {
            keys = entry.raw,
            kind = entry.kind,
            desc = text,
            source = handle.source,
            scope = handle.data.buf and "buffer" or "global",
            buf = handle.data.buf,
            hidden = context.evaluate(entry.hidden, ctx, errors, handle.source, "hidden") == true,
          }
        end
      end
    end
  end
  return result
end

function M.clear_buffer(buf)
  local any = false
  for id, handle in pairs(records) do
    if handle.data.buf == buf then
      records[id], any = nil, true
    end
  end
  if any then
    changed()
  end
end

return M
