local api = vim.api
local keys = require("keymap_tools.keys")
local maps = require("keymap_tools.maps")
local view = require("keymap_tools.view")
local query = require("keymap_tools.query")
local registry = require("keymap_tools.registry")
local context = require("keymap_tools.context")
local providers = require("keymap_tools.providers")
local M = { triggers = {}, suspended = false }
local config
local pending

-- Read each buffer/mode once, and never delete a mapping another owner replaced.
local function installed(triggers)
  local snapshots = {}
  for _, trigger in ipairs(triggers) do
    if api.nvim_buf_is_valid(trigger.buf) then
      local buffer = snapshots[trigger.buf] or {}
      snapshots[trigger.buf] = buffer
      if not buffer[trigger.mode] then
        local callbacks = {}
        for _, map in ipairs(api.nvim_buf_get_keymap(trigger.buf, trigger.mode)) do
          callbacks[keys.raw(map.lhs)] = map.callback
        end
        buffer[trigger.mode] = callbacks
      end
    end
  end
  return snapshots
end

local function owned(trigger, snapshots)
  local buffer = snapshots[trigger.buf]
  return buffer and buffer[trigger.mode][trigger.raw] == trigger.callback
end

local function remove(trigger, snapshots)
  if owned(trigger, snapshots) then
    pcall(vim.keymap.del, trigger.mode, trigger.lhs, { buffer = trigger.buf })
  end
  maps.internal[trigger.callback] = nil
end

function M.detach()
  pending = nil
  local snapshots = installed(M.triggers)
  for _, trigger in ipairs(M.triggers) do
    remove(trigger, snapshots)
  end
  M.triggers = {}
end

function M.request_refresh()
  if pending then
    return
  end
  local request = {}
  pending = request
  vim.schedule(function()
    if pending == request then
      M.refresh()
    end
  end)
end

