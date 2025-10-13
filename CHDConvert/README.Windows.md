# ROMs → CHD Converter (Windows / PowerShell)

A Windows PowerShell script to convert disc-based ROM archives and loose images into `.chd` using **7‑Zip** and **chdman**. Mirrors the Linux/mac script’s behavior while following PowerShell best practices (approved verbs, analyzer‑clean).

> Supports Dreamcast, PSX/PS1, PS2, GameCube, and SegaCD — archives (`.7z`) and images (`.cue`, `.gdi`, `.toc`, `.iso`, `.gcm`).

---

## Table of Contents

- [Requirements](#requirements)
- [Install](#install)
- [Quick Start](#quick-start)
- [Usage](#usage)
  - [Parameters](#parameters)
  - [Examples](#examples)
- [Notes](#notes)
- [Migration Notes (from older README/script)](#migration-notes-from-older-readmescript)

---

## Requirements

- **7‑Zip** CLI (`7z.exe`) installed.
  - Default path used by the script: `C:\Program Files\7-Zip\7z.exe`
- **chdman** (from MAME) on PATH, or provide `-ChdmanPath`.
- **PowerShell 7+ recommended**, **Windows PowerShell 5.1 compatible**.

---

## Install

1. Place `roms_to_chd.ps1` somewhere convenient (e.g., `C:\Tools\roms_to_chd.ps1`).
2. Unblock once if downloaded from the web:
   ```powershell
   Unblock-File C:\Tools\roms_to_chd.ps1
   ```
3. (Optional) Add the folder to your PATH for easier invocation.

> **Tip:** If you have both PowerShell 5.1 and 7 installed, you can explicitly choose the host:
> - PS7: `pwsh -ExecutionPolicy Bypass -File ...`
> - PS5.1: `powershell -ExecutionPolicy Bypass -File ...`

---

## Quick Start

Dreamcast, recurse, 6 workers, overwrite existing outputs:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Tools\roms_to_chd.ps1 `
  -SourceDir "D:\ROMs\Dreamcast" -Platform Dreamcast -Recurse -MaxParallel 6 -Force
```

PS2, mirror output to another drive, keep `.7z` archives after extraction:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Tools\roms_to_chd.ps1 `
  -SourceDir "D:\ROMs\PS2" -OutputDir "E:\CHD\PS2" -Recurse -MaxParallel 8 -Platform PS2 -Force -KeepArchives
```

---

## Usage

### Parameters

| Parameter | Type | Description | Default |
|---|---|---|---|
| `SourceDir` | `string` (required) | Root directory containing `.7z` archives and/or disc images. | — |
| `OutputDir` | `string` | Where `.chd` files are written (mirrors input tree). | `SourceDir` |
| `Platform` | `enum` | `All`, `PSX`, `PS2`, `Dreamcast`, `GC`, `SegaCD` | `All` |
| `Recurse` | `switch` | Recurse into subfolders. | Off |
| `MaxParallel` | `int` | Parallel workers (1–8). | 2 |
| `Force` | `switch` | Overwrite existing `.chd`. | Off |
| `KeepArchives` | `switch` | Keep `.7z` archives after successful conversion. | Off |
| `KeepImages` | `switch` | Keep source images (`.iso/.cue/.gdi/.toc/.gcm`) after conversion. | Off |
| `ChdmanPath` | `string` | Path to `chdman` if not on PATH. | `chdman.exe` |
| `SevenZipPath` | `string` | Path to `7z.exe`. | `C:\Program Files\7-Zip\7z.exe` |
| `LogDir` | `string` | Directory for logs. | `<ScriptDir>\logs` |

### Examples

- **Dreamcast (all subfolders), overwrite outputs:**
  ```powershell
  .\roms_to_chd.ps1 -SourceDir "D:\ROMs\DC" -Platform Dreamcast -Recurse -MaxParallel 6 -Force
  ```

- **Mirror PS2 output tree to another drive:**
  ```powershell
  .\roms_to_chd.ps1 -SourceDir "D:\ROMs\PS2" -OutputDir "E:\CHD\PS2" -Recurse -MaxParallel 8 -Platform PS2 -Force
  ```

- **GameCube, keep original images:**
  ```powershell
  .\roms_to_chd.ps1 -SourceDir "D:\ROMs\GC" -Platform GC -KeepImages
  ```

- **Custom tool paths:**
  ```powershell
  .\roms_to_chd.ps1 `
    -SourceDir "D:\Temp\Imports" `
    -OutputDir "E:\Library\CHDs" `
    -ChdmanPath "C:\Tools\chdman.exe" `
    -SevenZipPath "C:\Program Files\7-Zip\7z.exe"
  ```

---

## Notes

- **Archive support:** This script auto‑extracts **`.7z`** archives. If you have `.zip` files, extract them first or re‑package to `.7z`.
- **Image formats:** `.cdi` is not supported by `chdman`; convert to `.gdi` or `.cue/.bin` first.
- **Logging:** A single log file is written to:
  ```
  <ScriptDir>\logs\roms_to_chd.log
  ```
- **Cleanup behavior:** By default, successfully converted **source images are deleted**; use `-KeepImages` to retain them. Archives are deleted unless `-KeepArchives` is specified.
- **Compatibility:** Runs on PowerShell 5.1 and 7+. The script avoids the null‑propagation operator and reserved variables so it’s analyzer‑clean.

---

## Migration Notes (from older README/script)

If you were using a previous version, note these changes:

| Old Parameter | New Parameter | Reason |
|---|---|---|
| `-RomDir` | `-SourceDir` | Clearer, conventional naming |
| `-OutDir` | `-OutputDir` | Clearer, conventional naming |
| `-Jobs` | `-MaxParallel` | Matches implementation (`SemaphoreSlim`) |
| `-OnlyPlatform` | `-Platform` | Simpler, consistent with other tools |
| `-DryRun` | *(removed)* | Feature removed in refactor |

Other updates:
- Per‑title log directory (`<RomDir>\.chd_logs`) replaced with **single log file** at `<ScriptDir>\logs\roms_to_chd.log`.
- Internal helper names now use **approved verbs**: `Test-CDImage`, `Test-DVDImage`, `Confirm-Directory`, `Test-PlatformMatch`.
- Script is **PSScriptAnalyzer‑clean** (no `$args` assignments, no unapproved verbs).