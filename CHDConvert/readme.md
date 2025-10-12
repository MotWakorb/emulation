# ROMs → CHD Converter

A fast, parallel script to convert disc-based ROM archives and loose images into `.chd` (MAME’s Compressed Hunks of Data) on Linux, Debian/Ubuntu, RHEL/CentOS/Fedora, openSUSE, and macOS (Homebrew).

> Works great for Dreamcast, PS1/PS2, GameCube, and any platform where your image can be represented as **CD** (`.cue`, `.gdi`, `.toc`) or **DVD** (`.iso`, `.gcm`). Archives (`.zip`, `.7z`) are supported too.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Install](#install)
- [Quick Start](#quick-start)
- [Usage](#usage)
  - [Options](#options)
  - [Platforms & Extensions](#platforms--extensions)
  - [Dry Run](#dry-run)
  - [Force Overwrite](#force-overwrite)
  - [Keeping Archives](#keeping-archives)
  - [Per-Title Logs](#per-title-logs)
  - [Parallelism](#parallelism)
- [Examples](#examples)
- [Exit Codes](#exit-codes)
- [Notes & Tips](#notes--tips)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Features

- **Archive support**: `.zip`, `.7z`
- **Image support**:
  - **CD**: `.cue`, `.gdi`, `.toc`
  - **DVD**: `.iso`, `.gcm`
- **Parallel** extraction & conversion (`--jobs N`)
- **Dry-run** mode (`--dry-run`) prints what *would* happen
- **Force** overwrite existing CHDs (`--force`)
- **Platform filter**: `--only-platform dreamcast|ps2|psx|gc`
- **Keep archives** after success (`--keep-archives`)
- **Per-title logs** in `.<rom-dir>/.chd_logs`
- Auto detection of package manager (apt/dnf/yum/zypper/brew); optional auto-install
- macOS supported via Homebrew

> **Not supported**: `.cdi` (Dreamcast DiscJuggler) — convert to CUE/BIN or GDI first.

---

## Requirements

- **7-Zip CLI**: `7z` or `7zz`
- **chdman** (from `mame` / `mame-tools`)
- Bash 4+

Install suggestions by distro:

- Debian/Ubuntu: `sudo apt install 7zip mame-tools` (or `p7zip-full`, `mame`)
- RHEL/CentOS/Fedora: `sudo dnf install 7zip mame-tools` (or `p7zip`, `mame`)
- openSUSE: `sudo zypper install 7zip mame-tools`
- macOS (Homebrew): `brew install 7zip mame`

---

## Install

Place the script on your system and make it executable:

```bash
sudo install -m 0755 roms_to_chd.sh /usr/local/bin/roms_to_chd.sh
```

> You can also run it in-place: `bash roms_to_chd.sh ...`

---

## Quick Start

Dreamcast conversion (recursive, 6 workers, preview only):

```bash
sudo /usr/local/bin/roms_to_chd.sh -d /path/to/roms/dc -r -j 6 --only-platform dreamcast --dry-run
```

Then run for real:

```bash
sudo /usr/local/bin/roms_to_chd.sh -d /path/to/roms/dc -r -j 6 --only-platform dreamcast
```

Mirror output to another tree and overwrite existing CHDs:

```bash
sudo /usr/local/bin/roms_to_chd.sh -d /path/to/roms/ps2 -o /path/to/output/ps2_chd -r -j 8 --only-platform ps2 --force
```

---

## Usage

```text
roms_to_chd.sh — Convert ROM archives & images to CHD (parallel, per-title logs)

Required:
  -d, --rom-dir DIR         Root directory containing ROMs

Options:
  -r, --recursive           Recurse into subfolders (default: off)
  -o, --out-dir DIR         Write CHDs under this dir (mirrors rom-dir)
  -l, --log-dir DIR         Per-title logs (default: <rom-dir>/.chd_logs)
  -j, --jobs N              Parallel workers (default: min(cpu,6))
  -n, --dry-run             Show actions only (no extract/convert/delete)
  -c, --check-only          Only check dependencies and exit
  -a, --auto-install        Attempt to install missing deps (apt/dnf/yum/zypper/brew)
      --7z BIN              Force extractor (7zz or 7z)

New controls:
  -f, --force               Overwrite existing .chd files
      --keep-archives       Keep archives after successful conversion
      --only-platform P     Limit to one platform: dreamcast | ps2 | psx | gc
                            (affects loose image filtering and extracted descriptors)
```

### Platforms & Extensions

| Platform   | CD Descriptors           | DVD Images     | Notes                                  |
|------------|--------------------------|----------------|----------------------------------------|
| Dreamcast  | `.gdi`, `.toc` (+ `.cue`*) | —              | `.cdi` not supported                   |
| PS1 (PSX)  | `.cue`                   | —              | —                                      |
| PS2        | —                        | `.iso`         | —                                      |
| GameCube   | —                        | `.gcm`, `.iso` | —                                      |

> `--only-platform` filters **loose images** and **extracted descriptors**. Archives are still scanned (the descriptor inside must match the platform to be processed).

### Dry Run

Use `--dry-run` to print planned actions (no extraction, conversion, or deletion):

```bash
roms_to_chd.sh -d /path/to/roms -r -j 6 --dry-run
```

### Force Overwrite

If a `.chd` already exists, add `--force` to overwrite it.

### Keeping Archives

By default, archives are deleted after a successful conversion. Keep them with `--keep-archives`.

### Per-Title Logs

All activity is written to `<rom-dir>/.chd_logs/<title>.log` by default. Use `--log-dir DIR` to change.

### Parallelism

Adjust `--jobs N` to balance CPU/I/O. Defaults to `min(cores,6)`.

---

## Examples

- Dreamcast, recurse, preview only:

  ```bash
  sudo roms_to_chd.sh -d /path/to/roms/dc -r -j 6 --only-platform dreamcast --dry-run
  ```

- PS2 to a mirrored output tree, overwrite any existing CHDs:

  ```bash
  sudo roms_to_chd.sh -d /path/to/roms/ps2 -o /path/to/output/ps2_chd -r -j 8 --only-platform ps2 --force
  ```

- Convert all supported platforms, keep original archives:

  ```bash
  sudo roms_to_chd.sh -d /path/to/roms -r -j 6 --keep-archives
  ```

---

## Exit Codes

- `0` — success
- `2` — usage error or missing dependency
- Other — propagated tool failures (7z/chdman)

---

## Notes & Tips

- `.cdi` (Dreamcast) isn’t supported by `chdman`; convert to `.gdi` or `.cue/.bin` first.
- Already-converted titles are skipped unless `--force` is used.
- To re-process a single title, delete its existing `.chd` (or use `--force`).

---

## Troubleshooting

- **Dry-run extracts files**: update to the latest script; dry-run is argument-driven for workers and should never extract/convert.
- **“file already exists”**: use `--force` to overwrite, or delete the existing `.chd`.
- **7z / chdman missing**: install per your distro (see [Requirements](#requirements)).
- **Weird parsing errors**: ensure the file has Unix line-endings (`sed -i 's/\r$//' roms_to_chd.sh'`) and executable bit set.

---

## License

MIT
