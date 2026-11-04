local M = {}
local configured = false
local pending, startup

local function activate()
  if startup then
    vim.api.nvim_del_autocmd(startup)
    startup = nil
  end
  if pending then
    local value = pending
    pending = nil
    require("keymap_tools.hints").setup(value)
  end
end

function M.setup(opts)
  local config = require("keymap_tools.config")
  local value = config.normalize(opts)
  config.set(value)
  if startup then
    vim.api.nvim_del_autocmd(startup)
    startup = nil
  end
  pending = value
  if value.defer and vim.v.vim_did_enter == 0 and not package.loaded["keymap_tools.hints"] then
    startup = vim.api.nvim_create_autocmd("VimEnter", {
      once = true,
      desc = "Initialize keymap hints before the first input",
      callback = function()
        startup = nil
        activate()
      end,
    })
  else
    activate()
  end
  configured = true
end

local function ensure_setup()
  if not configured then
    M.setup()
  end
  activate()
end

function M.register(source, spec)
  return require("keymap_tools.registry").register(source, spec)
end

function M.list(opts)
  return require("keymap_tools.query").list(opts)
end

function M.pick(opts)
  ensure_setup()
  return require("keymap_tools.picker").open(opts)
end

function M.show(opts)
  ensure_setup()
  return require("keymap_tools.hints").show(opts)
end

function M.hide()
  local hints = package.loaded["keymap_tools.hints"]
  if hints then
    hints.hide()
  end
end

function M.refresh()
  ensure_setup()
  require("keymap_tools.hints").refresh()
end

return M
