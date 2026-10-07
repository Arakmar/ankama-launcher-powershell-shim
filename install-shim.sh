#!/usr/bin/env bash
# Installs the powershell.exe shim into the Wine/Proton prefix used by the
# Ankama Launcher, and sets powershell.exe to "native" in the prefix registry:
# without that override Wine keeps running its builtin powershell, whatever
# file sits in its place.
#
# Usage: ./install-shim.sh [--uninstall] [PREFIX]
#   PREFIX defaults to ~/Games/dofus; drive_c is looked up in PREFIX and PREFIX/pfx.
#
# The launcher must be closed: wineserver keeps the registry in memory and
# writes it back on exit, which would drop the override.
set -euo pipefail

SHIM_DIR="$(cd "$(dirname "$0")" && pwd)"
SHIM="$SHIM_DIR/powershell.exe"

UNINSTALL=0
if [ "${1:-}" = "--uninstall" ]; then UNINSTALL=1; shift; fi
PREFIX="${1:-$HOME/Games/dofus}"

die() { echo "$*" >&2; exit 1; }

# Locate the Wine prefix (the directory holding drive_c and user.reg)
if   [ -d "$PREFIX/drive_c" ];     then WINEPREFIX="$PREFIX"
elif [ -d "$PREFIX/pfx/drive_c" ]; then WINEPREFIX="$PREFIX/pfx"
else die "drive_c not found under $PREFIX"
fi
WINDIR="$WINEPREFIX/drive_c/windows"
USER_REG="$WINEPREFIX/user.reg"
[ -d "$WINDIR/system32" ] || die "system32 not found: $WINDIR/system32"
[ -f "$USER_REG" ]        || die "user.reg not found: $USER_REG"

# Every place where Wine may put a powershell.exe
TARGET_DIRS=(system32 syswow64 system32/WindowsPowerShell/v1.0 syswow64/WindowsPowerShell/v1.0)

is_wine_builtin() { grep -qaF -e 'Wine builtin DLL' -e 'Wine placeholder DLL' "$1"; }

# True if a wineserver runs for this prefix. A wineserver keeps the prefix
# directory open for its whole life (its working directory, on the other hand,
# switches between the prefix and its server directory).
prefix_in_use() {
  local pid fd
  for pid in $(pgrep -u "$(id -u)" wineserver); do
    for fd in /proc/"$pid"/fd/*; do
      [ "$fd" -ef "$WINEPREFIX" ] && return 0
    done
  done
  return 1
}

# Drops any powershell.exe value from the DllOverrides key of user.reg
# (sed range: from the key header to the blank line that closes it)
remove_override() {
  sed -i '/^\[Software\\\\Wine\\\\DllOverrides\]/I,/^$/{/^"powershell\.exe"=/Id}' "$USER_REG"
}

prefix_in_use && die "A wineserver is using $WINEPREFIX: close the Ankama Launcher, then run this script again."

if [ "$UNINSTALL" = 1 ]; then
  for d in "${TARGET_DIRS[@]}"; do
    f="$WINDIR/$d/powershell.exe"
    if [ -e "$f.wine-stub" ] || [ -L "$f.wine-stub" ]; then
      mv -f "$f.wine-stub" "$f"
      echo "[*] Wine stub restored in $d"
    elif [ -f "$f" ] && ! is_wine_builtin "$f"; then
      rm -f "$f"
      echo "[*] Shim removed from $d"
    fi
  done
  remove_override
  echo "[*] powershell.exe override removed from $USER_REG"
  echo
  echo "[OK] Uninstalled."
  exit 0
fi

# 1. Build the shim, or use the prebuilt one next to this script
if command -v x86_64-w64-mingw32-gcc >/dev/null; then
  echo "[*] Building the shim..."
  x86_64-w64-mingw32-gcc -O2 -s -o "$SHIM" "$SHIM_DIR/powershell-shim-v2.c"
elif [ -f "$SHIM" ]; then
  echo "[*] mingw not found: using $SHIM"
else
  die "Install mingw-w64 (x86_64-w64-mingw32-gcc) or put a prebuilt powershell.exe next to this script"
fi

# 2. Put the shim wherever Wine has a powershell.exe. The original stub is moved,
#    not copied: in a Proton prefix it is a symlink into Proton itself, and
#    writing through it would overwrite Proton's own powershell.exe.
for d in "${TARGET_DIRS[@]}"; do
  [ -d "$WINDIR/$d" ] || continue
  f="$WINDIR/$d/powershell.exe"
  if [ -e "$f" ] && is_wine_builtin "$f"; then
    mv -f "$f" "$f.wine-stub"
  fi
  cp --remove-destination "$SHIM" "$f"
  echo "[*] Shim installed in $d"
done

# 3. Set powershell.exe to native, inside the existing DllOverrides key if any.
#    Lutris rewrites user.reg with its own parser, which rejects a key header
#    without the timestamp Wine puts after it, and keeps a single copy of a
#    key that appears twice.
remove_override
if grep -qi '^\[Software\\\\Wine\\\\DllOverrides\]' "$USER_REG"; then
  sed -i '/^\[Software\\\\Wine\\\\DllOverrides\]/Ia "powershell.exe"="native"' "$USER_REG"
else
  printf '\n[Software\\\\Wine\\\\DllOverrides] %s\n"powershell.exe"="native"\n' "$(date +%s)" >> "$USER_REG"
fi
echo "[*] powershell.exe=native override added to $USER_REG"

# Lutris passes its DLL overrides through WINEDLLOVERRIDES, which beats the
# registry: flag a game on this prefix whose powershell.exe override isn't native.
for f in ~/.config/lutris/games/*.yml ~/.local/share/lutris/games/*.yml \
         ~/.var/app/net.lutris.Lutris/{config,data}/lutris/games/*.yml; do
  [ -f "$f" ] || continue
  p=$(sed -n 's/^  prefix: //p' "$f")               # game.prefix
  v=$(sed -n 's/^    powershell\.exe: //p' "$f")    # wine.overrides.powershell.exe
  [[ -n "$p" && -n "$v" && "$v" != n* ]] || continue
  [[ "$p" -ef "$WINEPREFIX" || "$p" -ef "$PREFIX" ]] || continue
  echo "[!] $f sets powershell.exe=$v, which beats the registry:"
  echo "    set it to native in the game's Lutris options (Runner options > DLL overrides)."
done

echo
echo "[OK] Done. Restart the Ankama Launcher and retry the installation."
echo "     To undo: $0 --uninstall \"$PREFIX\""
