local M = {}
local triggers = {}
for _, prefix in ipairs({ "<leader>", "<localleader>", "g", "z", "[", "]", "<C-w>" }) do
  triggers[#triggers + 1] = { prefix = prefix, modes = { "n", "x", "o" } }
end
local defaults = {
  hints = { enabled = true, delay = 200, triggers = triggers, operators = true },
  window = { width = 80, height = 16, columns = 2, border = "rounded" },
  picker = {},
  presets = true,
  providers = { registers = true, marks = true, spelling = { suggestions = 20 } },
}
local current = vim.deepcopy(defaults)

function M.get()
  return current
end

function M.normalize(opts)
  opts = opts or {}
  for key in pairs(opts) do
    assert(defaults[key] ~= nil, "keymap-tools: unknown setup field: " .. tostring(key))
  end
  local result = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  if opts.hints and opts.hints.triggers ~= nil then
    result.hints.triggers = vim.deepcopy(opts.hints.triggers)
  end
  for field in pairs(result.hints) do
    assert(defaults.hints[field] ~= nil, "keymap-tools: unknown hints field: " .. field)
  end
  assert(
    type(result.hints.enabled) == "boolean" and type(result.hints.operators) == "boolean",
    "keymap-tools: invalid hints enabled/operators"
  )
  assert(type(result.hints.delay) == "number" and result.hints.delay >= 0, "keymap-tools: delay must be nonnegative")
  assert(vim.islist(result.hints.triggers), "keymap-tools: hints.triggers must be a list")
  for _, trigger in ipairs(result.hints.triggers) do
    assert(
      type(trigger.prefix) == "string" and #trigger.prefix > 0 and vim.islist(trigger.modes) and #trigger.modes > 0,
      "keymap-tools: each trigger requires prefix and modes"
    )
    for field in pairs(trigger) do
      assert(field == "prefix" or field == "modes", "keymap-tools: unknown trigger field")
    end
    for _, mode in ipairs(trigger.modes) do
      assert(type(mode) == "string" and mode:match("^[nxoic]$"), "keymap-tools: invalid trigger mode")
    end
  end
  for field in pairs(result.window) do
    assert(defaults.window[field] ~= nil, "keymap-tools: unknown window field: " .. field)
  end
  for _, field in ipairs({ "width", "height" }) do
    local value = result.window[field]
    assert(
      type(value) == "number" and value >= 1 and value == math.floor(value),
      "keymap-tools: window dimensions must be positive integers"
    )
  end
  assert(result.window.columns == 1 or result.window.columns == 2, "keymap-tools: window.columns must be 1 or 2")
  assert(
    type(result.picker) == "table" and result.picker.key == nil,
    "keymap-tools: bind picker shortcuts with vim.keymap.set()"
  )
  for name, option in pairs(result.providers) do
    assert(defaults.providers[name] ~= nil, "keymap-tools: unknown provider: " .. name)
    assert(
      type(option) == "boolean" or type(option) == "table",
      "keymap-tools: provider option must be boolean or table"
    )
  end
  for name, option in pairs(result.providers) do
    if type(option) == "table" then
      for field in pairs(option) do
        assert(
          field == "enabled"
            or (name == "registers" and field == "clipboard")
            or (name == "spelling" and field == "suggestions"),
          "keymap-tools: unknown provider option: " .. field
        )
      end
      assert(
        option.enabled == nil or type(option.enabled) == "boolean",
        "keymap-tools: provider enabled must be boolean"
      )
      assert(option.clipboard == nil or type(option.clipboard) == "boolean", "keymap-tools: clipboard must be boolean")
      if option.suggestions then
        assert(
          type(option.suggestions) == "number"
            and option.suggestions >= 1
            and option.suggestions <= 62
            and option.suggestions == math.floor(option.suggestions),
          "keymap-tools: suggestions must be an integer between 1 and 62"
        )
      end
    end
  end
  assert(
    type(result.presets) == "boolean" or type(result.presets) == "table",
    "keymap-tools: presets must be boolean or table"
  )
  if type(result.presets) == "table" then
    for field, value in pairs(result.presets) do
      assert(
        vim.tbl_contains({ "motions", "navigation", "windows", "folds", "textobjects" }, field)
          and type(value) == "boolean",
        "keymap-tools: invalid preset option"
      )
    end
  end
  return result
end

function M.set(value)
  current = value
end

return M
