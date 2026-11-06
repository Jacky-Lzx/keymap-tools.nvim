local api = vim.api
local uv = vim.uv or vim.loop
local keys = require("keymap_tools.keys")
local M = {}
local ns = api.nvim_create_namespace("keymap_tools.showkeys")
local enabled, config, timer, group, queued = false, nil, nil, nil, nil
local history, ignored, generation = {}, "", 0

local function owned_buffer(buf, tick)
  return buf
    and api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buftype == "nofile"
    and vim.bo[buf].filetype == "keymap-tools-showkeys"
    and api.nvim_buf_get_changedtick(buf) == tick
end

local function close_window()
  local win, buf, tick = M.win, M.buf, M.tick
  M.win, M.buf, M.tick = nil, nil, nil
  local owned = owned_buffer(buf, tick)
  if owned and win and api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then
    api.nvim_win_close(win, true)
  end
  if owned and api.nvim_buf_is_valid(buf) then
    api.nvim_buf_delete(buf, { force = true })
  end
end

local function clear()
  history = {}
  generation = generation + 1
  if timer then
    timer:stop()
  end
  close_window()
end

function M.highlights()
  api.nvim_set_hl(0, "KeymapToolsShowkeysActive", { default = true, link = "PmenuSel" })
  api.nvim_set_hl(0, "KeymapToolsShowkeysInactive", { default = true, link = "Visual" })
end

local function clip(text, width)
  local result = ""
  for _, char in ipairs(vim.fn.split(text, "\\zs")) do
    if vim.fn.strdisplaywidth(result .. char) > width then
      break
    end
    result = result .. char
  end
  return result
end

