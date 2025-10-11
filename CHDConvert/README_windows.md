# ROMs to CHD (Windows, PowerShell)

**Script:** `roms_to_chd.ps1`

## Prereqs
- **7-Zip CLI** (`7zz.exe` or `7z.exe`) — use **winget**: `winget install 7zip.7zip` (or **choco**: `choco install 7zip`)
- **MAME (chdman.exe)** — `winget install MAMEDev.MAME` (or `choco install mame`)

> The script can attempt installation automatically when you pass `-AutoInstall` (if `winget` or `choco` is available).

## Examples
```powershell
# Dependency check only
.\roms_to_chd.ps1 -CheckOnly

# Convert PS2 ROMs recursively with 6 workers
.\roms_to_chd.ps1 -RomDir 'D:\Roms\ps2' -Recursive -Jobs 6

# Convert whole library to a separate drive, mirroring structure
.\roms_to_chd.ps1 -RomDir 'D:\Roms' -OutDir 'E:\CHD' -Recursive

# Dry-run with custom log folder
.\roms_to_chd.ps1 -DryRun -RomDir 'D:\Roms' -Recursive -LogDir 'D:\logs\chd'
```

## Notes
- Per-title logs are written to `"$RomDir\.chd_logs"` by default (override with `-LogDir`).
- Colored output works in modern terminals; set `NO_COLOR=1` to disable ANSI.
- Supports PowerShell 7+ parallelism (`ForEach-Object -Parallel`) and falling back to `Start-Job`.
