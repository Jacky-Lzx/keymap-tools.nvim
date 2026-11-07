vim.opt.rtp:prepend(vim.fn.getcwd())
vim.opt.rtp:append(vim.fn.getcwd() .. "/../selection-tools.nvim")
local api = vim.api
local selection = require("selection_tools")
selection.setup({
  matcher = { backend = "native" },
  component_defaults = { path = { hl = "Special" }, time = { hl = "String" } },
})
local function ready(p)
  assert(
    vim.wait(5000, function()
      return not p.loading and not p.matching
    end, 5),
    "picker did not settle"
  )
  assert(not p.error, p.error)
end
local function spans(p, group)
  local result = {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(p.list_buf, -1, 0, -1, { details = true })) do
    if mark[4].hl_group == group then
      local line = api.nvim_buf_get_lines(p.list_buf, mark[2], mark[2] + 1, false)[1]
      result[#result + 1] = line:sub(mark[3] + 1, mark[4].end_col)
    end
  end
  return table.concat(result)
end
local tools = require("keymap_tools")
tools.setup({})
api.nvim_set_keymap("n", "zX1", "<Nop>", { desc = "中文 needle action" })
api.nvim_set_keymap("n", "zX2", "<Nop>", { desc = "other action" })
local p = tools.pick({ prefix = "zX", scope = "global" })
ready(p)
assert(p.components and #p.components.specs > 1)
assert(spans(p, "KeymapToolsKey"):find("zX1", 1, true))
assert(spans(p, "KeymapToolsMuted"):find("global", 1, true))
p:set_query("needle")
assert(#p.matches == 1 and p:current().desc == "中文 needle action")
assert(spans(p, "SelectionToolsMatch") == "needle")
p:close()
assert(#api.nvim_list_wins() == 1)
p = tools.pick({ prefix = "zX", scope = "global", components = false })
assert(not p.components and #p.entries == 2)
p:close()
api.nvim_del_keymap("n", "zX1")
api.nvim_del_keymap("n", "zX2")
print("Keymap components: key/scope colors, Unicode search, legacy opt-out and cleanup passed")
