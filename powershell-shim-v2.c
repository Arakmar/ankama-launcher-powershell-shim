/*
 * powershell.exe - standalone shim for the Ankama Launcher under Wine/Proton.
 *
 * The launcher (check-disk-space v3+) runs:
 *   C:\windows\system32\powershell.exe -NoProfile -Command
 *     "Get-CimInstance -ClassName Win32_LogicalDisk
 *      | Select-Object Caption, FreeSpace, Size"
 * Wine's builtin powershell is an empty stub -> NoMatchError
 * -> "Invalid path" (code 9001).
 *
 * Installed at that path with powershell.exe set to "native" (see
 * install-shim.sh), this shim detects the Win32_LogicalDisk query and prints
 * a table in the format check-disk-space parses. It gets the disk space
 * straight from the Win32 API (GetLogicalDriveStringsW +
 * GetDiskFreeSpaceExW): no wmic dependency, deterministic behavior.
 * Any other invocation -> silent exit 0.
 *
 * Build:
 *   x86_64-w64-mingw32-gcc -O2 -s -o powershell.exe powershell-shim-v2.c
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>

/* Case-insensitive search in the full command line. */
static int contains_ci(const wchar_t *hay, const wchar_t *needle) {
    if (!hay) return 0;
    size_t nl = wcslen(needle);
    for (const wchar_t *p = hay; *p; p++) {
        size_t i = 0;
        while (i < nl && p[i] &&
               towlower(p[i]) == towlower(needle[i])) i++;
        if (i == nl) return 1;
    }
    return 0;
}

int main(void) {
    /* Read the raw command line (handles quotes better than the
       argv/argc split done by the CRT). */
    const wchar_t *cmd = GetCommandLineW();

    if (!contains_ci(cmd, L"Win32_LogicalDisk")) {
        /* Not a disk query: silent success. */
        return 0;
    }

    /* Header in the PowerShell Format-Table layout check-disk-space expects. */
    printf("\r\nCaption  FreeSpace      Size\r\n");
    printf("-------  ---------      ----\r\n");

    wchar_t drives[512];
    DWORD n = GetLogicalDriveStringsW(511, drives);
    if (n == 0) {
        /* Worst case: empty but valid table. */
        fflush(stdout);
        return 0;
    }

    for (wchar_t *d = drives; *d; d += wcslen(d) + 1) {
        /* d is e.g. "C:\" */
        ULARGE_INTEGER freeAvail, total, totalFree;
        if (GetDiskFreeSpaceExW(d, &freeAvail, &total, &totalFree)) {
            /* Caption = letter + ':' (no backslash), as in Win32_LogicalDisk. */
            char caption[8];
            caption[0] = (char)d[0];
            caption[1] = ':';
            caption[2] = '\0';
            /* %-8s for the Caption column, values in decimal. */
            printf("%-8s %-14llu %llu\r\n",
                   caption,
                   (unsigned long long)freeAvail.QuadPart,
                   (unsigned long long)total.QuadPart);
        }
    }

    fflush(stdout);
    return 0;
}
