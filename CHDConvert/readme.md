<a name="top"></a>

# 🧩 ROMs to CHD Conversion Script (Linux / macOS Edition)

**File:** `roms_to_chd.sh`  
**Version:** 1.0  
**License:** MIT (Personal/Home-Lab Use)  
**Tested On:** Debian, Ubuntu, Fedora, openSUSE, macOS (Homebrew)

---

## 🎯 Overview

This script automates the conversion of ROM archives and disc images into modern **CHD (Compressed Hard Disk Image)** format — the preferred standard for many emulation systems (PS1/PS2, GameCube, Dreamcast, and more).

**Core Features:**
- 🗜️ Extract `.7z` and `.zip` archives  
- 💿 Convert `.iso`, `.gcm`, `.cue`, `.gdi`, `.toc` to `.chd`  
- ⚙️ Parallel conversion for multi-core CPUs  
- 🧹 Safe cleanup of verified source files  
- 🧾 Per-title logs  
- ✅ Auto-checks and installs dependencies (via `apt`, `dnf`, `yum`, `zypper`, or `brew`)

[↑ Back to top](#top)

---

## 🧰 Requirements

> 🟢 **Note:** Designed for Debian-based and RPM-based distributions, and macOS via Homebrew.

| Tool | Linux Install | macOS (brew) | Description |
|------|----------------|---------------|-------------|
| 7-Zip CLI | `sudo apt install 7zip` | `brew install 7zip` | Extract `.7z`/`.zip` archives |
| MAME Tools | `sudo apt install mame-tools` | `brew install mame` | Provides `chdman` for CHD creation |

Run a dependency check anytime:
```bash
sudo CHECK_ONLY=1 /usr/local/bin/roms_to_chd.sh
```

[↑ Back to top](#top)

---

## ⚙️ Configuration and Environment Variables

| Variable | Default | Description |
|-----------|----------|-------------|
| `ROM_DIR` | `/path/to/roms` | Root directory containing ROMs |
| `RECURSIVE` | `0` | Scan subfolders recursively (set to `1`) |
| `JOBS` | `min(nproc, 6)` | Parallel job count |
| `OUT_DIR` | *(none)* | Output folder for CHDs (mirrors folder structure) |
| `LOG_DIR` | `$ROM_DIR/.chd_logs` | Location of per-title logs |
| `DRYRUN` | `0` | Preview without changes |
| `AUTO_INSTALL` | `0` | Attempt dependency installation |
| `CHECK_ONLY` | `0` | Check dependencies then exit |

[↑ Back to top](#top)

---

## 🚀 Usage Examples

```bash
# Dependency check
sudo CHECK_ONLY=1 /usr/local/bin/roms_to_chd.sh

# Convert PS2 ROMs recursively
sudo RECURSIVE=1 ROM_DIR="/path/to/roms/ps2" JOBS=6 /usr/local/bin/roms_to_chd.sh

# Write CHDs to a different drive
sudo RECURSIVE=1 ROM_DIR="/path/to/roms" OUT_DIR="/mnt/chd" JOBS=6 /usr/local/bin/roms_to_chd.sh

# Dry-run: no extraction or conversion
sudo DRYRUN=1 RECURSIVE=1 ROM_DIR="/path/to/roms" /usr/local/bin/roms_to_chd.sh
```

[↑ Back to top](#top)

---

## 🧩 Supported Formats

| Type | Command | Extensions |
|------|----------|------------|
| DVD | `chdman createdvd` | `.iso`, `.gcm` |
| CD | `chdman createcd` | `.cue`, `.gdi`, `.toc` |
| Archive | Extract & convert | `.7z`, `.zip` |

Unsupported: `.wbfs`, `.cso`, `.nkit` — convert to `.iso` first.

[↑ Back to top](#top)

---

## 🧱 Example Output

```
[2025-10-11 16:20:10] Preflight OK: using 7zz and chdman.
[2025-10-11 16:20:10] Starting ROMs -> CHD in: /path/to/roms/ps2 (JOBS=6, RECURSIVE=1)
[2025-10-11 16:20:11] Extracting: Tekken 5 (USA).7z
[2025-10-11 16:20:42] Converting: Tekken 5 (USA) → Tekken 5 (USA).chd
[2025-10-11 16:21:05] Success: Tekken 5 (USA).chd created.
[2025-10-11 16:21:05] Done.
```

[↑ Back to top](#top)

---

## 🧹 Safety Features

- ✅ Deletes source files only when `.chd` exists and is valid  
- 🔒 Uses isolated temporary folders for each extraction  
- 🧩 Handles filenames safely (spaces, Unicode, quotes)  
- 🧾 Logs per game title in `$LOG_DIR`

[↑ Back to top](#top)

---

## 🧾 Troubleshooting

| Issue | Fix |
|-------|-----|
| `Extraction failed` | Verify archive integrity manually with `7zz x file.7z` |
| `No archives found` | Use `RECURSIVE=1` to include subfolders |
| `command not found` | Install missing tools with `AUTO_INSTALL=1` |
| `CHD not created` | Check extracted files for valid `.iso`/`.cue` |
| `Permission denied` | Run as `sudo` or adjust permissions |

[↑ Back to top](#top)

---

## 🧮 Advanced Notes

- Multi-core parallel conversion using `xargs -P`.  
- Cross-distro dependency detection: `apt`, `dnf`, `yum`, `zypper`, `brew`.  
- Optional `DRYRUN` and `OUT_DIR` for testing and organization.  
- Supports macOS through Homebrew.  

[↑ Back to top](#top)

---

## 💻 Installation

```bash
sudo install -m 0755 roms_to_chd.sh /usr/local/bin/roms_to_chd.sh
roms_to_chd.sh --help
```

[↑ Back to top](#top)

---

## 📦 Packaging and Cross-Platform Links

- Windows version available: [README_windows.md](README_windows.md)  
- Linux/macOS version maintained in: `/usr/local/share/docs/roms_to_chd/`  
- See `pkg/` directory for Chocolatey and WinGet manifests.

[↑ Back to top](#top)

---

## 📜 License & Attribution

This script and documentation are provided **as-is** for personal or home-lab use.  
No warranty expressed or implied.

```
Copyright © 2025
Project Maintainer
```

[↑ Back to top](#top)
