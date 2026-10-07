/*
 * powershell.exe shim for the Ankama Launcher under Wine/Proton.
 * Superseded by powershell-shim-v2.c, which does not depend on wmic.
 *
 * The launcher runs:
 *   powershell -NoProfile -Command "Get-CimInstance -ClassName Win32_LogicalDisk
 *                                   | Select-Object Caption, FreeSpace, Size"
 * Wine ships a stub powershell.exe that prints nothing -> check-disk-space
 * fails with NoMatchError -> "Invalid path".
 *
 * This shim:
 *   - if the command line mentions Win32_LogicalDisk -> runs wmic and
 *     reformats its output as a PowerShell Format-Table, which
 *     check-disk-space can parse.
 *   - otherwise -> silent exit 0 (enough for the launcher's other calls).
 *
 * Build:
 *   x86_64-w64-mingw32-gcc -O2 -s -o powershell.exe powershell-shim-v1.c
 */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static int contains_ci(const char *hay, const char *needle) {
    size_t nl = strlen(needle);
    for (const char *p = hay; *p; p++) {
        if (_strnicmp(p, needle, nl) == 0) return 1;
    }
    return 0;
}

int main(int argc, char **argv) {
    /* Rebuild the full command line to inspect it */
    char cmdline[8192] = {0};
    for (int i = 1; i < argc; i++) {
        strncat(cmdline, argv[i], sizeof(cmdline) - strlen(cmdline) - 2);
        strncat(cmdline, " ", sizeof(cmdline) - strlen(cmdline) - 2);
    }

    if (!contains_ci(cmdline, "Win32_LogicalDisk")) {
        /* Not a disk query: do nothing, silent success. */
        return 0;
    }

    /* Run the prefix's own wmic and capture its output. */
    FILE *fp = _popen("wmic logicaldisk get caption,freespace,size", "r");
    if (!fp) {
        /* Last resort: empty but valid table (headers only). */
        printf("Caption FreeSpace Size\r\n");
        return 0;
    }

    /* Header in the format check-disk-space expects. */
    printf("\r\nCaption  FreeSpace      Size\r\n");
    printf("-------  ---------      ----\r\n");

    char line[1024];
    int header_skipped = 0;
    while (fgets(line, sizeof(line), fp)) {
        /* wmic prints "Caption  FreeSpace  Size" first -> skip it */
        if (!header_skipped) {
            if (contains_ci(line, "Caption")) { header_skipped = 1; continue; }
        }
        /* Strip CR/LF and trailing whitespace */
        size_t len = strlen(line);
        while (len > 0 && (line[len-1] == '\n' || line[len-1] == '\r'
                           || line[len-1] == ' ' || line[len-1] == '\t')) {
            line[--len] = 0;
        }
        if (len == 0) continue;

        /* Parse the 3 fields: caption, freespace, size */
        char caption[64] = {0};
        char freespace[64] = {0};
        char size[64] = {0};
        if (sscanf(line, "%63s %63s %63s", caption, freespace, size) >= 3) {
            printf("%-8s %-14s %s\r\n", caption, freespace, size);
        } else if (sscanf(line, "%63s", caption) == 1) {
            /* Partial line (drive without media): skip it */
            continue;
        }
    }
    _pclose(fp);
    fflush(stdout);
    return 0;
}
