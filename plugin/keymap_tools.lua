if vim.g.loaded_keymap_tools then
  return
end
vim.g.loaded_keymap_tools = true

vim.api.nvim_create_user_command("KeymapTools", function(args)
  local action = args.args ~= "" and args.args or "pick"
  if not vim.tbl_contains({ "pick", "show", "hide", "refresh" }, action) then
    vim.notify("keymap-tools: unknown action: " .. action, vim.log.levels.ERROR)
    return
  end
  require("keymap_tools")[action]()
end, {
  nargs = "?",
  desc = "Show or choose and execute buffer keymaps",
  complete = function()
    return { "pick", "show", "hide", "refresh" }
  end,
})
