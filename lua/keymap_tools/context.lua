local api = vim.api
local keys = require("keymap_tools.keys")
local M = {}

function M.resolve(opts)
  opts = opts or {}
  local win = opts.win
  if win == nil or win == 0 then
    win = api.nvim_get_current_win()
  end
  assert(api.nvim_win_is_valid(win), "keymap-tools: invalid window")
  local buf = opts.buf
  if buf == nil or buf == 0 then
    buf = api.nvim_win_get_buf(win)
  end
  assert(api.nvim_buf_is_valid(buf), "keymap-tools: invalid buffer")
  if api.nvim_win_get_buf(win) ~= buf then
    assert(opts.win == nil, "keymap-tools: window does not display the requested buffer")
    win = nil
    for _, candidate in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_buf(candidate) == buf then
        win = candidate
        break
      end
    end
  end
  local mode = opts.mode or keys.mode()
  assert(mode:match("^[nxoisct]$"), "keymap-tools: unsupported mode: " .. tostring(mode))
  local raw = keys.raw(opts.prefix or "")
  return {
    buf = buf,
    win = win,
    mode = mode,
    prefix = keys.label(raw),
    operator = opts.operator or (mode == "o" and keys.mode() == "o" and vim.v.operator or nil),
    count = opts.count == nil and vim.v.count or opts.count,
    register = opts.register or vim.v.register,
  }
end

-- Dynamic integrations receive a detached context; one callback cannot alter
-- another callback's source buffer/window or the live input session.
function M.evaluate(value, ctx, errors, source, field)
  if type(value) ~= "function" then
    return value, true
  end
  local ok, result = pcall(value, vim.deepcopy(ctx))
  if ok then
    return result, true
  end
  errors[#errors + 1] = { source = source, field = field, message = tostring(result) }
  return nil, false
end

return M
