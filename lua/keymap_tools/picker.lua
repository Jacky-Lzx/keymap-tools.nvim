local api = vim.api
local keys = require("keymap_tools.keys")
local maps = require("keymap_tools.maps")
local query = require("keymap_tools.query")
local context = require("keymap_tools.context")
local M = {}
local active
local generation = 0

function M.redraw()
  if not active or active.picker.closed then
    return
  end
  local picker = active.picker
  local entry = picker.matches[picker.index]
  local saved = { index = entry and entry.index, marks = vim.deepcopy(picker.marks), offset = picker.offset }
  active.rebuild()
  picker:set_items(active.items)
  picker:restore(saved)
end

function M.open(opts)
  opts = opts or {}
  assert(
    opts.picker == nil and opts.global == nil and opts["local"] == nil,
    "keymap-tools: pick() accepts scope and layout directly"
  )
  local ok, selection = pcall(require, "selection_tools")
  if not ok then
    vim.notify("keymap-tools: install selection-tools.nvim to use the keymap picker", vim.log.levels.WARN)
    return false
  end
  local origin = context.resolve(opts)
  if origin.win ~= api.nvim_get_current_win() then
    return false
  end
  if origin.mode ~= "n" and origin.mode ~= "x" and origin.mode ~= "i" then
    vim.notify("keymap-tools: open the picker from Normal, Visual or Insert mode", vim.log.levels.WARN)
    return false
  end
  if active and not active.picker.closed and active.picker:owns_window(origin.win) then
    active.picker:close()
    return true
  end
  local parent = selection.current(origin.win)
  local config = require("keymap_tools.config").get()
  local picker_opts = vim.tbl_deep_extend("force", {}, config.picker, opts)
  local scope = picker_opts.scope
  assert(vim.tbl_contains({ "buffer", "global", "effective" }, scope), "keymap-tools: invalid picker scope")
  local shown = { buffer = scope ~= "global", global = scope ~= "buffer" }
  local toggle_keys = { buffer = picker_opts.keys.toggle_buffer, global = picker_opts.keys.toggle_global }
  local icons = require("keymap_tools.icons")
  local display = require("keymap_tools.display")
  require("keymap_tools.view").highlights()
  local function collect(include_hidden)
    local items = query.collect(
      vim.tbl_extend(
        "force",
        {},
        origin,
        { scope = "effective", kinds = { "mapping" }, include_hidden = include_hidden }
      ),
      config
    )
    if opts.prefix then
      local prefix = keys.raw(opts.prefix)
      items = vim.tbl_filter(function(item)
        return item.keys:sub(1, #prefix) == prefix
      end, items)
    end
    local local_items, global_items = {}, {}
    for _, item in ipairs(items) do
      if shown[item.scope] then
        local target = item.scope == "buffer" and local_items or global_items
        target[#target + 1] = item
      end
    end
    items = vim.list_extend(local_items, global_items)
    return items
  end
  local function prompt()
    local labels = { "Keymaps" }
    for _, name in ipairs({ "buffer", "global" }) do
      local key = toggle_keys[name][1]
      labels[#labels + 1] = (key and keys.display(keys.raw(key)) .. " " or "")
        .. name
        .. ":"
        .. (shown[name] and "on" or "off")
    end
    return table.concat(labels, " · ") .. " · " .. origin.mode
  end
  -- Keep the window open even with both scopes hidden, so either can be enabled.
  local items = collect()
  local insert_cursor = origin.mode == "i" and api.nvim_win_get_cursor(origin.win) or nil
  M.dispose()
  local version = generation
  if keys.mode() == "x" then
    -- Save '< and '> before the picker changes focus and enters Insert mode.
    vim.cmd.normal({ args = { keys.raw("<Esc>") }, bang = true })
  end
  local function valid(item)
    if not api.nvim_win_is_valid(origin.win) or api.nvim_win_get_buf(origin.win) ~= origin.buf then
      return false, "Source window changed; reopen the keymap picker"
    end
    for _, current in ipairs(collect(true)) do
      if current.keys == item.keys and maps.same(item, current) then
        return true
      end
    end
    return false, "Mapping changed; reopen the keymap picker"
  end
  local formatted, decorations, icon_width = {}, {}, 0
  local function rebuild()
    formatted, decorations, icon_width = {}, {}, 0
    for _, item in ipairs(items) do
      local icon, hl = icons.resolve(item, config.icons)
      decorations[item] = { icon = icon, hl = hl }
      icon_width = math.max(icon_width, vim.fn.strdisplaywidth(icon))
    end
  end
  rebuild()
  local function presentation(item)
    if not formatted[item] then
      local decoration = decorations[item]
      local label = keys.display(item.keys)
      local text, spans = display.row(item, {
        label = label,
        key_width = math.max(18, vim.fn.strdisplaywidth(label)),
        icon = decoration.icon,
        icon_hl = decoration.hl,
        icon_width = icon_width,
        width = math.huge,
        scope = true,
      })
      formatted[item] = { text = text, spans = spans }
    end
    return formatted[item]
  end
  local function toggle_scope(picker, name)
    if picker.closed then
      return
    end
    local selected = picker:current()
    local offset = picker.offset
    shown[name] = not shown[name]
    items = collect()
    rebuild()
    picker.opts.prompt = prompt()
    if active and active.picker == picker then
      active.items = items
    end
    picker:set_items(items)
    if selected then
      for index, item in ipairs(items) do
        if item.keys == selected.keys and item.scope == selected.scope then
          picker:restore({ index = index, marks = {}, offset = offset })
          break
        end
      end
    end
  end
  picker_opts.actions = vim.tbl_extend("force", {}, picker_opts.actions or {}, {
    toggle_buffer = function(picker)
      toggle_scope(picker, "buffer")
    end,
    toggle_global = function(picker)
      toggle_scope(picker, "global")
    end,
  })
  picker_opts.action_descriptions = vim.tbl_extend("force", {}, picker_opts.action_descriptions or {}, {
    toggle_buffer = "Show or hide buffer keymaps",
    toggle_global = "Show or hide global keymaps",
  })
  local restore_allowed = true
  local on_close = opts.on_close or config.picker.on_close
  if picker_opts.components == nil and not picker_opts.format_item then
    local C = require("selection_tools.components")
    picker_opts.components = {
      C.text({
        get = function(item)
          return keys.display(item.keys)
        end,
        min_width = 18,
        hl = "KeymapToolsKey",
      }),
      C.text({
        get = function()
          return "›"
        end,
        searchable = false,
        hl = "KeymapToolsSeparator",
      }),
      C.text({
        get = function(item)
          return decorations[item].icon
        end,
        searchable = false,
        hl = false,
        highlights = function(item)
          local icon = decorations[item]
          return { { 0, #icon.icon, hl = icon.hl } }
        end,
      }),
      C.text({ field = "scope", width = 6, hl = "KeymapToolsMuted" }),
      C.text({
        get = function(item)
          return (item.group and "+" or "") .. item.desc
        end,
        grow = 1,
        truncate = "match",
        highlights = function(item)
          return item.group and { { 0, #item.desc + 1, hl = "KeymapToolsGroup" } } or {}
        end,
      }),
    }
  end
  local picker = selection.select(
    items,
    vim.tbl_deep_extend("force", {}, picker_opts, {
      prompt = prompt(),
      resume = false,
      nested = parent ~= nil,
      preview = { enabled = false },
      item_icons = false,
      match_priority = function(item)
        return item.scope == "buffer" and 0 or 1
      end,
      format_item = function(item)
        return presentation(item).text
      end,
      highlight_item = not picker_opts.components and function(item)
        return presentation(item).spans
      end or nil,
      before_confirm = function(ctx)
        return valid(ctx.item)
      end,
      on_close = function(closed, outcome)
        restore_allowed = outcome.reason == "cancel" or outcome.reason == "confirm"
        if active and active.picker == closed then
          active = nil
        end
        if on_close then
          on_close(closed, outcome)
        end
      end,
    }),
    function(item)
      -- selection-tools closes its Insert-mode windows before this callback.
      -- Defer once more so stopinsert has taken effect before replaying keys.
      vim.schedule(function()
        if version ~= generation or not restore_allowed then
          return
        end
        if
          not api.nvim_win_is_valid(origin.win)
          or api.nvim_win_get_buf(origin.win) ~= origin.buf
          or api.nvim_get_current_win() ~= origin.win
        then
          return
        end
        if item then
          local still_valid, reason = valid(item)
          if not still_valid then
            vim.notify("keymap-tools: " .. reason, vim.log.levels.WARN)
            return
          end
        end
        api.nvim_set_current_win(origin.win)
        if origin.mode == "x" then
          vim.cmd.normal({ args = { "gv" }, bang = true })
        elseif insert_cursor then
          -- Closing the input window leaves Normal mode and may shift the
          -- source cursor left. Restore the original insertion byte position;
          -- startinsert! is needed at EOL, where Normal mode clamps the column.
          api.nvim_win_set_cursor(origin.win, insert_cursor)
          local line = api.nvim_buf_get_lines(origin.buf, insert_cursor[1] - 1, insert_cursor[1], false)[1]
          vim.cmd.startinsert({ bang = insert_cursor[2] >= #line })
        end
        if item then
          require("keymap_tools.hints").replay(item.keys)
        end
      end)
    end
  )
  if type(picker) == "table" and not picker.closed then
    -- selection-tools also uses Alt+g for file globs. This modal action owns
    -- its configured keys regardless of the base picker's installation order.
    if picker.input_buf then
      for _, buf in ipairs({ picker.input_buf, picker.list_buf, picker.preview_buf }) do
        for _, name in ipairs({ "buffer", "global" }) do
          local target = name
          for _, key in ipairs(toggle_keys[name]) do
            vim.keymap.set({ "n", "i" }, key, function()
              toggle_scope(picker, target)
            end, {
              buffer = buf,
              nowait = true,
              silent = true,
              desc = "[Keymaps] Show or hide " .. name .. " keymaps",
            })
          end
        end
      end
    end
    active = { picker = picker, items = items, rebuild = rebuild }
  end
  return picker
end

function M.dispose()
  generation = generation + 1
  local session = active
  active = nil
  if session and not session.picker.closed then
    session.picker:close(nil, nil, nil, { reason = "dispose" })
  end
end

return M
