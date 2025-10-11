# 🧩 ROMs to CHD Conversion Script

**File:** `/usr/local/bin/roms_to_chd.sh`  
**Author:** Curt LeCaptain  
**Version:** 1.0  
**License:** MIT (Personal/Home-Lab Use)

---

## 🎯 Overview

This script automates conversion of ROM archives and disc images into modern **CHD (Compressed Hard Disk Image)** format — the standard for many emulation systems (PS1/PS2, GameCube, Dreamcast, etc).

It performs:

- 🗜️ Extraction of `.7z` / `.zip` archives  
- 💿 Conversion of `.iso`, `.cue`, `.gdi`, `.gcm`, `.toc` images → `.chd`  
- 🧹 Automatic cleanup of verified source files  
- ⚙️ Parallel processing for multi-core systems  
- ✅ Dependency preflight (apt-based validation)

---

## 🧰 Requirements

> 🟢 **Note:** This script is designed for Debian-based Linux distributions (Ubuntu, Debian, Mint, etc.).

| Tool | Package | Description |
|------|----------|-------------|
| 7zz | 7zip | Official 7-Zip CLI |
| 7z | p7zip-full | Alternative extractor |
| chdman | mame-tools | Converts ISO/CUE → CHD |

The script checks these automatically and prints install commands if any are missing.

---

## 🧪 Preflight Check (Dependencies Only)

Run this first to ensure all tools are available:

```bash
sudo CHECK_ONLY=1 /usr/local/bin/roms_to_chd.sh
```

**Example output:**
```
[2025-10-11 16:20:10] Preflight OK: using 7zz and chdman.
CHECK_ONLY=1 set; exiting after preflight.
```

If anything’s missing:
```
Missing requirements detected:
  - 7zip
  - mame-tools

Install with:
  sudo apt update && sudo apt install 7zip mame-tools
```

---

## ⚙️ Configuration (Environment Variables)

| Variable | Default | Description |
|-----------|----------|-------------|
| `ROM_DIR` | `/path/to/roms` | Root directory containing ROMs |
| `RECURSIVE` | `0` | Set `1` to scan subfolders recursively |
| `JOBS` | `min(nproc, 6)` | Number of parallel conversions |
| `CHECK_ONLY` | `0` | Run only dependency check |
| `SEVENZIP_BIN` | auto | Force use of `7zz` or `7z` manually |

---

## 🚀 Usage Examples

### PlayStation 2
```bash
sudo RECURSIVE=1 ROM_DIR="/path/to/roms/ps2" JOBS=6 /usr/local/bin/roms_to_chd.sh
```

### GameCube
```bash
sudo RECURSIVE=1 ROM_DIR="/path/to/roms/gamecube" JOBS=6 /usr/local/bin/roms_to_chd.sh
```

### All Systems
```bash
sudo RECURSIVE=1 ROM_DIR="/path/to/roms" JOBS=6 /usr/local/bin/roms_to_chd.sh
```

> 💡 Tip: Use `JOBS=$(nproc)` for max speed on fast SSDs.

---

## 🧩 Supported Formats

| Input | Conversion | Example |
|--------|-------------|----------|
| DVD | `chdman createdvd` | `.iso`, `.gcm` |
| CD | `chdman createcd` | `.cue`, `.gdi`, `.toc` |
| Archives | extracted & converted | `.7z`, `.zip` |

Unsupported: `.wbfs`, `.cso`, `.nkit` (convert back to `.iso` first).

---

## 🧱 Example Output
```
[2025-10-11 16:20:10] Preflight OK: using 7zz and chdman.
[2025-10-11 16:20:10] Starting ROMs -> CHD in: /path/to/roms/ps2 (JOBS=6, RECURSIVE=1)
[2025-10-11 16:20:10] Archives found: 134
[2025-10-11 16:20:11] Extracting: Tekken 5 (USA).7z
[2025-10-11 16:20:42] Converting: Tekken 5 (USA) → Tekken 5 (USA).chd
[2025-10-11 16:21:05] Success: Tekken 5 (USA).chd created. Cleaning archive.
[2025-10-11 16:21:05] Done.
```

---

## 🧹 Safety Features

- ✅ Only deletes source files if the `.chd` exists and is non-empty  
- 🔒 Creates isolated temporary folders per game  
- 🧩 Handles spaces, quotes, and symbols safely  

---

## 🧾 Troubleshooting

| Problem | Fix |
|----------|-----|
| `Extraction failed:` | Corrupt or unsupported 7z — test manually with `7zz x file.7z` |
| `command not found` | Install missing `7zip` or `mame-tools` |
| `No archives found` | Check `ROM_DIR` and use `RECURSIVE=1` if needed |
| `Permission denied` | Run with `sudo` |
| `CHD not created` | Ensure extracted files contain a valid `.iso` or `.cue` |

---

## 🏁 Quick Start

| Step | Command |
|------|----------|
| 1️⃣ Check requirements | `sudo CHECK_ONLY=1 /usr/local/bin/roms_to_chd.sh` |
| 2️⃣ Convert PS2 ROMs | `sudo RECURSIVE=1 ROM_DIR="/path/to/roms/ps2" JOBS=6 /usr/local/bin/roms_to_chd.sh` |
| 3️⃣ Monitor | Watch terminal for `Converting` / `Success` |
| 4️⃣ Verify | `.chd` files appear beside sources |

---

## 🧮 Advanced Notes

- Parallelism: Uses `xargs -P` — stable and efficient.  
- Planned: `DRYRUN=1` and `OUT_DIR` support.  
- Extend: Modify `DVD_EXTS` / `CD_EXTS` arrays to support new systems.

---

## 📜 License & Attribution

This script and documentation are provided **as-is** for personal or home-lab use.  
No warranty expressed or implied.

```
Copyright © 2025
Curt LeCaptain
```

Happy archiving and preservation! 🎮