function M.redraw()
  if not enabled then
    return
  end
  if
    M.buf
    and (
      not owned_buffer(M.buf, M.tick)
      or M.win and vim.api.nvim_win_is_valid(M.win) and vim.api.nvim_win_get_buf(M.win) ~= M.buf
    )
  then
    close_window()
  end

  if #history == 0 then
    close_window()
    return
  end
  local border = config.winopts.border
  local edge = (border == "none" or border == "") and 0 or 2
  local available = math.max(1, vim.o.columns - edge - 2)
  local line, spans = "", {}
  -- Keep the newest key visible even when the terminal cannot fit the history.
  for i = #history, 1, -1 do
    local entry = history[i]
    local label = (entry.count > 1 and tostring(entry.count) .. " " or "") .. entry.label
    local cell = available >= 3 and (" " .. clip(label, available - 2) .. " ") or clip(label, available)
    if i < #history and vim.fn.strdisplaywidth(cell .. " " .. line) > available then
      break
    end
    line = cell .. (line ~= "" and " " or "") .. line
    table.insert(spans, 1, { length = #cell, active = i == #history })
  end
  local width = math.min(available, math.max(1, vim.fn.strdisplaywidth(line)))
  local bottom = math.max(1, vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0))
  local row = config.position:match("^top") and 1 or math.max(0, bottom - edge - 2)
  local col = 1
  if config.position:match("right$") then
    col = math.max(0, vim.o.columns - width - edge - 1)
  elseif config.position:match("center$") then
    col = math.max(0, math.floor((vim.o.columns - width - edge) / 2))
  end
  local view = package.loaded["keymap_tools.view"]
  if
    view
    and view.win
    and api.nvim_win_is_valid(view.win)
    and api.nvim_win_get_tabpage(view.win) == api.nvim_get_current_tabpage()
  then
    -- Screen positions remain zero until the first redraw of a new float.
    -- Hints use editor-relative SE coordinates, so use their config directly.
    local hint = api.nvim_win_get_config(view.win)
    local hint_edge = hint.border and #hint.border > 0 and 2 or 0
    local hint_width = hint.width + hint_edge
    local top = hint.row - hint.height - hint_edge
    local left = hint.col - hint_width
    if row + edge + 1 >= top and col < left + hint_width and col + width + edge > left then
      row = math.max(0, top - edge - 2)
    end
  end
  if not M.buf or not api.nvim_buf_is_valid(M.buf) then
    M.buf = api.nvim_create_buf(false, true)
    vim.bo[M.buf].bufhidden = "wipe"
    vim.bo[M.buf].filetype = "keymap-tools-showkeys"
  end
  vim.bo[M.buf].modifiable = true
  api.nvim_buf_set_lines(M.buf, 0, -1, false, { line })
  M.tick = api.nvim_buf_get_changedtick(M.buf)
  vim.bo[M.buf].modifiable = false
  api.nvim_buf_clear_namespace(M.buf, ns, 0, -1)
  local offset = 0
  for _, span in ipairs(spans) do
    api.nvim_buf_set_extmark(M.buf, ns, 0, offset, {
      end_col = offset + span.length,
      hl_group = "KeymapToolsShowkeys" .. (span.active and "Active" or "Inactive"),
    })
    offset = offset + span.length + 1
  end
  local opts = {
    relative = "editor",
    style = "minimal",
    focusable = false,
    row = row,
    col = col,
    width = width,
    height = 1,
    border = border,
    zindex = config.winopts.zindex,
  }
  if M.win and api.nvim_win_is_valid(M.win) then
    api.nvim_win_set_config(M.win, opts)
  else
    M.win = api.nvim_open_win(M.buf, false, opts)
  end
  vim.wo[M.win].winhighlight = config.winhl
  vim.wo[M.win].wrap = false
end

local function request_redraw()
  if queued then
    return
  end
  local request = {}
  queued = request
  vim.schedule(function()
    if queued == request then
      queued = nil
      M.redraw()
    end
  end)
end

local function format(raw)
  local label = keys.label(raw)
  if label:find("Mouse") or label:find("Scroll") or label:find("Drag") or label:find("Release") then
    return
  end
  if config.keyformat[label] ~= nil then
    return config.keyformat[label]
  end
  local inner = label:match("^<(.*)>$")
  if inner then
    if inner == "lt" then
      return "<"
    end
    local modifiers = {}
    while inner:match("^[CMSD]%-") do
      modifiers[#modifiers + 1] = config.keyformat["<" .. inner:sub(1, 1) .. ">"] or inner:sub(1, 1)
      inner = inner:sub(3)
    end
    modifiers[#modifiers + 1] = #modifiers > 0 and inner:lower() or inner
    return table.concat(modifiers, " + ")
  end
  return label
end

-- Hints replay the user's original input as typed keys to retain native undo
-- semantics. Suppress only that exact queued sequence in the screencast.
function M.ignore_replay(raw)
  if enabled then
    ignored = raw .. ignored
  end
end

local function on_key(_, typed)
  if not typed or typed == "" then
    return
  end
  if ignored ~= "" then
    local common = 0
    while common < math.min(#typed, #ignored) and typed:byte(common + 1) == ignored:byte(common + 1) do
      common = common + 1
    end
    ignored = ignored:sub(common + 1)
    typed = typed:sub(common + 1)
    if typed == "" then
      return
    end
    ignored = ""
  end
  local mode = api.nvim_get_mode().mode
  for _, excluded in ipairs(config.excluded_modes) do
    if mode == excluded or (#excluded == 1 and mode:sub(1, 1) == excluded) then
      history = {}
      generation = generation + 1
      timer:stop()
      request_redraw()
      return
    end
  end
  local changed = false
  for _, raw in ipairs(keys.tokens(typed)) do
    local label = format(raw)
    if label and label ~= "" then
      local last = history[#history]
      if config.show_count and last and last.raw == raw then
        last.count = last.count + 1
      else
        history[#history + 1] = { raw = raw, label = label, count = 1 }
        if #history > config.maxkeys then
          table.remove(history, 1)
        end
      end
      changed = true
    end
  end
  if changed then
    generation = generation + 1
    local current = generation
    timer:stop()
    timer:start(
      math.max(1, math.floor(config.timeout * 1000)),
      0,
      vim.schedule_wrap(function()
        if enabled and current == generation then
          clear()
        end
      end)
    )
    request_redraw()
  end
end

function M.is_enabled()
  return enabled
end

function M.disable()
  enabled, queued, ignored = false, nil, ""
  vim.on_key(nil, ns)
  if group then
    api.nvim_del_augroup_by_id(group)
    group = nil
  end
  clear()
  if timer then
    timer:close()
    timer = nil
  end
  return false
end

function M.enable()
  if enabled then
    return true
  end
  config = require("keymap_tools.config").get().showkeys
  enabled = true
  timer = assert(uv.new_timer())
  M.highlights()
  group = api.nvim_create_augroup("KeymapToolsShowkeys", { clear = true })
  api.nvim_create_autocmd("VimResized", { group = group, callback = request_redraw })
  api.nvim_create_autocmd("TabEnter", { group = group, callback = clear })
  api.nvim_create_autocmd("SafeState", {
    group = group,
    callback = function()
      ignored = ""
    end,
  })
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.highlights })
  api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.disable })
  vim.on_key(on_key, ns)
  return true
end

function M.toggle()
  if enabled then
    return M.disable()
  end
  return M.enable()
end

function M.setup(opts)
  M.disable()
  if opts.enabled then
    M.enable()
  end
end

function M.dispose()
  M.disable()
  config = nil
end

return M
