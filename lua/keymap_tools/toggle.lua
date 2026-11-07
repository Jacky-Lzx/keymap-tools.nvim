local M = {}

function M.register(source, spec)
  assert(type(spec) == "table", "keymap-tools: toggle must be a table")
  local allowed = {
    keys = true,
    name = true,
    get = true,
    set = true,
    action = true,
    notify = true,
    buf = true,
    modes = true,
    priority = true,
    when = true,
    hidden = true,
    icon = true,
  }
  for key in pairs(spec) do
    assert(allowed[key], "keymap-tools: unknown toggle field: " .. tostring(key))
  end
  assert(type(spec.name) == "string" and spec.name:match("%S"), "keymap-tools: toggle requires a name")
  assert(type(spec.get) == "function", "keymap-tools: toggle requires a get function")
  assert(
    (type(spec.set) == "function") ~= (type(spec.action) == "function"),
    "keymap-tools: toggle needs exactly one set or action function"
  )
  assert(spec.set == nil or type(spec.set) == "function", "Invalid toggle set")
  assert(spec.action == nil or type(spec.action) == "function", "Invalid toggle action")
  assert(spec.notify == nil or type(spec.notify) == "boolean", "keymap-tools: toggle notify must be a boolean")
  spec = vim.deepcopy(spec)
  if spec.buf == 0 then
    spec.buf = vim.api.nvim_get_current_buf()
  end
  local registration = require("keymap_tools.registry").register(source, {
    buf = spec.buf,
    modes = spec.modes,
    priority = spec.priority,
    toggles = {
      {
        keys = spec.keys,
        name = spec.name,
        get = spec.get,
        when = spec.when,
        hidden = spec.hidden,
        icon = spec.icon,
      },
    },
  })
  local function read(ctx)
    local state = spec.get(vim.deepcopy(ctx))
    assert(state == nil or type(state) == "boolean", "keymap-tools: toggle get must return a boolean or nil")
    return state
  end
  local function callback()
    local ok, state = pcall(function()
      local ctx = require("keymap_tools.context").resolve({ buf = spec.buf })
      if spec.action then
        local accepted, err = spec.action(vim.deepcopy(ctx))
        if accepted == false and type(err) == "string" then
          error(err)
        end
      else
        local current = read(ctx)
        assert(current ~= nil, "keymap-tools: toggle state is unavailable")
        spec.set(not current, vim.deepcopy(ctx))
      end
      return read(ctx)
    end)
    if not ok then
      vim.notify(tostring(state), vim.log.levels.ERROR, { title = spec.name })
    elseif spec.notify ~= false and state ~= nil then
      vim.notify(spec.name .. ": " .. (state and "Enabled" or "Disabled"), vim.log.levels.INFO, { title = "Toggle" })
    end
    if ok then
      return state
    end
  end
  return callback, registration
end

return M
