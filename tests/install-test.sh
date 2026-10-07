#!/usr/bin/env bash
# End-to-end test of install-shim.sh in a throwaway Wine prefix, laid out like
# the release archive (script + source + prebuilt shim). Checks that:
#   - after install, the shim answers on every powershell.exe path,
#   - user.reg stays readable by Lutris (no duplicate key, no header without
#     timestamp), and the override survives Wine rewriting it and a reinstall,
#   - it warns about a Lutris game on this prefix overriding powershell.exe,
#   - the script refuses to run while a wineserver uses the prefix,
#   - --uninstall gives Wine's own powershell back.
#
# Usage: tests/install-test.sh [SHIM_EXE]   (default: dist/x64/powershell.exe)
# Needs wine and pgrep. Leaves ~/.wine alone.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SHIM_EXE="$(realpath "${1:-$REPO/dist/x64/powershell.exe}")"
WORK="$(mktemp -d)"
export WINEPREFIX="$WORK/prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml="
trap 'wineserver -k 2>/dev/null || true; rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir "$WORK/bundle"
cp "$REPO/install-shim.sh" "$REPO/powershell-shim-v2.c" "$WORK/bundle/"
cp "$SHIM_EXE" "$WORK/bundle/powershell.exe"
INSTALL="$WORK/bundle/install-shim.sh"
USER_REG="$WINEPREFIX/user.reg"

wineboot --init && wineserver -w

# expect_shim yes|no: is the shim what answers on every powershell.exe path?
# Runs from $WORK, so that no powershell.exe sits in the current directory.
expect_shim() {
  local exe out got
  for exe in powershell 'C:\windows\system32\powershell.exe' \
             'C:\windows\system32\WindowsPowerShell\v1.0\powershell.exe'; do
    out=$(cd "$WORK" && wine "$exe" -NoProfile -Command \
      "Get-CimInstance -ClassName Win32_LogicalDisk | Select-Object Caption, FreeSpace, Size" \
      2>/dev/null) || true
    if grep -Eq '^C:[[:space:]]+[0-9]+' <<<"$out"; then got=yes; else got=no; fi
    [ "$got" = "$1" ] || fail "shim=$got, expected $1, for $exe"
    echo "ok: shim=$got for $exe"
  done
  wineserver -w
}

# count PATTERN: number of user.reg lines matching PATTERN (case-insensitive)
count() { grep -ci "$1" "$USER_REG" || true; }

echo "== Before install"
expect_shim no

# check_user_reg: user.reg must stay readable by Lutris' parser: one
# DllOverrides key holding one powershell.exe value, and every key header
# followed by its timestamp.
check_user_reg() {
  [ "$(count '^\[Software\\\\Wine\\\\DllOverrides\]')" = 1 ] || fail "DllOverrides key missing or duplicated"
  [ "$(count '^"powershell.exe"="native"')" = 1 ] || fail "powershell.exe override missing or duplicated"
  if grep '^\[' "$USER_REG" | grep -v '\] [0-9]'; then fail "key header without timestamp"; fi
  echo "ok: user.reg well-formed"
}

echo "== Install into a prefix without a DllOverrides key"
sed -i '/^\[Software\\\\Wine\\\\DllOverrides\]/I,/^$/d' "$USER_REG"
"$INSTALL" "$WINEPREFIX"
check_user_reg
expect_shim yes

echo "== Reinstall into the existing key, after Wine rewrote user.reg"
wine reg add 'HKCU\Software\install-shim-test' /f >/dev/null 2>&1
wineserver -w
"$INSTALL" "$WINEPREFIX" >/dev/null
check_user_reg
expect_shim yes

echo "== Lutris: warns only for a game on this prefix with a non-native override"
lutris_game() {  # lutris_game FILE PREFIX OVERRIDE, laid out like a Lutris game config
  mkdir -p "$(dirname "$1")"
  printf 'game:\n  prefix: %s\nwine:\n  overrides:\n    powershell.exe: %s\n' "$2" "$3" > "$1"
}
lutris_game "$WORK/home/.config/lutris/games/this.yml" "$WINEPREFIX" disabled
lutris_game "$WORK/home/.config/lutris/games/other.yml" "$WORK" disabled
lutris_game "$WORK/home/.var/app/net.lutris.Lutris/data/lutris/games/ok.yml" "$WINEPREFIX" native
out=$(HOME="$WORK/home" "$INSTALL" "$WINEPREFIX")
grep -q 'this\.yml sets powershell\.exe=disabled' <<<"$out" || fail "no Lutris warning for this prefix"
if grep -qE 'other\.yml|ok\.yml' <<<"$out"; then fail "Lutris warning for another prefix or a native override"; fi
echo "ok: warned for this.yml only"

echo "== Refuses to run while a wineserver uses the prefix"
wineserver -p   # persistent server, as while the launcher runs
if "$INSTALL" "$WINEPREFIX" >/dev/null 2>&1; then fail "ran while a wineserver was up"; fi
echo "ok: refused"
wineserver -k
wineserver -w

echo "== Uninstall"
"$INSTALL" --uninstall "$WINEPREFIX"
expect_shim no
[ "$(count '^"powershell.exe"=')" = 0 ] || fail "override left in user.reg"
while IFS= read -r f; do
  if [[ "$f" == *.wine-stub ]] || ! grep -qaF 'Wine builtin DLL' "$f"; then fail "leftover $f"; fi
done < <(find "$WINEPREFIX/drive_c/windows" -iname 'powershell.exe*')
echo "ok: only Wine's own powershell.exe left"

echo "PASS"
