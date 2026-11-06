#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_root=$(mktemp -d "${TMPDIR:-/tmp}/keymap-tools-tests.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
export XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache"
export NVIM_LOG_FILE="$test_root/nvim.log" PYTHONDONTWRITEBYTECODE=1
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/core.lua
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/layout.lua
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/icons.lua
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/registry.lua
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/query.lua
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/toggles.lua
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/toggle_actions.lua
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/providers.lua
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/performance.lua
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/refresh.lua
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/triggers.lua
for test in lazy lazy_explicit showkeys; do
  "${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin \
    -c "lua local ok, err = pcall(dofile, 'tests/$test.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa!
done
python3 tests/tui.py
python3 tests/advanced_tui.py
python3 tests/advanced_tui.py tests/showkeys_tui.lua
if [ -d "${THEME_TOOLS_DIR:-../theme-tools.nvim}" ]; then
  python3 tests/advanced_tui.py tests/theme_tui.lua
fi
stylua --check lua plugin tests
