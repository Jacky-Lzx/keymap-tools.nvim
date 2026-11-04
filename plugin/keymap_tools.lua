if vim.g.loaded_keymap_tools then
  return
end
vim.g.loaded_keymap_tools = true

vim.api.nvim_create_user_command("KeymapTools", function(args)
  local action = args.fargs[1] or "pick"
  if action == "showkeys" then
    local operation = args.fargs[2] or "toggle"
    if #args.fargs <= 2 and vim.tbl_contains({ "enable", "disable", "toggle" }, operation) then
      require("keymap_tools").showkeys[operation]()
    else
      vim.notify("keymap-tools: use showkeys [enable|disable|toggle]", vim.log.levels.ERROR)
    end
    return
  end
  if #args.fargs > 1 or not vim.tbl_contains({ "pick", "show", "hide", "refresh" }, action) then
    vim.notify("keymap-tools: unknown action: " .. action, vim.log.levels.ERROR)
    return
  end
  require("keymap_tools")[action]()
end, {
  nargs = "*",
  desc = "Show keymap hints, choose mappings, or toggle the key screencast",
  complete = function(_, line)
    if line:match("^%s*KeymapTools%s+showkeys%s+") then
      return { "enable", "disable", "toggle" }
    end
    return { "pick", "show", "hide", "refresh", "showkeys" }
  end,
})
