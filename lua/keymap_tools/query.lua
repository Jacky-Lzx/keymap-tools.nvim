local keys = require("keymap_tools.keys")
local maps = require("keymap_tools.maps")
local context = require("keymap_tools.context")
local registry = require("keymap_tools.registry")
local M = {}

-- One resolved model feeds public inspection, hint windows and executable pickers.
-- Raw keycodes and original map dictionaries remain private to the input engine.
function M.collect(opts, config)
  opts = opts or {}
  local ctx = context.resolve(opts)
  local scope = opts.scope or "effective"
  assert(vim.tbl_contains({ "effective", "global", "buffer" }, scope), "keymap-tools: invalid scope")
  local wanted = {}
  local kinds = opts.kinds or { "mapping", "hint", "group", "provider", "choice" }
  assert(vim.islist(kinds), "keymap-tools: kinds must be a list")
  for _, kind in ipairs(kinds) do
    assert(vim.tbl_contains({ "mapping", "hint", "group", "provider", "choice" }, kind), "keymap-tools: invalid kind")
    wanted[kind] = true
  end
  local merged, groups, errors = {}, {}, {}
  local projection = opts.trigger_prefixes and { prefixes = opts.trigger_prefixes } or nil
  if scope ~= "buffer" then
    local presets, labels = require("keymap_tools.presets").collect(ctx.mode, config.presets, ctx.operator, projection)
    for _, item in ipairs(presets) do
      item.kind, item.source, item.scope = "hint", "builtin:presets", "global"
      merged[item.keys] = item
    end
    if not projection then
      for raw, label in pairs(labels) do
        groups[raw] = { keys = raw, kind = "group", desc = label, source = "builtin:presets", scope = "global" }
      end
    end
    for raw, label in pairs(require("keymap_tools.providers").prefixes(ctx.mode, config.providers)) do
      if keys.matches_prefix(raw, opts.trigger_prefixes) then
        merged[raw] = {
          keys = raw,
          desc = label,
          kind = "provider",
          source = "builtin:providers",
          scope = "global",
          provider = true,
          virtual = true,
          map = {},
        }
      end
    end
  end
  for _, item in
    ipairs(maps.collect({
      buf = ctx.buf,
      mode = ctx.mode,
      scope = scope,
      plugs = opts.plugs,
      prefixes = opts.trigger_prefixes,
      minimal = projection ~= nil,
    }))
  do
    item.kind, item.source = "mapping", "neovim"
    merged[item.keys] = item
  end
  local registered = registry.resolve(ctx, scope, errors, projection)
  for raw, entry in pairs(registered.hint) do
    local item = merged[raw]
    if item then
      item.desc, item.hidden, item.metadata_source = entry.desc, entry.hidden, entry.source
    else
      entry.virtual, entry.map = true, {}
      merged[raw] = entry
    end
  end
  for raw, entry in pairs(registered.group) do
    groups[raw] = entry
  end
  for raw, group in pairs(groups) do
    if group.hidden then
      for candidate, item in pairs(merged) do
        if candidate:sub(1, #raw) == raw then
          item.hidden = true
        end
      end
      for candidate, child in pairs(groups) do
        if candidate:sub(1, #raw) == raw then
          child.hidden = true
        end
      end
    end
  end
  local raw_prefix = keys.raw(ctx.prefix)
  local seed = merged[raw_prefix]
  if opts.expand ~= false and seed and seed.provider then
    local choices = require("keymap_tools.providers").expand(raw_prefix, ctx, config.providers) or {}
    if #choices > 0 then
      merged[raw_prefix] = nil
    end
    for _, item in ipairs(choices) do
      if not merged[item.keys] then
        item.kind, item.source, item.scope, item.buf = "choice", seed.source, seed.scope, ctx.buf
        merged[item.keys] = item
      end
    end
  end
  local result, prefix = {}, opts.unfiltered and "" or raw_prefix
  for _, item in pairs(merged) do
    if wanted[item.kind] and (opts.include_hidden or not item.hidden) and item.keys:sub(1, #prefix) == prefix then
      result[#result + 1] = item
    end
  end
  if wanted.group then
    for raw, group in pairs(groups) do
      local descendants = false
      for candidate, item in pairs(merged) do
        if #candidate > #raw and candidate:sub(1, #raw) == raw and not item.hidden then
          descendants = true
          break
        end
      end
      if descendants and (opts.include_hidden or not group.hidden) and raw:sub(1, #prefix) == prefix then
        result[#result + 1] = group
      end
    end
  end
  if opts.sort ~= false then
    keys.sort(result)
  end
  return result, { context = ctx, errors = errors }
end

function M.list(opts)
  for field in pairs(opts or {}) do
    assert(
      vim.tbl_contains(
        { "buf", "win", "mode", "prefix", "scope", "kinds", "plugs", "include_hidden", "operator", "count", "register" },
        field
      ),
      "keymap-tools: unknown list field: " .. tostring(field)
    )
  end
  local items, info = M.collect(opts, require("keymap_tools.config").get())
  local result = {}
  for _, item in ipairs(items) do
    result[#result + 1] = {
      keys = keys.label(item.keys),
      kind = item.kind,
      source = item.source,
      metadata_source = item.metadata_source,
      scope = item.scope,
      buf = item.scope == "buffer" and item.buf or nil,
      mode = info.context.mode,
      desc = item.desc,
      hidden = item.hidden == true,
      executable = item.kind == "mapping",
    }
  end
  return result, info
end

function M.hints(ctx, config)
  local rows = M.collect(
    vim.tbl_extend("force", {}, ctx, { include_hidden = true, expand = false, unfiltered = true, sort = false }),
    config
  )
  local items, groups = {}, {}
  for _, row in ipairs(rows) do
    if row.kind == "group" then
      if not row.hidden then
        groups[row.keys] = row.desc
      end
    else
      items[#items + 1] = row
    end
  end
  return items, groups
end

-- Reuse query precedence/conditions without constructing unrelated display rows.
function M.triggers(ctx, config, prefixes)
  local rows = M.collect(
    vim.tbl_extend("force", {}, ctx, {
      trigger_prefixes = prefixes,
      include_hidden = true,
      expand = false,
      unfiltered = true,
      sort = false,
    }),
    config
  )
  local result = {}
  for _, prefix in ipairs(prefixes) do
    local matches, exact = maps.match(rows, prefix)
    result[prefix] = #prefix > 0 and #matches > 0 and (not exact or exact.virtual) or false
  end
  return result
end

return M
