local M = {}
local enabled = false
local last_config
local generation = 0
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

local function release()
  generation = generation + 1
  if startup then
    vim.api.nvim_del_autocmd(startup)
    startup = nil
  end
  pending = nil
  enabled = false
  for _, name in ipairs({ "showkeys", "hints", "picker", "theme" }) do
    local module = package.loaded["keymap_tools." .. name]
    if module then
      module.dispose()
    end
  end
end

function M.setup(opts)
  local config = require("keymap_tools.config")
  local value = config.normalize(opts)
  local active = enabled and pending == nil
  release()
  config.set(value)
  last_config = vim.deepcopy(value)
  local showkeys = package.loaded["keymap_tools.showkeys"]
  if showkeys or value.showkeys.enabled then
    require("keymap_tools.showkeys").setup(value.showkeys)
  end
  pending = value
  if value.defer and vim.v.vim_did_enter == 0 and not active then
    local version = generation
    startup = vim.api.nvim_create_autocmd("VimEnter", {
      once = true,
      desc = "Initialize keymap hints before the first input",
      callback = function()
        if generation ~= version then
          return
        end
        startup = nil
        activate()
      end,
    })
  else
    activate()
  end
  enabled = true
  return M
end

function M.is_enabled()
  return enabled
end

function M.disable()
  local showkeys = package.loaded["keymap_tools.showkeys"]
  if enabled or showkeys and showkeys.is_enabled() then
    last_config = vim.deepcopy(require("keymap_tools.config").get())
    last_config.showkeys.enabled = showkeys and showkeys.is_enabled() or false
  end
  release()
  return M
end

function M.enable()
  if not enabled then
    M.setup(last_config)
  end
  return M
end

function M.dispose()
  release()
  last_config = nil
  local config = package.loaded["keymap_tools.config"]
  if config then
    config.set(config.normalize())
  end
end

local function ensure_setup()
  if not enabled then
    M.enable()
  end
  activate()
end

function M.register(source, spec)
  return require("keymap_tools.registry").register(source, spec)
end

function M.register_toggle(source, spec)
  return require("keymap_tools.toggle").register(source, spec)
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

-- These actions do not activate deferred hints or load picker dependencies.
M.showkeys = {}
for _, action in ipairs({ "enable", "disable", "toggle", "is_enabled" }) do
  M.showkeys[action] = function()
    if action == "is_enabled" or action == "disable" then
      local showkeys = package.loaded["keymap_tools.showkeys"]
      return showkeys and showkeys[action]() or false
    end
    return require("keymap_tools.showkeys")[action]()
  end
end

return M
