vim.opt.rtp:prepend(vim.fn.getcwd())
local reports = {}
for _, kind in ipairs({ "start", "ok", "warn", "info", "error" }) do
  vim.health[kind] = function(message)
    reports[#reports + 1] = { kind, message }
  end
end
require("keymap_tools.health").check()
assert(#reports == 2 and reports[2][1] == "ok", "Optional pickers do not warn when unused")
assert(not package.loaded.keymap_tools and not package.loaded.selection_tools)
print("Keymap health: compact checks without optional-provider initialization passed")
