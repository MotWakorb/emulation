# 🎮 ROMs to CHD Converter (Linux/macOS)

_Version 1.2.0 — Flag-only CLI edition (synced with roms_to_chd.sh)_

Convert ROM archives and disc images into **CHD format** automatically with parallel processing, per-title logs, and intelligent cleanup.

---

## 🎯 Overview

This tool extracts `.7z`/`.zip` archives, converts supported disc images (`.cue`, `.iso`, `.gdi`, `.toc`, `.gcm`) to **CHD** via `chdman`, and removes redundant source files after successful conversion. It supports parallelism, automatic dependency installation, and full log tracking.

[↑ Back to top](#top)

---

## 🧰 Requirements

- 7-Zip (`7z` or `7zz`)
- `chdman` (from `mame-tools` or `mame`)
- GNU `find`, `xargs`, and `awk`
- Works on:
  - ✅ Debian, Ubuntu
  - ✅ Fedora, CentOS, RHEL
  - ✅ openSUSE, Arch
  - ✅ macOS (Homebrew)

---

## ⚙️ Command-Line Options (No Environment Variables)

| Option | Description |
|-------|-------------|
| `-d, --rom-dir DIR` | **Required.** Root directory containing ROMs |
| `-r, --recursive` | Recurse into subfolders |
| `-o, --out-dir DIR` | Write CHDs under this directory (mirrors rom-dir structure) |
| `-l, --log-dir DIR` | Per-title logs directory (default: `<rom-dir>/.chd_logs`) |
| `-j, --jobs N` | Parallel workers (default: `min(cpu,6)`) |
| `-n, --dry-run` | Preview actions; no extraction/convert/delete |
| `-a, --auto-install` | Try to install missing deps (apt/dnf/yum/zypper/brew) |
| `-c, --check-only` | Check dependencies and exit |
| `--7z BIN` | Force extractor binary (`7zz` or `7z`) |
| `-h, --help` | Show this help text |

[↑ Back to top](#top)

---

## 🚀 Usage Examples

### Quick Examples

```bash
# Dependency check
roms_to_chd.sh -d /path/to/roms -c

# Convert PS2 ROMs recursively
roms_to_chd.sh -d /path/to/roms/ps2 -r -j 6

# Write CHDs to a different drive
roms_to_chd.sh -d /path/to/roms -o /mnt/chd -r -j 6

# Dry-run: no extraction or conversion
roms_to_chd.sh -d /path/to/roms -r -n
```

### Advanced

```bash
# Preflight + auto-install if missing dependencies
roms_to_chd.sh -d /path/to/roms -c -a

# Full conversion with per-title logs
roms_to_chd.sh -d /path/to/roms -r -l /var/log/chd -j 8
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

- Verifies that CHDs were created successfully before deletion
- Keeps original files if conversion fails
- Generates per-title logs under `.chd_logs` (or custom `--log-dir`)
- Honors `--dry-run` mode for safe preview

---

## 🧾 Troubleshooting

- **Extraction failed:** Ensure 7-Zip (`7z` or `7zz`) is installed and usable
- **Missing `chdman`:** Install via your package manager (e.g. `sudo apt install mame-tools`)
- **Permission errors:** Run with `sudo` or ensure you own the directories
- **macOS users:** Install dependencies via `brew install 7zip mame`

[↑ Back to top](#top)

---

## 🪟 Windows Support

Windows users can use the PowerShell version for native behavior:

👉 [README_windows.md](./README_windows.md)

---

## 📜 License & Attribution

MIT License © 2025  
Created for cross-platform ROM archival workflows with CHD conversion automation.
