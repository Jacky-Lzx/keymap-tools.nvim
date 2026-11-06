local keys = require("keymap_tools.keys")
local M = { revision = 0 }
local records, serial, listener, scheduled = {}, 0, nil, nil
local Handle = {}
Handle.__index = Handle
local cleanup_installed = false

local function changed()
  M.revision = M.revision + 1
  if listener and not scheduled then
    local request = { listener = listener }
    scheduled = request
    vim.schedule(function()
      if scheduled ~= request then
        return
      end
      scheduled = nil
      if listener == request.listener then
        listener.callback()
      end
    end)
  end
end

function M.on_change(callback)
  assert(callback == nil or type(callback) == "function", "registry listener must be a function")
  local entry = callback and { callback = callback } or nil
  listener, scheduled = entry, nil
  return function()
    if listener == entry then
      listener, scheduled = nil, nil
    end
  end
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
  fields(
    spec,
    { buf = true, modes = true, priority = true, groups = true, hints = true, toggles = true, when = true },
    "registration"
  )
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
  for _, kind in ipairs({ "groups", "hints", "toggles" }) do
    local list = spec[kind] or {}
    assert(vim.islist(list), "keymap-tools: " .. kind .. " must be a list")
    for _, item in ipairs(list) do
      local group = kind == "groups"
      local toggle = kind == "toggles"
      fields(
        item,
        group and { prefix = true, label = true, modes = true, when = true, hidden = true, icon = true }
          or toggle and { keys = true, name = true, get = true, modes = true, when = true, hidden = true, icon = true }
          or { keys = true, desc = true, modes = true, when = true, hidden = true, icon = true },
        kind .. " entry"
      )
      local lhs = group and item.prefix or item.keys
      local text = group and item.label or toggle and item.name or item.desc
      assert(
        type(lhs) == "string" and #lhs > 0,
        "keymap-tools: entry requires nonempty " .. (group and "prefix" or "keys")
      )
      assert(
        type(text) == "string" or type(text) == "function",
        "keymap-tools: entry requires a " .. (toggle and "name" or "label/description")
      )
      assert(not toggle or type(item.get) == "function", "keymap-tools: toggle requires a get function")
      if type(item.icon) == "table" then
        fields(item.icon, { icon = true, hl = true, ascii = true }, "icon")
        assert(type(item.icon.icon) == "string", "keymap-tools: icon table requires an icon string")
        assert(item.icon.hl == nil or type(item.icon.hl) == "string", "keymap-tools: invalid icon highlight")
        assert(
          item.icon.ascii == nil or type(item.icon.ascii) == "string" and not item.icon.ascii:find("[^ -~]"),
          "keymap-tools: icon ascii must be printable ASCII"
        )
      else
        assert(item.icon == nil or item.icon == false or type(item.icon) == "string", "keymap-tools: invalid icon")
      end
      local glyph = type(item.icon) == "table" and item.icon.icon or item.icon
      assert(type(glyph) ~= "string" or not glyph:find("[%c]"), "keymap-tools: icon must be a single line")
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
          get = toggle and item.get or nil,
          mode = mode,
          when = item.when,
          hidden = item.hidden,
          icon = vim.deepcopy(item.icon),
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

local function describe(entry, ctx, errors, source, projection)
  local context = require("keymap_tools.context")
  local field = entry.get and "name" or entry.kind == "group" and "label" or "desc"
  local text = context.evaluate(entry.text, ctx, errors, source, field)
  if type(text) ~= "string" or not entry.get or projection then
    return text
  end
  local state = context.evaluate(entry.get, ctx, errors, source, "get")
  if state ~= nil and type(state) ~= "boolean" then
    errors[#errors + 1] = { source = source, field = "get", message = "toggle get must return a boolean or nil" }
    state = nil
  end
  local action = "Toggle "
  if state ~= nil then
    action = state and "Disable " or "Enable "
  end
  return action .. text, { name = text, state = state }
end

function M.resolve(ctx, scope, errors, projection)
  local context = require("keymap_tools.context")
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
      if
        entry.mode == ctx.mode
        and (not projection or entry.kind ~= "group")
        and keys.matches_prefix(entry.raw, projection and projection.prefixes)
      then
        local enabled, valid = context.evaluate(entry.when, ctx, errors, handle.source, "when")
        if valid and enabled ~= false then
          local text, toggle = describe(entry, ctx, errors, handle.source, projection)
          if type(text) == "string" then
            result[entry.kind][entry.raw] = {
              keys = entry.raw,
              kind = entry.kind,
              desc = text,
              toggle = toggle,
              icon = vim.deepcopy(entry.icon),
              source = handle.source,
              scope = handle.data.buf and "buffer" or "global",
              buf = handle.data.buf,
              hidden = not projection and context.evaluate(entry.hidden, ctx, errors, handle.source, "hidden") == true,
            }
          end
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
