# 🪟 ROMs to CHD Converter (Windows / PowerShell)

_Version 1.2.0 — PowerShell edition (synced with roms_to_chd.ps1)_

Convert ROM archives and disc images into **CHD format** on Windows with PowerShell — includes per-title logs, parallel processing, and auto-dependency validation.

---

## 🎯 Overview

This PowerShell edition automates conversion of ROM archives and disc images (`.7z`, `.zip`, `.cue`, `.iso`, `.gdi`, `.toc`, `.gcm`) into **CHD format** using `chdman`.  
It runs natively on Windows, supports parallel execution, safe cleanup, and automatic dependency verification (with `winget` or `choco`).

[↑ Back to top](#top)

---

## 🧰 Requirements

| Component | Description |
|------------|--------------|
| `7-Zip` | CLI version (must be in PATH) |
| `chdman.exe` | From MAME or mame-tools |
| PowerShell 7+ | Recommended for full compatibility |
| Windows Package Manager | `winget` or Chocolatey (`choco`) |

---

## ⚙️ Parameters

> ℹ️ **Linux/macOS users:** The Bash edition now uses CLI flags only (no environment variables). See the Linux/macOS README for the flag list.

| Parameter | Description |
|-----------|-------------|
| `-RomDir` | **Required.** Root directory containing ROMs |
| `-Recursive` | Recurse into subfolders |
| `-OutDir` | Destination directory for CHDs (mirrors ROM dir structure) |
| `-LogDir` | Directory for per-title logs (default: `<RomDir>\.chd_logs`) |
| `-Jobs` | Number of parallel workers (default: auto-detect CPU cores) |
| `-DryRun` | Preview actions only; no extraction or conversion |
| `-AutoInstall` | Install missing dependencies (requires `winget` or `choco`) |
| `-CheckOnly` | Only check dependencies, do not convert |
| `-Help` | Show help information |

---

## 🚀 Usage Examples

### Quick Examples

```powershell
# Dependency check
.oms_to_chd.ps1 -RomDir "D:\Roms" -CheckOnly

# Convert PS2 ROMs recursively
.oms_to_chd.ps1 -RomDir "D:\Roms\PS2" -Recursive -Jobs 6

# Write CHDs to a different drive
.oms_to_chd.ps1 -RomDir "D:\Roms" -OutDir "E:\CHD" -Recursive -Jobs 6

# Dry-run mode (no conversion)
.oms_to_chd.ps1 -RomDir "D:\Roms" -Recursive -DryRun
```

### Advanced

```powershell
# Preflight with auto-install (using winget or choco)
.oms_to_chd.ps1 -RomDir "D:\Roms" -CheckOnly -AutoInstall

# Full conversion with custom logs path
.oms_to_chd.ps1 -RomDir "D:\Roms" -Recursive -Jobs 8 -LogDir "D:\Logs\CHD"
```

[↑ Back to top](#top)

---

## 🧩 Supported Formats

| Category | Extensions |
|-----------|-------------|
| **Archives** | `.7z`, `.zip` |
| **CD-Based** | `.cue`, `.gdi`, `.toc` |
| **DVD-Based** | `.iso`, `.gcm` |
| **Unsupported (must convert manually)** | `.wbfs`, `.cso`, `.nkit` |

---

## 🧹 Safety Features

- Keeps original files if CHD creation fails  
- Generates detailed per-title logs  
- Automatically validates `7z` and `chdman` presence  
- Supports preview mode (`-DryRun`) for safety

---

## 🧾 Troubleshooting

- **Missing 7-Zip:** Install via `winget install 7zip.7zip` or `choco install 7zip`
- **Missing chdman:** Install MAME or MAME tools (`winget install MAMEDev.MAME`)
- **Permission issues:** Run PowerShell as Administrator
- **Parallel jobs not working:** Ensure PowerShell 7+ (Core) is in use

[↑ Back to top](#top)

---

## 🐧 Linux/macOS Version

Prefer Bash? See the cross-platform version here:  
👉 [README.md](./README.md)

---

## 📜 License & Attribution

MIT License © 2025  
Created for Windows-based CHD conversion workflows in PowerShell.
