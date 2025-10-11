#!/usr/bin/env bash
# shellcheck disable=SC2155
set -euo pipefail

# ===== Config =====
# Override at runtime: ROM_DIR="/some/path" RECURSIVE=1 JOBS=6 ./roms_to_chd.sh
ROM_DIR="${ROM_DIR:-/path/to/roms}"
RECURSIVE="${RECURSIVE:-0}"                  # 0 = only this dir, 1 = recurse subdirs
OUT_DIR="${OUT_DIR:-}"                       # If set, write CHDs under this root, mirroring ROM_DIR structure
LOG_DIR="${LOG_DIR:-}"                       # If empty, defaults to "$ROM_DIR/.chd_logs"
DRYRUN="${DRYRUN:-0}"                        # 1 = print actions only (no extraction/convert/delete)
if command -v nproc >/dev/null 2>&1; then
  JOBS_DEFAULT="$(nproc)"; (( JOBS_DEFAULT>6 )) && JOBS_DEFAULT=6
else
  # macOS (Darwin) doesn't ship nproc; fall back to sysctl -n hw.ncpu
  if [[ "$(uname -s)" == "Darwin" ]]; then
    JOBS_DEFAULT="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
    if [[ "$JOBS_DEFAULT" -gt 6 ]]; then JOBS_DEFAULT=6; fi
  else
    JOBS_DEFAULT=4
  fi
fi
JOBS="${JOBS:-$JOBS_DEFAULT}"
CHECK_ONLY="${CHECK_ONLY:-0}"                # 1 = preflight then exit
AUTO_INSTALL="${AUTO_INSTALL:-0}"            # 1 = attempt to install missing packages automatically (apt/dnf/yum/zypper/brew)

# File-type mapping for chdman
DVD_EXTS=("iso" "gcm")                       # PS2/Wii/GameCube
CD_EXTS=("cue" "gdi" "toc")                  # PS1/PS2 CD, Dreamcast, etc.

# ===== Colors (TTY-aware; respect NO_COLOR) =====
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_INFO=$'\033[1;36m'     # cyan
  C_WARN=$'\033[1;33m'     # yellow
  C_ERR=$'\033[1;31m'      # red
  C_OK=$'\033[1;32m'       # green
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
else
  C_RESET=""; C_INFO=""; C_WARN=""; C_ERR=""; C_OK=""; C_BOLD=""; C_DIM="";
fi

timestamp() { date '+%F %T'; }
log()      { printf '[%s] %s%s%s\n' "$(timestamp)" "${C_INFO}" "$*" "${C_RESET}"; }
warn()     { printf '[%s] %s%s%s\n' "$(timestamp)" "${C_WARN}" "$*" "${C_RESET}"; }
ok()       { printf '[%s] %s%s%s\n' "$(timestamp)" "${C_OK}"  "$*" "${C_RESET}"; }
err()      { printf '[%s] %s%s%s\n' "$(timestamp)" "${C_ERR}" "$*" "${C_RESET}" >&2; }

script_name() { basename "$0"; }

