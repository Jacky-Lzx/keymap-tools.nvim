local M = {}

-- Classify actions locally; the loaded shared service owns glyphs and colors.
local rules = {
  { { "diagnostic", "诊断" }, "󰒡", "Green", "diagnostics" },
  { { "debug", "dap", "breakpoint", "调试", "断点" }, "", "Red", "debug" },
  { { "git", "commit", "branch", "hunk" }, "󰊢", "Orange", "git" },
  { { "search", "find", "grep", "selection", "搜索", "查找", "选择" }, "", "Green", "search" },
  { { "terminal", "终端" }, "", "Red", "terminal" },
  { { "format", "indent", "格式", "缩进" }, "󰉢", "Cyan", "format" },
  { { "rename", "重命名" }, "󰑕", "Purple", "rename" },
  { { "code", "lsp", "definition", "reference", "代码", "定义", "引用" }, "", "Blue", "code" },
  { { "workspace", "project", "工作区", "项目" }, "󰉋", "Cyan", "workspace" },
  { { "buffer", "file", "文件", "缓冲" }, "󰈔", "Cyan", "file" },
  { { "window", "split", "窗口", "分屏" }, "", "Blue", "window" },
  { { "tab", "标签" }, "󰓩", "Purple", "tab" },
  { { "save", "write", "session", "保存", "会话" }, "", "Blue", "save" },
  { { "quit", "exit", "close", "退出", "关闭" }, "󰅖", "Red", "close" },
  { { "toggle", "enable", "disable", "切换", "启用", "禁用" }, "", "Yellow", "toggle_off" },
  {
    { "register", "clipboard", "yank", "paste", "copy", "寄存器", "复制", "粘贴" },
    "",
    "Yellow",
    "register",
  },
  { { "mark", "bookmark", "标记", "书签" }, "󰃀", "Purple", "mark" },
  { { "spell", "拼写" }, "󰓆", "Green", "spell" },
  { { "fold", "折叠" }, "󰘖", "Cyan", "fold" },
  { { "help", "帮助" }, "󰋖", "Blue", "help" },
  { { "test", "测试" }, "󰙨", "Green", "test" },
  { { "build", "compile", "构建", "编译" }, "󰙨", "Orange", "build" },
  { { "notif", "message", "通知", "消息" }, "󰵅", "Blue", "notification" },
  { { "ui", "theme", "界面", "主题" }, "󰙵", "Purple", "theme" },
  { { "move", "jump", "next", "previous", "跳转", "移动" }, "󰁔", "Blue", "move" },
  { { "delete", "remove", "删除" }, "󰆴", "Red", "delete" },
  { { "undo", "redo", "撤销", "重做" }, "󰕌", "Orange", "undo" },
}

function M.highlights()
  require("keymap_tools.theme").setup()
end

function M.resolve(item, config)
  config = config or require("keymap_tools.config").get().icons
  if not config.enabled or item.icon == false then
    return "", "KeymapToolsIcon"
  end
  local shared = package.loaded["theme_tools.icons"]
  shared = type(shared) == "table" and type(shared.get) == "function" and shared or nil
  local mode = shared and shared.current()
  if mode == "none" then
    return "", "KeymapToolsIcon"
  end
  local function semantic(name, fallback, hl)
    if shared then
      local icon, group, default = shared.get("ui", name)
      if not default or mode == "ascii" then
        return icon, group
      end
    end
    return fallback, hl
  end
  local function custom(value)
    value = type(value) == "string" and { icon = value } or value
    if mode == "ascii" then
      local icon, hl = shared.get("ui", "keymap")
      return value.ascii or icon, value.hl or hl
    end
    return value.icon, value.hl or "KeymapToolsIcon"
  end
  if item.icon ~= nil then
    return custom(item.icon)
  end
  local desc = (item.desc or ""):lower()
  for _, rule in ipairs(config.rules) do
    if desc:find(rule.pattern) then
      return custom(rule)
    end
  end
  if item.toggle then
    return semantic(
      item.toggle.state == true and "toggle_on" or "toggle_off",
      item.toggle.state == true and "" or "",
      "KeymapToolsIconYellow"
    )
  end
  for _, rule in ipairs(rules) do
    for _, word in ipairs(rule[1]) do
      -- Match English word starts (also allowing plurals), and literal CJK text.
      local pattern = word:match("^[a-z]+$") and ("%f[%a]" .. word) or word
      if desc:find(pattern) then
        return semantic(rule[4], rule[2], "KeymapToolsIcon" .. rule[3])
      end
    end
  end
  local group = item.group or item.kind == "group"
  return semantic(group and "group" or "keymap", group and "󰉋" or "󰌌", "KeymapToolsIcon")
end

return M