function M.refresh()
  pending = nil
  if not config or M.session or M.suspended then
    return
  end
  local buf = api.nvim_get_current_buf()
  if not config.hints.enabled or vim.bo[buf].buftype ~= "" or vim.fn.reg_recording() ~= "" then
    M.detach()
    return
  end
  local previous, snapshots = M.triggers, installed(M.triggers)
  local reusable, retained, desired = {}, {}, {}
  for _, trigger in ipairs(previous) do
    if trigger.buf == buf and owned(trigger, snapshots) then
      reusable[trigger.mode .. "\0" .. trigger.raw] = trigger
    end
  end
  local modes = { "n", "x", "o", "i", "c" }
  for _, mode in ipairs(modes) do
    local prefixes, seen = {}, {}
    local function add(raw)
      if #raw > 0 and not seen[raw] then
        prefixes[#prefixes + 1], seen[raw] = raw, true
      end
    end
    for _, trigger in ipairs(config.hints.triggers) do
      if vim.tbl_contains(trigger.modes, mode) then
        add(keys.raw(trigger.prefix))
      end
    end
    for raw in pairs(providers.prefixes(mode, config.providers)) do
      add(raw)
    end
    local eligible = #prefixes > 0 and query.triggers({ buf = buf, mode = mode }, config, prefixes) or {}
    for _, raw in ipairs(prefixes) do
      if eligible[raw] then
        desired[#desired + 1] = { buf = buf, mode = mode, lhs = keys.label(raw), raw = raw }
      end
    end
  end
  M.triggers = {}
  for _, candidate in ipairs(desired) do
    local id = candidate.mode .. "\0" .. candidate.raw
    local trigger = reusable[id]
    if trigger then
      retained[trigger] = true
    else
      trigger = candidate
      local lhs, mode = trigger.lhs, trigger.mode
      trigger.callback = function()
        M.show({ prefix = lhs, mode = mode, automatic = true })
      end
      maps.internal[trigger.callback] = true
      vim.keymap.set(mode, lhs, trigger.callback, {
        buffer = buf,
        nowait = true,
        silent = true,
        desc = "keymap-tools prefix hint",
      })
    end
    M.triggers[#M.triggers + 1] = trigger
  end
  for _, trigger in ipairs(previous) do
    if not retained[trigger] then
      remove(trigger, snapshots)
    end
  end
end

-- Keep triggers detached until Neovim has consumed the replayed mapping.
-- SafeState/BufEnter attach them again after execution.
function M.replay(raw, count, register)
  M.detach()
  M.suspended = true
  local prefix = ""
  if count and count > 0 then
    prefix = tostring(count)
  end
  if register and register ~= '"' then
    prefix = '"' .. register .. prefix
  end
  api.nvim_feedkeys(prefix .. raw, "mit", false)
end

function M.hide()
  M.session = nil
  view.hide()
end

local function run(state, opts)
  local items, groups = query.hints(vim.tbl_extend("force", {}, state, { scope = opts.scope }), config)
  local prefix = keys.raw(opts.prefix or "")
  local history = {}
  local expanded = {}
  local changed = true
  local started = (vim.uv or vim.loop).hrtime() / 1e6
  local last_size
  while M.session == state do
    if
      not api.nvim_win_is_valid(state.win)
      or api.nvim_get_current_win() ~= state.win
      or api.nvim_get_current_buf() ~= state.buf
      or keys.mode() ~= state.mode
    then
      return
    end
    local matches, exact = maps.match(items, prefix)
    if exact and exact.provider and not expanded[prefix] then
      expanded[prefix] = true
      local extra = providers.expand(prefix, state, config.providers) or {}
      if #extra > 0 then
        for i, item in ipairs(items) do
          if item == exact then
            table.remove(items, i)
            break
          end
        end
      end
      for _, item in ipairs(extra) do
        if not select(2, maps.match(items, item.keys)) then
          items[#items + 1] = item
        end
      end
      matches, exact = maps.match(items, prefix)
    end
    if #matches == 0 or (exact and (#matches == 1 or exact.map.nowait == 1)) then
      M.replay(
        exact and exact.execute or prefix,
        state.mode == "n" and not (exact and exact.execute) and state.count or 0,
        state.mode == "n" and state.register or nil
      )
      return
    end
    local elapsed = (vim.uv or vim.loop).hrtime() / 1e6 - started
    if exact and vim.o.timeout and elapsed >= vim.o.timeoutlen then
      M.replay(prefix, state.mode == "n" and state.count or 0, state.mode == "n" and state.register or nil)
      return
    end
    local size = vim.o.columns .. ":" .. vim.o.lines
    if elapsed >= (opts.automatic and config.hints.delay or 0) and (changed or last_size ~= size) then
      view.show(
        maps.children(matches, prefix, groups),
        prefix,
        state.mode == "o" and ("o · " .. state.operator) or state.mode,
        config.window
      )
      changed, last_size = false, size
    end
    local char = vim.fn.getcharstr(0)
    if char == "" then
      -- Process redraw, timers and resize while retaining ownership of the input.
      local _, reason = vim.wait(10, function()
        return M.session ~= state
      end, 10)
      if reason == -2 then
        if state.mode == "x" or state.mode == "o" then
          api.nvim_feedkeys(keys.raw("<Esc>"), "n", false)
        end
        return
      end
    elseif char == keys.raw("<Esc>") or char == keys.raw("<C-c>") then
      if state.mode == "x" or state.mode == "o" then
        api.nvim_feedkeys(keys.raw("<Esc>"), "n", false)
      end
      return
    elseif char == keys.raw("<BS>") and #history > 0 then
      prefix = table.remove(history)
      changed = true
      started = (vim.uv or vim.loop).hrtime() / 1e6
    elseif
      view.win
      and (char == keys.raw("<C-d>") or char == keys.raw("<C-u>"))
      and #maps.match(items, prefix .. char) == 0
    then
      view.scroll(char == keys.raw("<C-d>") and 1 or -1)
    else
      history[#history + 1] = prefix
      prefix = prefix .. char
      changed = true
      started = (vim.uv or vim.loop).hrtime() / 1e6
    end
  end
end

function M.show(opts)
  opts = opts or {}
  assert(
    opts.keys == nil and opts.global == nil and opts["local"] == nil,
    "keymap-tools: show() accepts prefix and scope"
  )
  if M.session then
    return false
  end
  local mode = opts.mode or keys.mode()
  if not vim.tbl_contains({ "n", "x", "o", "i", "c" }, mode) then
    return false
  end
  local state = context.resolve(opts)
  if state.win ~= api.nvim_get_current_win() or state.mode ~= keys.mode() then
    return false
  end
  M.session = state
  local ok, err = pcall(run, state, opts)
  M.hide()
  if not ok and (mode == "o" or mode == "x") then
    api.nvim_feedkeys(keys.raw("<Esc>"), "n", false)
  end
  if not ok and not tostring(err):match("[Ii]nterrupt") then
    vim.notify("keymap-tools: " .. tostring(err), vim.log.levels.ERROR)
  end
  return ok
end

function M.setup(opts)
  M.hide()
  M.detach()
  config = opts
  M.suspended = false
  local group = api.nvim_create_augroup("KeymapToolsHints", { clear = true })
  api.nvim_create_autocmd({ "SafeState", "BufEnter", "FileType", "LspAttach", "RecordingLeave" }, {
    group = group,
    callback = function()
      if M.session then
        return
      end
      if M.suspended then
        -- Replay has finished: restore triggers before the next input arrives.
        M.suspended = false
        M.refresh()
      else
        M.request_refresh()
      end
    end,
  })
  api.nvim_create_autocmd("RecordingEnter", { group = group, callback = M.detach })
  api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = function()
      if
        not config.hints.enabled
        or M.session
        or keys.mode() ~= "o"
        or not config.hints.operators
        or vim.fn.reg_recording() ~= ""
        or vim.fn.reg_executing() ~= ""
      then
        return
      end
      -- Keep rapid native input on Neovim's normal path. Only take ownership when
      -- an operator is actually waiting for a motion; replay leaves it pending.
      if vim.fn.getcharstr(1) == "" then
        M.show({ mode = "o", automatic = true })
      end
    end,
  })
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = view.highlights })
  registry.on_change(M.request_refresh)
  view.highlights()
  M.refresh()
end

return M
