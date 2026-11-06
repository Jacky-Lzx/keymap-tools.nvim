local M = {}
local triggers = {}
for _, prefix in ipairs({ "<leader>", "<localleader>", "g", "z", "[", "]", "<C-w>" }) do
  triggers[#triggers + 1] = { prefix = prefix, modes = { "n", "x", "o" } }
end
local defaults = {
  defer = false,
  hints = { enabled = true, delay = 200, triggers = triggers, operators = true },
  window = { width = 80, height = 16, columns = 2, border = "rounded" },
  icons = { enabled = true, rules = {} },
  picker = { scope = "effective", keys = { toggle_buffer = { "<A-b>" }, toggle_global = { "<A-g>" } } },
  showkeys = {
    enabled = false,
    timeout = 3, -- Seconds, matching showkeys.
    maxkeys = 5,
    show_count = false,
    excluded_modes = {},
    position = "bottom-right",
    keyformat = {
      ["<BS>"] = "⌫",
      ["<CR>"] = "↵",
      ["<Space>"] = "␣",
      ["<Up>"] = "↑",
      ["<Down>"] = "↓",
      ["<Left>"] = "←",
      ["<Right>"] = "→",
      ["<PageUp>"] = "Page ↑",
      ["<PageDown>"] = "Page ↓",
      ["<M>"] = "Alt",
      ["<C>"] = "Ctrl",
      ["<S>"] = "Shift",
      ["<D>"] = "Cmd",
    },
    winopts = { border = "single", zindex = 60 },
    winhl = "Normal:NormalFloat,FloatBorder:FloatBorder",
  },
  presets = true,
  providers = { registers = true, marks = true, spelling = { suggestions = 20 } },
}
local current = vim.deepcopy(defaults)

function M.get()
  return current
end

local function border(value, name)
  if type(value) == "string" then
    assert(
      vim.tbl_contains({ "none", "", "single", "double", "rounded", "solid", "shadow" }, value),
      "keymap-tools: invalid " .. name
    )
    return
  end
  assert(
    type(value) == "table" and vim.islist(value) and vim.tbl_contains({ 1, 2, 4, 8 }, #value),
    "keymap-tools: invalid " .. name
  )
  for _, entry in ipairs(value) do
    local char = entry
    if type(entry) == "table" then
      assert(
        vim.islist(entry) and #entry == 2 and type(entry[2]) == "string",
        "keymap-tools: invalid " .. name .. " highlight"
      )
      char = entry[1]
    end
    assert(
      type(char) == "string" and not char:find("[%c]") and vim.fn.strdisplaywidth(char) <= 1,
      "keymap-tools: border characters must occupy at most one cell"
    )
  end
end

function M.normalize(opts)
  assert(opts == nil or type(opts) == "table", "keymap-tools: setup expects a table")
  opts = vim.deepcopy(opts or {})
  for key in pairs(opts) do
    assert(defaults[key] ~= nil, "keymap-tools: unknown setup field: " .. tostring(key))
  end
  local result = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  for _, name in ipairs({ "hints", "window", "providers" }) do
    assert(type(result[name]) == "table", "keymap-tools: " .. name .. " must be a table")
  end
  assert(type(result.icons) == "table", "keymap-tools: icons must be a table")
  for field in pairs(result.icons) do
    assert(defaults.icons[field] ~= nil, "keymap-tools: unknown icons field: " .. tostring(field))
  end
  assert(type(result.icons.enabled) == "boolean", "keymap-tools: icons.enabled must be boolean")
  assert(vim.islist(result.icons.rules), "keymap-tools: icons.rules must be a list")
  for _, rule in ipairs(result.icons.rules) do
    assert(type(rule) == "table", "keymap-tools: icon rule must be a table")
    for field in pairs(rule) do
      assert(
        field == "pattern" or field == "icon" or field == "hl" or field == "ascii",
        "keymap-tools: unknown icon rule field"
      )
    end
    assert(
      type(rule.pattern) == "string" and pcall(string.find, "", rule.pattern),
      "keymap-tools: invalid icon pattern"
    )
    assert(type(rule.icon) == "string" and not rule.icon:find("[%c]"), "keymap-tools: invalid rule icon")
    assert(rule.hl == nil or type(rule.hl) == "string", "keymap-tools: invalid icon highlight")
    assert(
      rule.ascii == nil or type(rule.ascii) == "string" and not rule.ascii:find("[^ -~]"),
      "keymap-tools: rule ascii must be printable ASCII"
    )
  end
  if opts.showkeys and opts.showkeys.excluded_modes ~= nil then
    result.showkeys.excluded_modes = vim.deepcopy(opts.showkeys.excluded_modes)
  end
  local showkeys = result.showkeys
  assert(type(showkeys) == "table", "keymap-tools: showkeys must be a table")
  for field in pairs(showkeys) do
    assert(defaults.showkeys[field] ~= nil, "keymap-tools: unknown showkeys field: " .. tostring(field))
  end
  assert(type(showkeys.enabled) == "boolean", "keymap-tools: showkeys.enabled must be boolean")
  assert(type(showkeys.show_count) == "boolean", "keymap-tools: showkeys.show_count must be boolean")
  assert(
    type(showkeys.timeout) == "number" and showkeys.timeout > 0 and showkeys.timeout < math.huge,
    "keymap-tools: showkeys.timeout must be positive seconds"
  )
  assert(
    type(showkeys.maxkeys) == "number"
      and showkeys.maxkeys >= 1
      and showkeys.maxkeys == math.floor(showkeys.maxkeys)
      and showkeys.maxkeys < math.huge,
    "keymap-tools: showkeys.maxkeys must be a positive integer"
  )
  assert(
    vim.tbl_contains(
      { "top-left", "top-center", "top-right", "bottom-left", "bottom-center", "bottom-right" },
      showkeys.position
    ),
    "keymap-tools: invalid showkeys.position"
  )
  assert(vim.islist(showkeys.excluded_modes), "keymap-tools: showkeys.excluded_modes must be a list")
  for _, mode in ipairs(showkeys.excluded_modes) do
    assert(type(mode) == "string" and #mode > 0, "keymap-tools: excluded modes must be nonempty strings")
  end
  assert(type(showkeys.keyformat) == "table", "keymap-tools: showkeys.keyformat must be a table")
  for key, label in pairs(showkeys.keyformat) do
    assert(
      type(key) == "string" and type(label) == "string" and not label:find("[%c]"),
      "keymap-tools: invalid keyformat"
    )
  end
  assert(type(showkeys.winhl) == "string", "keymap-tools: showkeys.winhl must be a string")
  assert(type(showkeys.winopts) == "table", "keymap-tools: showkeys.winopts must be a table")
  for field in pairs(showkeys.winopts) do
    assert(field == "border" or field == "zindex", "keymap-tools: showkeys.winopts accepts border and zindex")
  end
  assert(
    type(showkeys.winopts.zindex) == "number"
      and showkeys.winopts.zindex >= 1
      and showkeys.winopts.zindex == math.floor(showkeys.winopts.zindex)
      and showkeys.winopts.zindex < math.huge,
    "keymap-tools: showkeys zindex must be a positive integer"
  )
  border(showkeys.winopts.border, "showkeys.winopts.border")
  assert(type(result.defer) == "boolean", "keymap-tools: defer must be boolean")
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
  assert(
    type(result.hints.delay) == "number" and result.hints.delay >= 0 and result.hints.delay < math.huge,
    "keymap-tools: delay must be nonnegative"
  )
  assert(vim.islist(result.hints.triggers), "keymap-tools: hints.triggers must be a list")
  for _, trigger in ipairs(result.hints.triggers) do
    assert(
      type(trigger) == "table"
        and type(trigger.prefix) == "string"
        and #trigger.prefix > 0
        and vim.islist(trigger.modes)
        and #trigger.modes > 0,
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
      type(value) == "number" and value >= 1 and value < math.huge and value == math.floor(value),
      "keymap-tools: window dimensions must be positive integers"
    )
  end
  border(result.window.border, "window.border")
  assert(result.window.columns == 1 or result.window.columns == 2, "keymap-tools: window.columns must be 1 or 2")
  assert(
    type(result.picker) == "table" and result.picker.key == nil,
    "keymap-tools: bind picker shortcuts with vim.keymap.set()"
  )
  assert(
    vim.tbl_contains({ "buffer", "global", "effective" }, result.picker.scope),
    "keymap-tools: invalid picker scope"
  )
  assert(type(result.picker.keys) == "table", "keymap-tools: picker.keys must be a table")
  for _, name in ipairs({ "toggle_buffer", "toggle_global" }) do
    assert(vim.islist(result.picker.keys[name]), "keymap-tools: picker.keys." .. name .. " must be a list")
    for _, key in ipairs(result.picker.keys[name]) do
      assert(type(key) == "string" and key ~= "", "keymap-tools: scope toggle keys must be nonempty strings")
    end
  end
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
