local api = vim.api
local keys = require("keymap_tools.keys")
local maps = require("keymap_tools.maps")
local view = require("keymap_tools.view")
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
  for _, mode in ipairs(config.modes) do
    local items, seen = maps.collect({ buf = buf, mode = mode }), {}
    for _, lhs in ipairs(config.triggers) do
      local raw = keys.raw(lhs)
      local matches, exact = maps.match(items, raw)
      if #raw > 0 and not seen[raw] and #matches > 0 and not exact then
        seen[raw] = true
        local trigger = { buf = buf, mode = mode, lhs = lhs }
        trigger.callback = function()
          M.show({ keys = lhs, mode = mode, automatic = true })
        end
        maps.internal[trigger.callback] = true
        vim.keymap.set(mode, lhs, trigger.callback, {
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
-- SafeState/ModeChanged/BufEnter attach them again after execution.
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
  local items = maps.available({ buf = state.buf, mode = state.mode, global = opts.global, ["local"] = opts["local"] })
  local prefix = keys.raw(opts.keys or "")
  local history = {}
  local changed = true
  local started = (vim.uv or vim.loop).hrtime() / 1e6
  local last_size
  while M.session == state do
    if not api.nvim_win_is_valid(state.win) or api.nvim_get_current_win() ~= state.win then
      return
    end
    local matches, exact = maps.match(items, prefix)
    if #matches == 0 or (exact and (#matches == 1 or exact.map.nowait == 1)) then
      M.replay(prefix, state.count, state.register)
      return
    end
    local elapsed = (vim.uv or vim.loop).hrtime() / 1e6 - started
    if exact and vim.o.timeout and elapsed >= vim.o.timeoutlen then
      M.replay(prefix, state.count, state.register)
      return
    end
    local size = vim.o.columns .. ":" .. vim.o.lines
    if elapsed >= (opts.automatic and config.delay or 0) and (changed or last_size ~= size) then
      view.show(maps.children(matches, prefix, config.groups), prefix, state.mode, config.win)
      changed, last_size = false, size
    end
    local char = vim.fn.getcharstr(0)
    if char == "" then
      -- Process redraw, timers and resize while retaining ownership of the input.
      vim.wait(10, function()
        return M.session ~= state
      end, 10)
    elseif char == keys.raw("<Esc>") or char == keys.raw("<C-c>") then
      if state.mode == "x" then
        api.nvim_feedkeys(keys.raw("<Esc>"), "n", false)
      end
      return
    elseif char == keys.raw("<BS>") and #history > 0 then
      prefix = table.remove(history)
      changed = true
      started = (vim.uv or vim.loop).hrtime() / 1e6
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
  if mode ~= "n" and mode ~= "x" then
    return false
  end
  local state = {
    buf = api.nvim_get_current_buf(),
    win = api.nvim_get_current_win(),
    mode = mode,
    count = mode == "n" and vim.v.count or 0,
    register = mode == "n" and vim.v.register or nil,
  }
  M.session = state
  local ok, err = pcall(run, state, opts)
  M.hide()
  if not ok and not tostring(err):match("[Ii]nterrupt") then
    vim.notify("keymap-tools: " .. tostring(err), vim.log.levels.ERROR)
  end
  return ok
end

function M.setup(opts)
  M.hide()
  M.detach()
  config = opts
  config.groups = vim.deepcopy(opts.groups)
  for lhs, desc in pairs(opts.groups) do
    config.groups[keys.raw(lhs)] = desc
  end
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
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = view.highlights })
  view.highlights()
  M.refresh()
end

return M
