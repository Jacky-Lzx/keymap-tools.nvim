local api = vim.api
local keys = require("keymap_tools.keys")
local maps = require("keymap_tools.maps")
local M = {}

function M.open(opts)
  opts = opts or {}
  local ok, selection = pcall(require, "selection_tools")
  if not ok then
    vim.notify("keymap-tools: install selection-tools.nvim to use the keymap picker", vim.log.levels.WARN)
    return false
  end
  local origin = { win = api.nvim_get_current_win(), buf = api.nvim_get_current_buf(), mode = opts.mode or keys.mode() }
  if origin.mode ~= "n" and origin.mode ~= "x" then
    vim.notify("keymap-tools: open the picker from Normal or Visual mode", vim.log.levels.WARN)
    return false
  end
  local items = maps.available(vim.tbl_extend("force", {}, opts, { buf = origin.buf, mode = origin.mode }))
  if #items == 0 then
    vim.notify("keymap-tools: no mappings for this buffer and mode", vim.log.levels.INFO)
    return false
  end
  if keys.mode() == "x" then
    -- Save '< and '> before the picker changes focus and enters Insert mode.
    vim.cmd.normal({ args = { keys.raw("<Esc>") }, bang = true })
  end
  local function valid(item)
    if not api.nvim_win_is_valid(origin.win) or api.nvim_win_get_buf(origin.win) ~= origin.buf then
      return false, "Source window changed; reopen the keymap picker"
    end
    for _, current in ipairs(maps.collect({ buf = origin.buf, mode = origin.mode })) do
      if current.keys == item.keys and maps.same(item, current) then
        return true
      end
    end
    return false, "Mapping changed; reopen the keymap picker"
  end
  return selection.select(
    items,
    vim.tbl_deep_extend("force", {}, opts.picker or {}, {
      prompt = "Buffer keymaps · " .. origin.mode,
      resume = false,
      preview = { enabled = false },
      format_item = function(item)
        local label = keys.label(item.keys)
        return ("%s%s  %-6s  %s"):format(
          label,
          string.rep(" ", math.max(0, 18 - vim.fn.strdisplaywidth(label))),
          item.scope,
          item.desc
        )
      end,
      before_confirm = function(ctx)
        return valid(ctx.item)
      end,
    }),
    function(item)
      -- selection-tools closes its Insert-mode windows before this callback.
      -- Defer once more so stopinsert has taken effect before replaying keys.
      vim.schedule(function()
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
end

return M
