# 🧩 ROMs to CHD Conversion Script

**File:** `/usr/local/bin/roms_to_chd.sh`  
**Author:** Curt LeCaptain  
**Version:** 1.3  
**License:** MIT (Personal/Home-Lab Use)

---

## 🎯 Overview

This script automates conversion of ROM archives and disc images into modern **CHD (Compressed Hard Disk Image)** format — the standard for many emulation systems (PS1/PS2, GameCube, Dreamcast, etc).

**What’s new:**  
- 🎨 **Colored output** (TTY-aware; honors `NO_COLOR`).  
- 📝 **Per-title logs** in a dedicated logs directory.  
- 🗂️ Optional `OUT_DIR` to mirror ROM structure elsewhere.  
- 🧪 `DRYRUN=1` to preview actions.  
- 🧰 Cross-distro preflight for **Debian/Ubuntu** and **RPM-based** distros, with optional auto-install.

---

## 🧰 Requirements

Debian-based and RPM-based distributions are supported.

| Purpose | Debian/Ubuntu Package(s) | RPM Package(s) (Fedora/RHEL/Alma/Rocky/CentOS/openSUSE) |
|--------|---------------------------|----------------------------------------------------------|
| 7-Zip CLI | `7zip` *(preferred)* or `p7zip-full` | `7zip` *(preferred)* or `p7zip` |
| chdman | `mame-tools` *(or `mame`)* | `mame-tools` *(or `mame`)* |

---

## 🧪 Preflight Check (Dependencies Only)

```bash
# Show what’s missing (no conversions)
sudo CHECK_ONLY=1 /usr/local/bin/roms_to_chd.sh

# Optionally auto-install (uses apt/dnf/yum/zypper)
sudo AUTO_INSTALL=1 CHECK_ONLY=1 /usr/local/bin/roms_to_chd.sh
```

---

## ⚙️ Configuration (Environment Variables)

| Variable | Default | Description |
|-----------|----------|-------------|
| `ROM_DIR` | `/path/to/roms` | Root directory containing ROMs |
| `RECURSIVE` | `0` | Set `1` to scan subfolders recursively |
| `OUT_DIR` | *(empty)* | If set, CHDs are written here, mirroring `ROM_DIR` structure |
| `LOG_DIR` | `$ROM_DIR/.chd_logs` | Per-title logs are written here |
| `DRYRUN` | `0` | If `1`, prints actions without extracting/converting/deleting |
| `JOBS` | `min(nproc, 6)` | Number of parallel conversions |
| `CHECK_ONLY` | `0` | Run only dependency check then exit |
| `AUTO_INSTALL` | `0` | If `1`, attempt apt/dnf/yum/zypper installs |
| `SEVENZIP_BIN` | auto | Force use of `7zz` or `7z` manually |
| `NO_COLOR` | unset | If set, disables colored output |

---

## 🚀 Usage Examples

### Convert PS2 ROMs with per-title logs
```bash
sudo RECURSIVE=1 ROM_DIR="/path/to/roms/ps2" JOBS=6 /usr/local/bin/roms_to_chd.sh
# Logs: /path/to/roms/ps2/.chd_logs/<Game_Title>.log
```

### Convert to a separate OUT_DIR (mirrors structure)
```bash
sudo RECURSIVE=1 ROM_DIR="/path/to/roms" OUT_DIR="/srv/chd" JOBS=6 /usr/local/bin/roms_to_chd.sh
# Example: /path/to/roms/ps2/Foo/Foo.iso -> /srv/chd/ps2/Foo/Foo.chd
# Logs (by default): /path/to/roms/.chd_logs
```

### Dry-Run (no changes) with custom LOG_DIR
```bash
sudo DRYRUN=1 RECURSIVE=1 LOG_DIR="/var/log/chd" ROM_DIR="/path/to/roms" /usr/local/bin/roms_to_chd.sh
```

---

## 🧩 Supported Formats

| Input | Conversion | Example |
|--------|-------------|----------|
| DVD | `chdman createdvd` | `.iso`, `.gcm` |
| CD | `chdman createcd` | `.cue`, `.gdi`, `.toc` |
| Archives | extracted & converted | `.7z`, `.zip` |

Unsupported: `.wbfs`, `.cso`, `.nkit` (convert these back to `.iso` first).

---

## 📄 Per-Title Logs

For each title (archive or loose image), the script writes a log file that includes:
- Extraction command + output
- Conversion command + output
- Any cleanup actions (source deletions)
- Errors or skips

**Default location:** `$ROM_DIR/.chd_logs`  
**Customize:** set `LOG_DIR="/path/to/logs"`

---

