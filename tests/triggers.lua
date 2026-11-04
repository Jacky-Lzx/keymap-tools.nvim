vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = " "
local api, tools = vim.api, require("keymap_tools")
local keys, maps = require("keymap_tools.keys"), require("keymap_tools.maps")
local query, config = require("keymap_tools.query"), require("keymap_tools.config").normalize({})
local prefixes = {}
for _, lhs in ipairs({ "<leader>", "g", "z", "a", "i", '"', "'", "<C-r>", "<F3>", "<Plug>" }) do
  prefixes[#prefixes + 1] = keys.raw(lhs)
end
local function parity(buf, mode)
  local ctx = { buf = buf, mode = mode }
  local items = query.hints(ctx, config)
  local actual = query.triggers(ctx, config, prefixes)
  for _, prefix in ipairs(prefixes) do
    local matches, exact = maps.match(items, prefix)
    local expected = #matches > 0 and (not exact or exact.virtual) or false
    assert(actual[prefix] == expected, "trigger projection disagrees for " .. mode .. ":" .. keys.label(prefix))
  end
end
local active, desc = true, "Dynamic"
local first = api.nvim_get_current_buf()
vim.keymap.set("n", "<leader>aa", "<Nop>")
vim.keymap.set("n", "<F3>a", "<Nop>")
vim.keymap.set("n", "<Plug>(private)", "<Nop>")
tools.register("projection", {
  modes = { "n", "x", "o", "i", "c" },
  groups = { { prefix = "g", label = "Group", hidden = true } },
  hints = {
    { keys = "<F3>a", desc = "Annotation" },
    {
      keys = "<leader>conditional",
      when = function(ctx)
        return active and ctx.buf == first
      end,
      desc = function()
        if desc == "error" then
          error("dynamic description failed")
        end
        return desc
      end,
      hidden = true,
    },
  },
})
local second = api.nvim_create_buf(false, true)
tools.register("buffer-exact", { buf = second, hints = { { keys = "g", desc = "Virtual exact" } } })
tools.register("dynamic-only", {
  hints = {
    {
      keys = "Qx",
      desc = function()
        return desc
      end,
      when = function()
        return active
      end,
    },
  },
})
for _, state in ipairs({ "Dynamic", "error", false }) do
  desc = state
  assert(query.triggers({ mode = "n" }, config, { "Q" }).Q == (type(desc) == "string"))
  for _, buf in ipairs({ first, second }) do
    for _, mode in ipairs({ "n", "x", "o", "i", "c" }) do
      parity(buf, mode)
    end
  end
end
active = false
assert(not query.triggers({ mode = "n" }, config, { "Q" }).Q)
vim.keymap.set("n", "g", "<Nop>")
vim.keymap.set("n", "<F3>", "<Nop>", { buffer = first })
parity(first, "n")
parity(second, "n")

-- Display callbacks outside the requested prefix cannot affect installation.
tools.register("display-only", {
  groups = { {
    prefix = "other",
    label = function()
      error("unused group label")
    end,
  } },
  hints = { {
    keys = "other-key",
    desc = function()
      error("unrelated description")
    end,
  } },
})
for i = 1, 200 do
  vim.keymap.set("n", ("q%03d"):format(i), "<Nop>")
end
local label, calls = keys.label, 0
keys.label = function(raw)
  calls = calls + 1
  return label(raw)
end
local rows, info = query.collect({ mode = "n", trigger_prefixes = { "q" }, sort = false }, config)
keys.label = label
assert(#rows == 200 and #info.errors == 0)
assert(calls <= 2, "trigger installation must not format mapping display names")
local enabled = query.triggers({ mode = "n" }, config, { "q" })
assert(enabled.q)
vim.keymap.set("n", "q", "<Nop>")
assert(not query.triggers({ mode = "n" }, config, { "q" }).q, "exact native mapping must prevent a trigger")
print("PASS lightweight/full query parity across modes, scopes, hidden entries, dynamic failures and exact mappings")
