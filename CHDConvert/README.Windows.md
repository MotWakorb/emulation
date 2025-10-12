# ROMs → CHD Converter (Windows / PowerShell)

A Windows PowerShell script to convert disc-based ROM archives and loose images into `.chd` using `7-Zip` and `chdman`. Mirrors the Linux/mac script’s behavior and options (PowerShell idioms).

> Supports Dreamcast, PS1/PS2, GameCube — archives (`.zip`, `.7z`) and images (`.cue`, `.gdi`, `.toc`, `.iso`, `.gcm`).

---

## Table of Contents

- [Requirements](#requirements)
- [Install](#install)
- [Quick Start](#quick-start)
- [Usage](#usage)
  - [Parameters](#parameters)
  - [Examples](#examples)
- [Notes](#notes)

---

## Requirements

- **7-Zip** (installed; `7z.exe` on PATH)
- **chdman** (from MAME) on PATH
- PowerShell 7+ recommended

---

## Install

1. Place `roms_to_chd.ps1` somewhere convenient (e.g., `C:\\Tools\\roms_to_chd.ps1`).
2. Unblock once if downloaded from the web:
   ```powershell
   Unblock-File C:\\Tools\\roms_to_chd.ps1
   ```
3. (Optional) Add folder to your PATH for easier invocation.

---

## Quick Start

Preview (no changes), recurse, 6 jobs:

```powershell
powershell -ExecutionPolicy Bypass -File C:\\Tools\\roms_to_chd.ps1 `
  -RomDir "D:\\ROMs\\Dreamcast" -Recurse -Jobs 6 -OnlyPlatform Dreamcast -DryRun
```

Run for real, overwrite existing CHDs, keep archives:

```powershell
powershell -ExecutionPolicy Bypass -File C:\\Tools\\roms_to_chd.ps1 `
  -RomDir "D:\\ROMs\\PS2" -Recurse -Jobs 8 -OnlyPlatform PS2 -Force -KeepArchives
```

---

## Usage

### Parameters

- `-RomDir <string>` (required): Root directory of ROMs
- `-OutDir <string>`: Output directory (mirrors input tree)
- `-LogDir <string>`: Per-title logs directory (default: `<RomDir>\\.chd_logs`)
- `-Recurse` (switch): Recurse into subfolders
- `-Jobs <int>`: Parallel workers (default: 4)
- `-DryRun` (switch): Print intentions only (no extract/convert/delete)
- `-Force` (switch): Overwrite existing `.chd`
- `-KeepArchives` (switch): Keep archives after successful conversion
- `-OnlyPlatform <Dreamcast|PS2|PSX|GC>`: Restrict processing by platform

### Examples

- Dreamcast preview:
  ```powershell
  .\\roms_to_chd.ps1 -RomDir "D:\\ROMs\\DC" -Recurse -Jobs 6 -OnlyPlatform Dreamcast -DryRun
  ```

- Mirror PS2 output tree:
  ```powershell
  .\\roms_to_chd.ps1 -RomDir "D:\\ROMs\\PS2" -OutDir "E:\\CHD\\PS2" -Recurse -Jobs 8 -OnlyPlatform PS2 -Force
  ```

---

## Notes

- `.cdi` is not supported by `chdman`; convert to `.gdi` or `.cue/.bin` first.
- If `7z.exe` or `chdman.exe` aren’t found, the script stops with a helpful error.
- Per-title logs are written to `<RomDir>\\.chd_logs` by default.