print_help() {
  local name; name="$(script_name)"
  cat <<EOF
${C_BOLD}${name}${C_RESET} — Convert ROM archives & images to CHD with parallelism, per-title logs, and cross-platform preflight.

${C_BOLD}USAGE${C_RESET}
  ${name} [--help]
  # Configuration is via environment variables (examples below).

${C_BOLD}ENVIRONMENT VARIABLES${C_RESET}
  ${C_BOLD}ROM_DIR${C_RESET}        Root directory containing ROMs (default: /path/to/roms)
  ${C_BOLD}RECURSIVE${C_RESET}      0=only ROM_DIR, 1=recurse into subfolders (default: 0)
  ${C_BOLD}OUT_DIR${C_RESET}        If set, write CHDs under this path, mirroring ROM_DIR's structure
  ${C_BOLD}LOG_DIR${C_RESET}        Directory for per-title logs (default: \$ROM_DIR/.chd_logs)
  ${C_BOLD}DRYRUN${C_RESET}         1=preview (no extraction/convert/delete), 0=execute (default: 0)
  ${C_BOLD}JOBS${C_RESET}           Parallel workers (default: min(nproc/hw.ncpu, 6))
  ${C_BOLD}CHECK_ONLY${C_RESET}     1=dependency check then exit (default: 0)
  ${C_BOLD}AUTO_INSTALL${C_RESET}   1=attempt to install missing deps (apt/dnf/yum/zypper/brew) (default: 0)
  ${C_BOLD}SEVENZIP_BIN${C_RESET}   Force extractor: 7zz or 7z (auto-detected otherwise)
  ${C_BOLD}NO_COLOR${C_RESET}       If set, disables ANSI colors in output

${C_BOLD}EXAMPLES${C_RESET}
  # Check dependencies only (no conversion)
  CHECK_ONLY=1 ${name}

  # Auto-install missing deps (requires sudo on Linux)
  AUTO_INSTALL=1 CHECK_ONLY=1 ${name}

  # Convert PS2 ROMs with 6 workers
  RECURSIVE=1 ROM_DIR="/path/to/roms/ps2" JOBS=6 ${name}

  # Convert whole library, write CHDs to a separate folder (mirror structure)
  RECURSIVE=1 ROM_DIR="/path/to/roms" OUT_DIR="/srv/chd" JOBS=6 ${name}

  # Dry-run (no changes), log per-title to /var/log/chd
  DRYRUN=1 RECURSIVE=1 LOG_DIR="/var/log/chd" ROM_DIR="/path/to/roms" ${name}

${C_BOLD}SUPPORTED INPUTS${C_RESET}
  Archives: .7z, .zip
  CD images: .cue, .gdi, .toc
  DVD images: .iso, .gcm
  (Unsupported directly: .wbfs, .cso, .nkit — convert back to .iso first)

${C_BOLD}DEPENDENCIES${C_RESET}
  7-Zip CLI (7zz or 7z): package ${C_BOLD}7zip${C_RESET} (or ${C_BOLD}p7zip/p7zip-full${C_RESET})
  chdman: package ${C_BOLD}mame-tools${C_RESET} / ${C_BOLD}mame${C_RESET}
  ${C_DIM}The script auto-detects apt/dnf/yum/zypper on Linux and brew on macOS; can auto-install when AUTO_INSTALL=1.${C_RESET}
EOF
}

# Parse CLI flags (we primarily use env vars; only --help/-h is supported)
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  print_help
  exit 0
fi

# ===== Package manager detection (Linux + macOS Homebrew) =====
PKG_MGR=""
PKG_INSTALL_CMD=""
detect_pkg_mgr() {
  if command -v apt-get >/dev/null 2>&1; then
    PKG_MGR="apt"
    PKG_INSTALL_CMD="sudo apt update && sudo apt install -y"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
    PKG_INSTALL_CMD="sudo dnf install -y"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
    PKG_INSTALL_CMD="sudo yum install -y"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MGR="zypper"
    PKG_INSTALL_CMD="sudo zypper install -y"
  elif command -v brew >/dev/null 2>&1; then
    PKG_MGR="brew"
    PKG_INSTALL_CMD="brew install"
  else
    PKG_MGR="unknown"
  fi
}

have_pkg() {
  case "$PKG_MGR" in
    apt)
      dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -q "install ok installed" ;;
    dnf|yum|zypper)
      rpm -q "$1" >/dev/null 2>&1 ;;
    brew)
      brew list --versions "$1" >/dev/null 2>&1 ;;
    *)
      return 1 ;;
  esac
}

try_auto_install() {
  # $@: package names
  if (( AUTO_INSTALL )) && [[ -n "$PKG_INSTALL_CMD" ]]; then
    log "Attempting automatic install (${PKG_MGR}): $*"
    if [[ "$PKG_MGR" == "brew" ]]; then
      # brew does not use sudo and may have different package names; try sequentially
      for p in "$@"; do
        brew list --versions "$p" >/dev/null 2>&1 || brew install "$p" || true
      done
    else
      # shellcheck disable=SC2086
      eval "$PKG_INSTALL_CMD $*"
    fi
  else
    return 1
  fi
}

# ===== Preflight (multi-distro + macOS) =====
SEVENZIP_BIN="${SEVENZIP_BIN:-}"             # Will be set to 7zz or 7z

