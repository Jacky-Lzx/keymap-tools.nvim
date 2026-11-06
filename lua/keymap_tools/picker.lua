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
  if origin.mode ~= "n" and origin.mode ~= "x" then
    vim.notify("keymap-tools: open the picker from Normal or Visual mode", vim.log.levels.WARN)
    return false
  end
  local config = require("keymap_tools.config").get()
  local icons = require("keymap_tools.icons")
  local display = require("keymap_tools.display")
  require("keymap_tools.view").highlights()
  local items =
    query.collect(vim.tbl_extend("force", {}, origin, { scope = "effective", kinds = { "mapping" } }), config)
  if opts.prefix then
    local prefix = keys.raw(opts.prefix)
    items = vim.tbl_filter(function(item)
      return item.keys:sub(1, #prefix) == prefix
    end, items)
  end
  if opts.scope and opts.scope ~= "effective" then
    assert(opts.scope == "global" or opts.scope == "buffer", "keymap-tools: invalid picker scope")
    items = vim.tbl_filter(function(item)
      return item.scope == opts.scope
    end, items)
  end
  if #items == 0 then
    vim.notify("keymap-tools: no mappings for this buffer and mode", vim.log.levels.INFO)
    return false
  end
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
    for _, current in
      ipairs(
        query.collect(
          vim.tbl_extend("force", {}, origin, { scope = "effective", kinds = { "mapping" }, include_hidden = true }),
          config
        )
      )
    do
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
  local on_close = opts.on_close or config.picker.on_close
  local picker = selection.select(
    items,
    vim.tbl_deep_extend("force", {}, config.picker, opts, {
      prompt = "Buffer keymaps · " .. origin.mode,
      resume = false,
      preview = { enabled = false },
      item_icons = false,
      format_item = function(item)
        return presentation(item).text
      end,
      highlight_item = function(item)
        return presentation(item).spans
      end,
      before_confirm = function(ctx)
        return valid(ctx.item)
      end,
      on_close = function(closed, outcome)
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
        if version ~= generation then
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
        end
        if item then
          require("keymap_tools.hints").replay(item.keys)
        end
      end)
    end
  )
  if type(picker) == "table" and not picker.closed then
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
