local M = {}
local configured = false

function M.setup(opts)
  local config = require("keymap_tools.config")
  local value = config.normalize(opts)
  require("keymap_tools.hints").setup(value)
  config.set(value)
  configured = true
end

local function ensure_setup()
  if not configured then
    M.setup()
  end
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
  require("keymap_tools.hints").hide()
end

function M.refresh()
  ensure_setup()
  require("keymap_tools.hints").refresh()
end

return M
