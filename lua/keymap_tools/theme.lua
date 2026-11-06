local M = {}
local initialized, stop = false, nil
local api = vim.api

-- Refresh private defaults; public groups remain owned by themes and users.
local function define(name, value, fallback)
  local target = "KeymapToolsDefault" .. name
  local function empty(group)
    return vim.tbl_isempty(api.nvim_get_hl(0, { name = group, link = true, create = false }))
  end
  if not fallback or empty(target) then
    api.nvim_set_hl(0, target, value)
  end
  local public = "KeymapTools" .. name
  api.nvim_set_hl(0, public, { link = target, default = not empty(public) })
end

local function fallback()
  for name, link in pairs({
    Normal = "NormalFloat",
    Border = "FloatBorder",
    Key = "Special",
    Group = "Title",
    Separator = "Comment",
    Muted = "Comment",
    Icon = "Special",
    IconBlue = "Function",
    IconCyan = "Type",
    IconGreen = "String",
    IconOrange = "Constant",
    IconPurple = "Statement",
    IconRed = "DiagnosticError",
    IconYellow = "DiagnosticWarn",
  }) do
    define(name, { link = link }, true)
  end
end

local function redraw()
  local view = package.loaded["keymap_tools.view"]
  if view then
    view.redraw()
  end
  local picker = package.loaded["keymap_tools.picker"]
  if picker then
    picker.redraw()
  end
end

local function apply(c)
  for name, value in pairs({
    Normal = { fg = c.ui.float_fg, bg = c.ui.float_bg },
    Border = { fg = c.ui.border, bg = c.ui.float_bg },
    Key = { fg = c.ui.accent },
    Group = { fg = c.palette.purple, bold = true },
    Separator = { fg = c.ui.subtle },
    Muted = { fg = c.ui.muted },
    Icon = { fg = c.ui.accent },
  }) do
    define(name, value)
  end
  for _, color in ipairs({ "Blue", "Cyan", "Green", "Orange", "Purple", "Red", "Yellow" }) do
    define("Icon" .. color, { fg = c.palette[color:lower()] })
  end
  redraw()
end

local function attach()
  local themes = package.loaded.theme_tools
  if not stop and type(themes) == "table" and type(themes.on_change) == "function" then
    stop = themes.on_change("keymap-tools", apply)
  end
end

function M.setup()
  fallback()
  if initialized then
    return
  end
  initialized = true
  local group = api.nvim_create_augroup("KeymapToolsTheme", { clear = true })
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "ThemeToolsReady", "ThemeToolsIconsChanged" },
    callback = function()
      attach()
      redraw()
    end,
  })
  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      fallback()
      attach()
    end,
  })
  attach()
end

function M.dispose()
  if stop then
    stop()
    stop = nil
  end
  initialized = false
  pcall(api.nvim_del_augroup_by_name, "KeymapToolsTheme")
end

return M
