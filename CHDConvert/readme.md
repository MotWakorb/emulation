# ROMs → CHD Converter (Linux / macOS)

A Bash script (`roms_to_chd.sh`) to convert disc-based ROM archives and loose images into `.chd` using **7-Zip** (`7z`) and **chdman**. Mirrors the Windows PowerShell version’s logic and parameters.

> Supports Dreamcast, PSX/PS1, PS2, GameCube, and SegaCD — archives (`.7z`) and images (`.cue`, `.gdi`, `.toc`, `.iso`, `.gcm`).

---

## Requirements

- **7-Zip** (`7z`) on PATH
- **chdman** (from MAME) on PATH
- **bash** 4.x or newer
- Optional: `sudo` if ROM directories require elevated access

---

## Install

```bash
chmod +x roms_to_chd.sh
sudo mv roms_to_chd.sh /usr/local/bin/
```

---

## Quick Start

Dreamcast conversion, recurse, 6 workers:

```bash
sudo ./roms_to_chd.sh \
  --source "/data/emu/library/roms/dreamcast" \
  --platform dreamcast \
  --recurse \
  --max-parallel 6 \
  --force
```

PS2, mirror output, keep `.7z` archives:

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

### Dry-Run Example

Simulate extraction/conversion without writing any changes:

```bash
./roms_to_chd.sh --source "/data/emu/library/roms/psx" --platform psx --dry-run --recurse
```

---

## Usage

| Option | Description | Default |
|---|---|---|
| `--source` | Root directory containing `.7z` archives or disc images. | *(required)* |
| `--output` | Destination directory for `.chd` files. | Same as `--source` |
| `--platform` | Platform filter: `all`, `psx`, `ps2`, `dreamcast`, `gc`, `segacd`. | `all` |
| `--recurse` | Recurse into subdirectories. | Off |
| `--max-parallel` | Number of parallel workers. | 2 |
| `--force` | Overwrite existing `.chd`. | Off |
| `--keep-archives` | Keep `.7z` archives after successful conversion. | Off |
| `--keep-images` | Keep source `.iso`, `.cue`, `.gdi`, etc. | Off |
| `--dry-run` | Print actions without modifying files. | Off |
| `--chdman` | Path to `chdman`. | `chdman` |
| `--sevenzip` | Path to `7z`. | `7z` |
| `--log-dir` | Directory for log output. | `./logs` |

---

## Notes

- **Dry-run mode** shows what the script *would do* without performing extraction or conversion.
- **Logging:** Output written to `./logs/roms_to_chd.log`.
- **Cleanup:** Converted source images are deleted unless `--keep-images` is specified. Archives are deleted unless `--keep-archives` is set.
- **Parallelism:** Controlled via `--max-parallel` (default 2). Each worker runs its own `chdman` process.
- **Permissions:** Run with `sudo` if required for write access to mounted storage.

---

## Migration Notes

| Old Option | New Option | Reason |
|---|---|---|
| `--rom-dir` | `--source` | Clearer naming |
| `--out-dir` | `--output` | Clearer naming |
| `--jobs` | `--max-parallel` | Matches internal implementation |
| `--only-platform` | `--platform` | Simpler |
| `--dry-run` | `--dry-run` | Retained and fully functional |

Other updates:
- Logging unified to single file `./logs/roms_to_chd.log`.
- Functions aligned with PowerShell version for parity.
- Enhanced safety and verbosity with dry-run diagnostics.
