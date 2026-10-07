# powershell.exe shim for the Ankama Launcher on Wine/Proton

Fixes the "invalid path" error (code 9001, *Chemin invalide* in French) that the
Ankama Launcher shows when it installs or updates Dofus under Wine, Proton or
Lutris.

## Why

To check the free disk space, the launcher uses the
[check-disk-space](https://www.npmjs.com/package/check-disk-space) module, which
runs:

```
powershell -NoProfile -Command "Get-CimInstance -ClassName Win32_LogicalDisk | Select-Object Caption, FreeSpace, Size"
```

Wine's `powershell.exe` is a stub that prints nothing, so the launcher finds no
disk at all and reports the install path as invalid.

This project puts a tiny `powershell.exe` in your Wine prefix instead. It answers
that one query with the table PowerShell would print, computed from the Win32
API, and exits silently on any other command, like Wine's stub.

## Install

Close the Ankama Launcher first: the installer refuses to run while Wine is
using the prefix.

### From a release (no compiler needed)

1. Download `ankama-launcher-powershell-shim-<version>.tar.gz` from the
   [Releases page](https://github.com/Arakmar/ankama-launcher-powershell-shim/releases),
   and optionally `SHA256SUMS` to check it:

   ```sh
   sha256sum -c --ignore-missing SHA256SUMS
   ```

2. Extract it and run the installer with the path of your Wine prefix
   (see [Finding your Wine prefix](#finding-your-wine-prefix)):

   ```sh
   tar xzf ankama-launcher-powershell-shim-<version>.tar.gz
   cd ankama-launcher-powershell-shim-<version>
   ./install-shim.sh ~/Games/dofus
   ```

3. Start the launcher and install or update the game again.

### Building it yourself

All you need is the MinGW-w64 cross-compiler:

| Distribution                 | Command                                  |
|------------------------------|------------------------------------------|
| Arch Linux, CachyOS, Manjaro | `sudo pacman -S mingw-w64-gcc`           |
| Debian, Ubuntu, Linux Mint   | `sudo apt install gcc-mingw-w64-x86-64`  |
| Fedora                       | `sudo dnf install mingw64-gcc`           |

Then get the sources and run the installer, which builds the shim itself:

```sh
git clone https://github.com/Arakmar/ankama-launcher-powershell-shim.git
cd ankama-launcher-powershell-shim
./install-shim.sh ~/Games/dofus
```

Whenever `x86_64-w64-mingw32-gcc` is available, `install-shim.sh` rebuilds
`powershell.exe` from `powershell-shim-v2.c`. Without it, the script uses the
`powershell.exe` found next to it.

To build the binary on one machine and install it on another one (a Steam Deck,
for instance), build it by hand:

```sh
x86_64-w64-mingw32-gcc -O2 -s -o powershell.exe powershell-shim-v2.c
```

then copy `install-shim.sh`, `powershell-shim-v2.c` and that `powershell.exe`
to the same directory on the other machine, and run the installer there. The
source is only used if that machine has MinGW too.

### Finding your Wine prefix

Pass the directory that contains `drive_c`. For Steam/Proton, where the prefix
lives in a `pfx` subdirectory, its parent works too. The default is
`~/Games/dofus`.

- **Lutris**: right-click the game > *Configure* > *Game options* > *Wine prefix*
- **Steam (Proton)**: `~/.local/share/Steam/steamapps/compatdata/<app id>`
- **Bottles**: `~/.local/share/bottles/bottles/<bottle>`, or for the Flatpak
  `~/.var/app/com.usebottles.bottles/data/bottles/bottles/<bottle>`
- **Plain Wine**: `~/.wine`, or the `WINEPREFIX` you use

### What the installer does

- It copies the shim over every `powershell.exe` Wine may run from the prefix:
  `system32`, `syswow64` and their `WindowsPowerShell\v1.0` subdirectories.
  Wine's own files are moved aside as `powershell.exe.wine-stub`.
- It sets `powershell.exe` to `native` under `HKCU\Software\Wine\DllOverrides`
  in the prefix's `user.reg`. Without this override, Wine keeps running its
  builtin powershell for `system32\powershell.exe`, whatever file is there.
- It warns you if a Lutris game using this prefix overrides `powershell.exe`
  with anything other than `native`. Lutris passes its overrides through
  `WINEDLLOVERRIDES`, which takes precedence over the registry, so fix it in the
  game's *Runner options* > *DLL overrides*.

## Uninstall

With the launcher closed:

```sh
./install-shim.sh --uninstall ~/Games/dofus
```

This puts Wine's original `powershell.exe` files back and removes the override.

## Manual install

If you would rather not run the script:

1. Copy the shim as `powershell.exe` to both
   `drive_c/windows/system32/` and `drive_c/windows/system32/WindowsPowerShell/v1.0/`,
   plus the same two places under `syswow64` if that directory exists. Create
   the file if it is missing. Move any existing `powershell.exe` aside first
   instead of copying over it: in Proton prefixes it can be a symlink into
   Proton itself, and writing through it would modify Proton's own copy.
2. With the launcher closed, set the override in one of these ways:
   - in Lutris: *Configure* > *Runner options* > *DLL overrides*, add
     `powershell.exe` with the value `native`;
   - in the registry, using the same Wine or Proton build that runs the game:

     ```sh
     WINEPREFIX=~/Games/dofus wine reg add 'HKCU\Software\Wine\DllOverrides' /v powershell.exe /d native /f
     ```

Releases also provide the bare binaries: use `powershell-x64.exe`, renamed to
`powershell.exe`. The Ankama Launcher needs a 64-bit prefix, and
`powershell-x86.exe` is only useful in 32-bit ones.

## Troubleshooting

- **"A wineserver is using ..."**: the launcher, or another program from the
  same prefix, is still running. Close it, or stop it with
  `WINEPREFIX=<prefix> wineserver -k` using the game's Wine build.
- **The error came back after a Wine or Proton update**: run the installer
  again.
- **Checking that the shim answers**: with the Wine or Proton build that runs
  the game, since running another version on a prefix can upgrade it:

  ```sh
  WINEPREFIX=~/Games/dofus wine powershell -NoProfile -Command "Get-CimInstance -ClassName Win32_LogicalDisk | Select-Object Caption, FreeSpace, Size"
  ```

  It should print a `Caption FreeSpace Size` table with a `C:` line. If it prints
  nothing, Wine is still running its builtin powershell: check the override.

## Development

| Path                     | Content                                                    |
|--------------------------|------------------------------------------------------------|
| `powershell-shim-v2.c`   | The shim, based on the Win32 API                           |
| `powershell-shim-v1.c`   | Previous version, which parsed `wmic` output; kept for reference |
| `install-shim.sh`        | Installer and uninstaller                                  |
| `tests/install-test.sh`  | End-to-end test of the installer in a throwaway prefix     |

The test needs `wine` and `pgrep`, and leaves `~/.wine` alone:

```sh
mkdir -p dist/x64
x86_64-w64-mingw32-gcc -O2 -s -Wall -o dist/x64/powershell.exe powershell-shim-v2.c
tests/install-test.sh dist/x64/powershell.exe
```

GitHub Actions (`.github/workflows/build.yml`) and GitLab CI (`.gitlab-ci.yml`)
build the x64 and x86 binaries and run the shim and installer tests under Wine.
On a version tag, they also publish a release with the archive and the binaries.

## License

[MIT](LICENSE)
