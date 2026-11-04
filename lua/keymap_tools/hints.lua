local api = vim.api
local keys = require("keymap_tools.keys")
local maps = require("keymap_tools.maps")
local view = require("keymap_tools.view")
local catalog = require("keymap_tools.catalog")
local providers = require("keymap_tools.providers")
local M = { triggers = {}, suspended = false }
local config

local function owned(trigger)
  if not api.nvim_buf_is_valid(trigger.buf) then
    return false
  end
  for _, map in ipairs(api.nvim_buf_get_keymap(trigger.buf, trigger.mode)) do
    if map.callback == trigger.callback then
      return true
    end
  end
  return false
end

function M.detach()
  for _, trigger in ipairs(M.triggers) do
    if owned(trigger) then
      pcall(vim.keymap.del, trigger.mode, trigger.lhs, { buffer = trigger.buf })
    end
    maps.internal[trigger.callback] = nil
  end
  M.triggers = {}
end

function M.refresh()
  if not config or M.session or M.suspended then
    return
  end
  M.detach()
  local buf = api.nvim_get_current_buf()
  if not config.enabled or vim.bo[buf].buftype ~= "" or vim.fn.reg_recording() ~= "" then
    return
  end
  local modes = vim.deepcopy(config.modes)
  if providers.enabled(config.providers, "registers") then
    vim.list_extend(modes, { "i", "c" })
  end
  for _, mode in ipairs(modes) do
    local items, seen = catalog.collect({ buf = buf, mode = mode }, config), {}
    local triggers = (mode == "i" or mode == "c") and {} or vim.deepcopy(config.triggers)
    for raw in pairs(providers.prefixes(mode, config.providers)) do
      triggers[#triggers + 1] = keys.label(raw)
    end
    for _, lhs in ipairs(triggers) do
      local raw = keys.raw(lhs)
      local matches, exact = maps.match(items, raw)
      if #raw > 0 and not seen[raw] and #matches > 0 and (not exact or exact.virtual) then
        seen[raw] = true
        local trigger = { buf = buf, mode = mode, lhs = keys.label(raw) }
        trigger.callback = function()
          M.show({ keys = lhs, mode = mode, automatic = true })
        end
        maps.internal[trigger.callback] = true
        vim.keymap.set(mode, trigger.lhs, trigger.callback, {
          buffer = buf,
          nowait = true,
          silent = true,
          desc = "keymap-tools prefix hint",
        })
        M.triggers[#M.triggers + 1] = trigger
      end
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
  local items, groups = catalog.collect(
    { buf = state.buf, mode = state.mode, operator = state.operator, global = opts.global, ["local"] = opts["local"] },
    config
  )
  local prefix = keys.raw(opts.keys or "")
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
      M.replay(exact and exact.execute or prefix, exact and exact.execute and nil or state.count, state.register)
      return
    end
    local elapsed = (vim.uv or vim.loop).hrtime() / 1e6 - started
    if exact and vim.o.timeout and elapsed >= vim.o.timeoutlen then
      M.replay(prefix, state.count, state.register)
      return
    end
    local size = vim.o.columns .. ":" .. vim.o.lines
    if elapsed >= (opts.automatic and config.delay or 0) and (changed or last_size ~= size) then
      view.show(
        maps.children(matches, prefix, groups),
        prefix,
        state.mode == "o" and ("o · " .. state.operator) or state.mode,
        config.win
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
  if M.session then
    return false
  end
  local mode = opts.mode or keys.mode()
  if not vim.tbl_contains({ "n", "x", "o", "i", "c" }, mode) then
    return false
  end
  local state = {
    buf = api.nvim_get_current_buf(),
    win = api.nvim_get_current_win(),
    mode = mode,
    count = mode == "n" and vim.v.count or 0,
    register = mode == "n" and vim.v.register or nil,
    operator = mode == "o" and vim.v.operator or nil,
  }
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
      M.suspended = false
      M.refresh()
    end,
  })
  api.nvim_create_autocmd("RecordingEnter", { group = group, callback = M.detach })
  api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      require("keymap_tools.metadata").clear(ev.buf)
    end,
  })
  api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = function()
      if
        not config.enabled
        or M.session
        or keys.mode() ~= "o"
        or not vim.tbl_contains(config.modes, "o")
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
  view.highlights()
  M.refresh()
end

return M