preflight() {
  detect_pkg_mgr
  if [[ "$PKG_MGR" == "unknown" ]]; then
    warn "Could not detect package manager. Proceeding only if binaries are present."
  else
    log "Detected package manager: $PKG_MGR"
  fi

  log "Preflight: checking required tools…"
  local need_pkgs=()
  local alt_pkgs=()

  # 7-Zip binary preference: 7zz (7zip) -> 7z (p7zip-full / p7zip)
  if [[ -z "${SEVENZIP_BIN}" ]]; then
    if command -v 7zz >/dev/null 2>&1; then
      SEVENZIP_BIN="7zz"
    elif command -v 7z >/dev/null 2>&1; then
      SEVENZIP_BIN="7z"
    fi
  fi

  if [[ -z "${SEVENZIP_BIN}" ]]; then
    case "$PKG_MGR" in
      apt)
        have_pkg 7zip       || need_pkgs+=("7zip")
        have_pkg p7zip-full || alt_pkgs+=("p7zip-full") ;;
      dnf|yum|zypper)
        have_pkg 7zip   || need_pkgs+=("7zip")
        have_pkg p7zip  || alt_pkgs+=("p7zip") ;;
      brew)
        have_pkg 7zip  || need_pkgs+=("7zip")
        have_pkg p7zip || alt_pkgs+=("p7zip") ;;
    esac
  fi

  # chdman provider
  if ! command -v chdman >/dev/null 2>&1; then
    case "$PKG_MGR" in
      apt)
        if ! have_pkg mame-tools && ! have_pkg mame; then
          need_pkgs+=("mame-tools")
        fi ;;
      dnf|yum|zypper)
        if ! have_pkg mame-tools && ! have_pkg mame; then
          need_pkgs+=("mame-tools"); alt_pkgs+=("mame")
        fi ;;
      brew)
        if ! have_pkg mame; then
          need_pkgs+=("mame")
        fi ;;
    esac
  fi

  # Attempt auto-install if requested
  if (( ${#need_pkgs[@]} )); then
    if (( AUTO_INSTALL )) && [[ -n "$PKG_INSTALL_CMD" ]]; then
      if ! try_auto_install "${need_pkgs[@]}"; then
        try_auto_install "${need_pkgs[@]}" "${alt_pkgs[@]}" || true
      fi
    fi
  fi

  # Re-resolve after possible install
  if [[ -z "${SEVENZIP_BIN}" ]]; then
    if command -v 7zz >/dev/null 2>&1; then SEVENZIP_BIN="7zz"; fi
    if [[ -z "${SEVENZIP_BIN}" ]] && command -v 7z >/dev/null 2>&1; then SEVENZIP_BIN="7z"; fi
  fi

  # Final checks
  local missing=0
  if [[ -z "${SEVENZIP_BIN}" ]]; then
    printf "\nMissing requirement: 7-Zip CLI (7zz or 7z).\n"
    case "$PKG_MGR" in
      apt)    printf "Install: sudo apt update && sudo apt install 7zip   # or: sudo apt install p7zip-full\n" ;;
      dnf)    printf "Install: sudo dnf install 7zip   # or: sudo dnf install p7zip\n" ;;
      yum)    printf "Install: sudo yum install 7zip   # or: sudo yum install p7zip\n" ;;
      zypper) printf "Install: sudo zypper install 7zip   # or: sudo zypper install p7zip\n" ;;
      brew)   printf "Install: brew install 7zip   # or: brew install p7zip\n" ;;
      *)      printf "Please install 7-Zip CLI (7zz/7z) via your package manager.\n" ;;
    esac
    missing=1
  fi

  if ! command -v chdman >/dev/null 2>&1; then
    printf "\nMissing requirement: chdman (from mame-tools or mame).\n"
    case "$PKG_MGR" in
      apt)    printf "Install: sudo apt update && sudo apt install mame-tools   # or: sudo apt install mame\n" ;;
      dnf)    printf "Install: sudo dnf install mame-tools   # or: sudo dnf install mame\n" ;;
      yum)    printf "Install: sudo yum install mame-tools   # or: sudo yum install mame\n" ;;
      zypper) printf "Install: sudo zypper install mame-tools   # or: sudo zypper install mame\n" ;;
      brew)   printf "Install: brew install mame\n" ;;
      *)      printf "Please install chdman via your package manager (package: mame-tools or mame).\n" ;;
    esac
    missing=1
  fi

  if (( missing )); then
    exit 2
  fi

  ok "Preflight OK: using ${SEVENZIP_BIN} and chdman."
  export SEVENZIP_BIN
  if (( CHECK_ONLY )); then
    warn "CHECK_ONLY=1 set; exiting after preflight."
    exit 0
  fi
}

