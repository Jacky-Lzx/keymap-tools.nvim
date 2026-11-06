local M = {}
function M.check()
  vim.health.start("keymap-tools.nvim providers")
  if #vim.api.nvim_get_runtime_file("lua/selection_tools/init.lua", false) > 0 then
    vim.health.ok("selection-tools available for executable keymap pickers")
  else
    vim.health.warn("selection-tools unavailable; keymap execution picker requires it", {
      "Install/mount Jacky-Lzx/selection-tools.nvim; hints and mapping inspection work independently",
    })
  end
  if #vim.api.nvim_get_runtime_file("lua/theme_tools/init.lua", false) > 0 then
    vim.health.ok("theme-tools shared icons and palette available")
  else
    vim.health.info("theme-tools unavailable; standard highlights and fallback icons remain available")
  end
end
return M
