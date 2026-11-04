local M = {}
local defaults = {
  enabled = true,
  delay = 200,
  modes = { "n", "x", "o" },
  triggers = { "<leader>", "<localleader>", "g", "z", "[", "]", "<C-w>" },
  groups = {},
  presets = true,
  providers = { registers = true, marks = true, spelling = { suggestions = 20 } },
  win = { width = 48, height = 16, border = "rounded" },
  picker = { key = "<leader>?" },
}
local configured = false
local installed = {}

function M.setup(opts)
  local config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  assert(type(config.delay) == "number" and config.delay >= 0, "keymap-tools: delay must be nonnegative")
  for _, mode in ipairs(config.modes) do
    assert(mode == "n" or mode == "x" or mode == "o", "keymap-tools: automatic hints support n/x/o modes")
  end
  assert(config.win.width >= 1 and config.win.height >= 1, "keymap-tools: window dimensions must be positive")
  for _, entry in ipairs(installed) do
    for _, current in ipairs(vim.api.nvim_get_keymap(entry.mode)) do
      if current.callback == entry.callback then
        vim.keymap.del(entry.mode, entry.lhs)
        break
      end
    end
  end
  installed = {}
  if config.picker.key then
    for _, mode in ipairs({ "n", "x" }) do
      -- Respect an existing user mapping. The API/command is always available.
      if vim.fn.maparg(config.picker.key, mode) == "" then
        local callback = function()
          M.pick()
        end
        vim.keymap.set(mode, config.picker.key, callback, { desc = "Choose and execute buffer keymap", silent = true })
        installed[#installed + 1] = { lhs = config.picker.key, mode = mode, callback = callback }
      end
    end
  end
  configured = true
  require("keymap_tools.hints").setup(config)
end

local function ensure_setup()
  if not configured then
    M.setup()
  end
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

function M.get_keymaps(opts)
  return require("keymap_tools.maps").collect(opts)
end

function M.add(spec)
  require("keymap_tools.metadata").add(spec)
  if configured then
    require("keymap_tools.hints").refresh()
  end
end

return M