# ===== Helpers =====
lower_ext() { local f="$1"; echo "${f##*.}" | tr '[:upper:]' '[:lower:]'; }
is_dvd_ext() { local e; e="$(lower_ext "$1")"; for x in "${DVD_EXTS[@]}"; do [[ "$e" == "$x" ]] && return 0; done; return 1; }
is_cd_ext()  { local e; e="$(lower_ext "$1")"; for x in "${CD_EXTS[@]}";  do [[ "$e" == "$x" ]] && return 0; done; return 1; }

sanitize_title() {
  # Turn a filename into a safe log filename
  local t="$1"
  t="${t// /_}"
  t="$(printf '%s' "$t" | tr -cd '[:alnum:]_.\-]')"
  printf '%s' "$t"
}

# Mirror ROM_DIR structure inside OUT_DIR. Prints destination dir to stdout.
dest_dir_for() {
  local src_dir="$1"
  if [[ -z "${OUT_DIR}" ]]; then
    printf '%s\n' "$src_dir"
    return 0
  fi
  local rel="$src_dir"
  case "$src_dir" in
    "$ROM_DIR"/*) rel="${src_dir#$ROM_DIR/}" ;;
    "$ROM_DIR")   rel="" ;;
    *)            rel="" ;;  # unknown base; drop into OUT_DIR root
  esac
  if [[ -n "$rel" ]]; then
    printf '%s\n' "${OUT_DIR%/}/$rel"
  else
    printf '%s\n' "${OUT_DIR%/}"
  fi
}

ensure_dir() {
  local d="$1"
  if (( DRYRUN )); then
    log "DRYRUN: would mkdir -p -- $d"
  else
    mkdir -p -- "$d"
  fi
}

# chd output path helper
chd_path_for() {
  local src_file="$1"
  local src_dir; src_dir="$(dirname "$src_file")"
  local base_noext; base_noext="$(basename "${src_file%.*}")"
  local outdir; outdir="$(dest_dir_for "$src_dir")"
  printf '%s/%s.chd\n' "$outdir" "$base_noext"
}

# Per-title log path
log_path_for() {
  local title="$1"
  local base="$(sanitize_title "$title")"
  printf '%s/%s.log\n' "$LOG_DIR" "$base"
}

run_and_log() {
  # $1: log file, rest: command...
  local logfile="$1"; shift
  if (( DRYRUN )); then
    log "DRYRUN: ${*}"
    printf '[%s] DRYRUN: %s\n' "$(timestamp)" "$*" >>"$logfile"
    return 0
  fi
  printf '[%s] RUN: %s\n' "$(timestamp)" "$*" >>"$logfile"
  # run command piping both stdout/stderr to tee
  set +e
  ( "$@" ) 2>&1 | tee -a "$logfile"
  local rc=${PIPESTATUS[0]}
  set -e
  return $rc
}

unsupported_image_notice() {
  local f="$1"
  case "$(lower_ext "$f")" in
    cso|wbfs|nkit|nkit.iso|nkit.gcm)
      warn "SKIP: '$f' is $(lower_ext "$f"); chdman cannot convert these directly. Convert back to ISO first." ;;
    *) warn "SKIP: Unsupported source for CHD: $f" ;;
  esac
}

# Parse a .cue/.toc to list referenced track files
cue_list_sources() {
  local cue="$1" dir; dir="$(dirname "$cue")"
  awk '
    BEGIN{IGNORECASE=1}
    $1=="FILE" {
      if ($2 ~ /^"/) {
        fname=$2
        for (i=3; i<=NF && $i !~ /"$/; i++) { fname=fname" "$i }
        if ($i ~ /"$/) fname=fname" "$i
        gsub(/^"/,"",fname); gsub(/"$/,"",fname)
        print fname
      } else { print $2 }
    }
  ' "$cue" | while IFS= read -r rel; do [[ -e "$dir/$rel" ]] && printf '%s\n' "$dir/$rel"; done
}

to_chd() {
  local input="$1" out="$2" logfile="$3"
  local outdir; outdir="$(dirname "$out")"
  ensure_dir "$outdir"
  if is_cd_ext "$input"; then
    run_and_log "$logfile" chdman createcd -i "$input" -o "$out"
  elif is_dvd_ext "$input"; then
    run_and_log "$logfile" chdman createdvd -i "$input" -o "$out"
  else
    unsupported_image_notice "$input"; return 2
  fi
}

safe_cleanup_sources() {
  local chd="$1"; shift
  local logfile="$1"; shift
  local sources=("$@")
  if (( DRYRUN )); then
    log "DRYRUN: would delete sources after CHD exists"
    printf '[%s] DRYRUN: would delete: %s\n' "$(timestamp)" "${sources[*]}" >>"$logfile"
    return 0
  fi
  if [[ -f "$chd" && -s "$chd" ]]; then
    for s in "${sources[@]}"; do
      if [[ -e "$s" ]]; then
        printf '[%s] DELETE: %s\n' "$(timestamp)" "$s" >>"$logfile"
        rm -f -- "$s"
      fi
    done
  fi
}

process_extracted_set() {
  local workdir="$1" basename_noext="$2" src_dir="$3" logfile="$4"
  local dest_dir; dest_dir="$(dest_dir_for "$src_dir")"
  ensure_dir "$dest_dir"
  local chd="${dest_dir}/${basename_noext}.chd"

  local desc
  desc="$(find "$workdir" -maxdepth 1 -type f \( -iname '*.cue' -o -iname '*.gdi' -o -iname '*.toc' \) | head -n1 || true)"
  if [[ -n "$desc" ]]; then
    log "Converting (CD) $basename_noext -> $(basename "$chd")"
    to_chd "$desc" "$chd" "$logfile"
    mapfile -t tracks < <(cue_list_sources "$desc" 2>/dev/null || true)
    safe_cleanup_sources "$chd" "$logfile" "$desc" "${tracks[@]}"
    return 0
  fi

  local dvd
  dvd="$(find "$workdir" -maxdepth 1 -type f \( -iname '*.iso' -o -iname '*.gcm' \) | head -n1 || true)"
  if [[ -n "$dvd" ]]; then
    log "Converting (DVD) $basename_noext -> $(basename "$chd")"
    to_chd "$dvd" "$chd" "$logfile"
    safe_cleanup_sources "$chd" "$logfile" "$dvd"
    return 0
  fi

  warn "No convertible image found for $basename_noext — skipping."
  return 2
}

process_archive() {
  local archive="$1" src_dir="$2"
  local fname="$(basename "$archive")"
  local basename_noext="${fname%.*}"
  local logfile="$(log_path_for "$basename_noext")"

  printf '%s\n%s\n\n' "Title: $basename_noext" "Source: $archive" >"$logfile"

  log "Extracting: $fname"
  if (( DRYRUN )); then
    printf '[%s] DRYRUN: would extract "%s"\n' "$(timestamp)" "$archive" >>"$logfile"
    return 0
  fi

  local workdir="$(mktemp -d --tmpdir="$src_dir" ".extract_${basename_noext}_XXXX")"
  run_and_log "$logfile" "$SEVENZIP_BIN" x -y -o"$workdir" -- "$archive" || {
    err "Extraction failed: $fname"
    printf '[%s] ERROR: extraction failed for %s\n' "$(timestamp)" "$fname" >>"$logfile"
    rm -rf -- "$workdir"; return 2
  }

  process_extracted_set "$workdir" "$basename_noext" "$src_dir" "$logfile" || {
    err "FAILED to find/convert content for $fname"
    printf '[%s] ERROR: convert step failed for %s\n' "$(timestamp)" "$fname" >>"$logfile"
    rm -rf -- "$workdir"; return 2
  }

  if [[ -s "$(dest_dir_for "$src_dir")/${basename_noext}.chd" ]]; then
    ok "Success: ${basename_noext}.chd created. Cleaning archive."
    printf '[%s] SUCCESS: created CHD\n' "$(timestamp)" >>"$logfile"
    safe_cleanup_sources "$(dest_dir_for "$src_dir")/${basename_noext}.chd" "$logfile" "$archive"
  else
    warn "CHD not created for $fname; leaving archive."
    printf '[%s] WARN: CHD not created; archive kept\n' "$(timestamp)" >>"$logfile"
  fi
  rm -rf -- "$workdir"
}

process_loose_single() {
  local f="$1"
  local stem="${f%.*}"
  local title="$(basename "$stem")"
  local logfile="$(log_path_for "$title")"
  printf '%s\n%s\n\n' "Title: $title" "Source: $f" >"$logfile"

  local chd="$(chd_path_for "$f")"

  if [[ -s "$chd" ]]; then
    warn "CHD already exists for $(basename "$f"); skipping."
    printf '[%s] SKIP: CHD already exists: %s\n' "$(timestamp)" "$chd" >>"$logfile"
    return 0
  fi

  if is_cd_ext "$f"; then
    log "Converting (CD) $(basename "$stem") -> $(basename "$chd")"
    to_chd "$f" "$chd" "$logfile"
    mapfile -t refs < <(cue_list_sources "$f" 2>/dev/null || true)
    safe_cleanup_sources "$chd" "$logfile" "$f" "${refs[@]}"
  elif is_dvd_ext "$f"; then
    log "Converting (DVD) $(basename "$stem") -> $(basename "$chd")"
    to_chd "$f" "$chd" "$logfile"
    safe_cleanup_sources "$chd" "$logfile" "$f"
  else
    unsupported_image_notice "$f"
    printf '[%s] WARN: unsupported image type\n' "$(timestamp)" >>"$logfile"
    return 2
  fi
}

# Worker entrypoints for xargs parallelism
if [[ "${1:-}" == "__proc_archive" ]]; then
  shift; process_archive "$@"; exit $?
elif [[ "${1:-}" == "__proc_loose" ]]; then
  shift; process_loose_single "$@"; exit $?
fi

# Corrected: accept ALL predicates and forward them to find safely.
gfind() {
  local args=("$@")
  if (( RECURSIVE )); then
    find "$ROM_DIR" "${args[@]}" -print0 2>/dev/null || true
  else
    find "$ROM_DIR" -maxdepth 1 "${args[@]}" -print0 2>/dev/null || true
  fi
}

main() {
  [[ -d "$ROM_DIR" ]] || { err "ROM_DIR does not exist: $ROM_DIR"; exit 1; }

  preflight   # resolves tools and exports SEVENZIP_BIN

  # Set up LOG_DIR default
  if [[ -z "$LOG_DIR" ]]; then
    LOG_DIR="$ROM_DIR/.chd_logs"
  fi
  ensure_dir "$LOG_DIR"
  log "Per-title logs -> $LOG_DIR"

  if [[ -n "$OUT_DIR" ]]; then
    log "Writing CHDs under OUT_DIR: $OUT_DIR (mirroring structure from ROM_DIR)"
    (( ! DRYRUN )) && mkdir -p -- "$OUT_DIR"
  fi
  (( DRYRUN )) && warn "DRYRUN is ON — no files will be extracted, converted, or deleted."

  log "Starting ROMs -> CHD in: $ROM_DIR  (JOBS=$JOBS, RECURSIVE=$RECURSIVE)"

  # ---- Parallel: archives first ----
  mapfile -d '' -t ARCHIVES < <( gfind -type f \( -iname '*.7z' -o -iname '*.zip' \) )
  log "Archives found: ${#ARCHIVES[@]}"
  if (( ${#ARCHIVES[@]} )); then
    printf '%s\0' "${ARCHIVES[@]}" | xargs -0 -I{} -P "$JOBS" bash -c '
      set -euo pipefail
      "'"$0"'" __proc_archive "$@" 
    ' _ {} "$(dirname "{}")"
  else
    warn "No archives found (.7z/.zip)."
  fi

  # ---- Parallel: loose images ----
  mapfile -d '' -t LOOSER_CD  < <( gfind -type f \( -iname '*.cue' -o -iname '*.gdi' -o -iname '*.toc' \) )
  log "CD-like images found: ${#LOOSER_CD[@]}"
  mapfile -d '' -t LOOSER_DVD < <( gfind -type f \( -iname '*.iso' -o -iname '*.gcm' \) )
  log "DVD-like images found: ${#LOOSER_DVD[@]}"

  if (( ${#LOOSER_CD[@]} )); then
    printf '%s\0' "${LOOSER_CD[@]}" | xargs -0 -I{} -P "$JOBS" bash -c '
      set -euo pipefail
      "'"$0"'" __proc_loose "$@" 
    ' _ {} 
  fi
  if (( ${#LOOSER_DVD[@]} )); then
    printf '%s\0' "${LOOSER_DVD[@]}" | xargs -0 -I{} -P "$JOBS" bash -c '
      set -euo pipefail
      "'"$0"'" __proc_loose "$@" 
    ' _ {}
  fi

  ok "Done."
}

main "$@"
