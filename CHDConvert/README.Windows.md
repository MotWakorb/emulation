# ROMs → CHD Converter (Windows / PowerShell)

A Windows PowerShell script to convert disc-based ROM archives and loose images into `.chd` using **7-Zip** and **chdman**. Mirrors the Linux/mac script’s behavior while following PowerShell best practices (approved verbs, analyzer-clean).

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

- **7-Zip** CLI (`7z.exe`) installed.
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

### Dry-Run Example

Preview all actions without extracting or converting:

```powershell
.\roms_to_chd.ps1 -SourceDir "D:\ROMs\PSX" -Platform PSX -DryRun -Recurse
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
| `DryRun` | `switch` | Simulate actions only (no extract/convert/delete). | Off |
| `ChdmanPath` | `string` | Path to `chdman` if not on PATH. | `chdman.exe` |
| `SevenZipPath` | `string` | Path to `7z.exe`. | `C:\Program Files\7-Zip\7z.exe` |
| `LogDir` | `string` | Directory for logs. | `<ScriptDir>\logs` |

---

## Notes

- **DryRun Mode:** The script prints what it *would* do—showing planned extractions, conversions, and deletions—without modifying anything.
- **Archive support:** Auto-extracts `.7z` archives. Extract `.zip` manually if present.
- **Image formats:** `.cdi` is not supported by `chdman`; convert to `.gdi` or `.cue/.bin` first.
- **Logging:** A single log file is written to `<ScriptDir>\logs\roms_to_chd.log`.
- **Cleanup behavior:** Successfully converted images are deleted unless `-KeepImages` is used. Archives are deleted unless `-KeepArchives` is specified.
- **Compatibility:** Works with PowerShell 5.1 and 7+. Analyzer-clean (no `$args` reassignments, approved verbs only).

---

## Migration Notes (from older README/script)

| Old Parameter | New Parameter | Reason |
|---|---|---|
| `-RomDir` | `-SourceDir` | Clearer naming |
| `-OutDir` | `-OutputDir` | Clearer naming |
| `-Jobs` | `-MaxParallel` | Matches implementation |
| `-OnlyPlatform` | `-Platform` | Simpler |
| `-DryRun` | `-DryRun` | Retained; now fully supported |

Other updates:
- Per-ROM logs replaced with single combined log file (`<ScriptDir>\logs\roms_to_chd.log`).
- Helper function names now use approved verbs (`Test-CDImage`, `Test-DVDImage`, etc.).
- Fully analyzer-clean, compatible across PowerShell 5.1 and 7+.