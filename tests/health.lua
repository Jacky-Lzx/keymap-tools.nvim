vim.opt.rtp:prepend(vim.fn.getcwd())
local reports = {}
for _, kind in ipairs({ "start", "ok", "warn", "info" }) do
  vim.health[kind] = function(message)
    reports[#reports + 1] = { kind = kind, message = message }
  end
end
local health = require("keymap_tools.health")
health.check()
assert(vim.iter(reports):any(function(r)
  return r.kind == "warn" and r.message:find("selection-tools unavailable", 1, true)
end))
assert(not package.loaded.keymap_tools and not package.loaded.selection_tools)
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture .. "/lua/selection_tools", "p")
vim.fn.writefile({ 'error("Health must not execute this provider")' }, fixture .. "/lua/selection_tools/init.lua")
vim.opt.rtp:append(fixture)
reports = {}
health.check()
assert(vim.iter(reports):any(function(r)
  return r.kind == "ok" and r.message:find("selection-tools available", 1, true)
end))
assert(not package.loaded.keymap_tools and not package.loaded.selection_tools)
vim.opt.rtp:remove(fixture)
vim.fn.delete(fixture, "rf")
print("Keymap health: missing/available providers and initialization isolation passed")