## 🧱 Example Output
```
[2025-10-11 16:20:10] Preflight OK: using 7zz and chdman.
[2025-10-11 16:20:10] Per-title logs -> /path/to/roms/.chd_logs
[2025-10-11 16:20:10] Starting ROMs -> CHD in: /path/to/roms/ps2 (JOBS=6, RECURSIVE=1)
[2025-10-11 16:20:11] Extracting: Tekken 5 (USA).7z
[2025-10-11 16:20:42] Converting (DVD) Tekken 5 (USA) -> Tekken 5 (USA).chd
[2025-10-11 16:21:05] Success: Tekken 5 (USA).chd created. Cleaning archive.
[2025-10-11 16:21:05] Done.
```

---

## 🧹 Safety Features

- ✅ Only deletes source files if the `.chd` exists and is non-empty  
- 🔒 Creates isolated temporary folders per game  
- 🧩 Handles spaces, quotes, and symbols safely  
- 🧪 DRYRUN mode avoids any file changes

---

## 🧾 Troubleshooting

| Problem | Fix |
|----------|-----|
| `Extraction failed:` | Corrupt or unsupported 7z — test manually with `7zz x file.7z` |
| `command not found` | Install missing `7zip`/`p7zip` or `mame-tools`/`mame` |
| `No archives found` | Check `ROM_DIR` and use `RECURSIVE=1` if needed |
| `Permission denied` | Run with `sudo` |
| `CHD not created` | Ensure extracted files contain a valid `.iso` or `.cue` |

---

## 🏁 Quick Start

| Step | Command |
|------|----------|
| 1️⃣ Check requirements | `sudo CHECK_ONLY=1 /usr/local/bin/roms_to_chd.sh` |
| 2️⃣ (Optional) Auto-install | `sudo AUTO_INSTALL=1 CHECK_ONLY=1 /usr/local/bin/roms_to_chd.sh` |
| 3️⃣ Convert PS2 ROMs | `sudo RECURSIVE=1 ROM_DIR="/path/to/roms/ps2" JOBS=6 /usr/local/bin/roms_to_chd.sh` |
| 4️⃣ Write to OUT_DIR | `sudo OUT_DIR="/srv/chd" RECURSIVE=1 ROM_DIR="/path/to/roms" /usr/local/bin/roms_to_chd.sh` |
| 5️⃣ Preview (no changes) | `sudo DRYRUN=1 RECURSIVE=1 ROM_DIR="/path/to/roms" /usr/local/bin/roms_to_chd.sh` |

---

## 📜 License & Attribution

This script and documentation are provided **as-is** for personal/home-lab use.  
No warranty expressed or implied.

```
Copyright © 2025
Curt LeCaptain
```

Happy archiving and preservation! 🎮


---


---

## 🆘 Usage (`--help`)

```text
roms_to_chd.sh — Convert ROM archives & images to CHD with parallelism, per-title logs, and cross-distro preflight.

USAGE
  roms_to_chd.sh [--help]
  # Configuration is via environment variables.

ENV VARS
  ROM_DIR        Root directory containing ROMs (default: /path/to/roms)
  RECURSIVE      0=only ROM_DIR, 1=recurse subfolders (default: 0)
  OUT_DIR        If set, write CHDs under this path, mirroring ROM_DIR's structure
  LOG_DIR        Directory for per-title logs (default: $ROM_DIR/.chd_logs)
  DRYRUN         1=preview (no extraction/convert/delete), 0=execute (default: 0)
  JOBS           Parallel workers (default: min(nproc, 6))
  CHECK_ONLY     1=dependency check then exit (default: 0)
  AUTO_INSTALL   1=attempt to install missing deps (apt/dnf/yum/zypper) (default: 0)
  SEVENZIP_BIN   Force extractor: 7zz or 7z (auto-detected otherwise)
  NO_COLOR       If set, disables ANSI colors in output

EXAMPLES
  sudo CHECK_ONLY=1 roms_to_chd.sh
  sudo AUTO_INSTALL=1 CHECK_ONLY=1 roms_to_chd.sh
  sudo RECURSIVE=1 ROM_DIR="/path/to/roms/ps2" JOBS=6 roms_to_chd.sh
  sudo RECURSIVE=1 ROM_DIR="/path/to/roms" OUT_DIR="/srv/chd" JOBS=6 roms_to_chd.sh
  sudo DRYRUN=1 RECURSIVE=1 LOG_DIR="/var/log/chd" ROM_DIR="/path/to/roms" roms_to_chd.sh
```

## 💻 Installation via Git Clone

You can install this script directly from your Git repository for easy updates.

```bash
# Clone repository (example)
git clone https://github.com/<yourname>/roms-to-chd.git
cd roms-to-chd

# Install script system-wide
sudo install -m 0755 roms_to_chd.sh /usr/local/bin/roms_to_chd.sh
sudo install -m 0644 README.md /usr/local/share/docs/roms_to_chd/README.md

# Verify installation and options
roms_to_chd.sh --help
```

### 🆘 Built-in Help

You can display usage information and environment variables at any time:

```bash
roms_to_chd.sh --help
```

---
