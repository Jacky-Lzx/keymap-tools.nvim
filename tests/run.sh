#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_root=$(mktemp -d "${TMPDIR:-/tmp}/keymap-tools-tests.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
export XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache"
export NVIM_LOG_FILE="$test_root/nvim.log" PYTHONDONTWRITEBYTECODE=1
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/core.lua
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/layout.lua
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/registry.lua
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/query.lua
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/providers.lua
"${NVIM_BIN:-nvim}" --headless -n -u NONE -i NONE --noplugin -l tests/performance.lua
python3 tests/tui.py
python3 tests/advanced_tui.py
stylua --check lua plugin tests
