# ROMs → CHD Converter (Linux / macOS)

A Bash script (`roms_to_chd.sh`) to convert disc-based ROM archives and loose images into `.chd` using **7-Zip** (`7z`) and **chdman**. Mirrors the Windows PowerShell version’s behavior and options.

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

- **7-Zip** (`7z`) installed and on PATH
- **chdman** (from MAME) on PATH
- **bash** 4.x or newer (standard on most Linux/macOS systems)
- Optional: `sudo` access if your ROM directories require elevated privileges

---

## Install

1. Make the script executable:
   ```bash
   chmod +x roms_to_chd.sh
   ```
2. (Optional) Move it into your PATH:
   ```bash
   sudo mv roms_to_chd.sh /usr/local/bin/
   ```

---

## Quick Start

Dreamcast conversion, recurse, 6 workers, overwrite existing outputs:

```bash
sudo ./roms_to_chd.sh \
  --source "/data/emu/library/roms/dreamcast" \
  --platform dreamcast \
  --recurse \
  --max-parallel 6 \
  --force
```

PS2 conversion, mirror output tree, keep `.7z` archives after extraction:

```bash
sudo ./roms_to_chd.sh \
  --source "/data/emu/library/roms/ps2" \
  --output "/data/emu/library/chd/ps2" \
  --recurse \
  --max-parallel 8 \
  --platform ps2 \
  --keep-archives \
  --force
```

---

## Usage

### Parameters

| Option | Description | Default |
|---|---|---|
| `--source` | Root directory containing `.7z` archives or disc images. | *(required)* |
| `--output` | Destination directory for `.chd` files. | Same as `--source` |
| `--platform` | Filter by platform: `all`, `psx`, `ps2`, `dreamcast`, `gc`, `segacd`. | `all` |
| `--recurse` | Recurse into subdirectories. | Off |
| `--max-parallel` | Parallel workers (1–8). | 2 |
| `--force` | Overwrite existing `.chd` outputs. | Off |
| `--keep-archives` | Keep `.7z` archives after extraction. | Off |
| `--keep-images` | Keep source image files after conversion. | Off |
| `--chdman` | Path to `chdman` if not on PATH. | `chdman` |
| `--sevenzip` | Path to `7z` binary. | `7z` |
| `--log-dir` | Directory for logs. | `./logs` |

---

## Examples

- **Dreamcast conversion (recursive):**
  ```bash
  ./roms_to_chd.sh --source "/data/emu/library/roms/dreamcast" --platform dreamcast --recurse --max-parallel 6 --force
  ```

- **PS2 mirror conversion:**
  ```bash
  ./roms_to_chd.sh --source "/data/emu/library/roms/ps2" --output "/data/emu/library/chd/ps2" --recurse --max-parallel 8 --platform ps2 --force
  ```

- **GameCube keep source images:**
  ```bash
  ./roms_to_chd.sh --source "/data/emu/library/roms/gc" --platform gc --keep-images
  ```

- **Custom tool paths:**
  ```bash
  ./roms_to_chd.sh \
    --source "/data/emu/library/roms/psx" \
    --output "/data/emu/library/chd/psx" \
    --chdman "/usr/local/bin/chdman" \
    --sevenzip "/usr/bin/7z"
  ```

---

## Notes

- **Archive support:** Only `.7z` archives are automatically extracted. Convert `.zip` archives manually first.
- **Image formats:** `.cdi` is not supported by `chdman`; convert to `.gdi` or `.cue/.bin` first.
- **Logging:** A single combined log file is written to:
  ```
  ./logs/roms_to_chd.log
  ```
- **Cleanup:** By default, successfully converted image files are deleted. Use `--keep-images` to retain them. Use `--keep-archives` to retain `.7z` files.
- **Parallelism:** Controlled by `--max-parallel`; each worker runs one `chdman` process.
- **Permissions:** You can run as root (via `sudo`) if needed to write to mounted storage.

---

## Migration Notes (from older README/script)

| Old Option | New Option | Reason |
|---|---|---|
| `--rom-dir` | `--source` | Clearer, conventional naming |
| `--out-dir` | `--output` | Clearer, conventional naming |
| `--jobs` | `--max-parallel` | Matches implementation and PowerShell version |
| `--only-platform` | `--platform` | Simpler and consistent |
| `--dry-run` | *(removed)* | Feature removed in refactor |

Other updates:
- Log structure simplified to a single `roms_to_chd.log` file under `./logs`.
- Function names unified with the PowerShell version (`Test-CDImage`, `Test-DVDImage`, `Confirm-Directory`, `Test-PlatformMatch` equivalents implemented in Bash).
- Now fully mirrors analyzer-clean PowerShell logic, without PowerShell-specific constructs.