#!/bin/bash
# QustahShindo tests: converts the hub, its raw files and the UI lib to Lua 5.3 and runs them in a mock Roblox.
#   tests/run.sh                 hub tests (map, menu, nofiles scenarios) + real-lib tests
#   tests/run.sh path/hub.lua    the same with a given QustahShindo.lua
#   BENCH=tests/bench.lua tests/run.sh    ESP timing instead of the tests (STRIPE_IMAGE=1: with getcustomasset)
# The other repos are looked for next to this one (override with HUB_SRC / LIB_SRC):
#   ../jewvjs-s-savhas-sh-sahsvsjebebs-wneve/QustahShindo.lua
#   ../79650/gwanjkcdsjawbdnjascdas-ui-lib/qustah-ui-lib/dist/qustah-ui-lib.lua  (or ../gwanjkcdsjawbdnjascdas-ui-lib/...)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$HERE/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HUB_SRC="${1:-${HUB_SRC:-$REPO/../jewvjs-s-savhas-sh-sahsvsjebebs-wneve/QustahShindo.lua}}"
if [ -z "${LIB_SRC:-}" ]; then
  for c in "$REPO/../79650/gwanjkcdsjawbdnjascdas-ui-lib" "$REPO/../gwanjkcdsjawbdnjascdas-ui-lib"; do
    [ -f "$c/qustah-ui-lib/dist/qustah-ui-lib.lua" ] && LIB_SRC="$c/qustah-ui-lib/dist/qustah-ui-lib.lua" && break
  done
fi
[ -f "$HUB_SRC" ] || { echo "hub not found: $HUB_SRC (give it as the first argument or HUB_SRC)"; exit 1; }

convert() { python3 "$HERE/luaparse.py" "$1" >/dev/null || { python3 "$HERE/luaparse.py" "$1"; exit 1; }; python3 "$HERE/transpile.py" "$1" "$2" || exit 1; }

convert "$HUB_SRC" "$TMP/hub53.lua"
# the raw files the hub downloads are served from this repo instead of HttpGet
convert "$REPO/rellauto" "$TMP/rell53.lua" && export RELL53="$TMP/rell53.lua"
convert "$REPO/shindo/esp.lua" "$TMP/esp53.lua" && export ESP53="$TMP/esp53.lua"
convert "$REPO/shindo/teleports.lua" "$TMP/teleports53.lua" && export TELEPORTS53="$TMP/teleports53.lua"

status=0
for sc in map menu nofiles; do
  texlua "$HERE/run.lua" "$TMP/hub53.lua" "$sc" || status=1
done
[ -n "${BENCH:-}" ] && exit $status
if [ -n "${LIB_SRC:-}" ] && [ -f "$LIB_SRC" ]; then
  convert "$LIB_SRC" "$TMP/lib53.lua"
  export LIB_ROOT="$(cd "$(dirname "$LIB_SRC")/../.." && pwd)" # (the repo: fonts and icon sheets are served from it)
  texlua "$HERE/lib_run.lua" "$TMP/lib53.lua" "$TMP/esp53.lua" || status=1
  python3 "$HERE/icons_check.py" "$HUB_SRC" "$LIB_ROOT/qustah-ui-lib" || status=1
else
  echo "[lib] skipped: qustah-ui-lib not found (set LIB_SRC)"
fi
exit $status
