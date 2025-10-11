#!/usr/bin/env bash
set -euo pipefail

# ===== Config =====
# Override at runtime: ROM_DIR="/some/path" RECURSIVE=1 JOBS=6 ./roms_to_chd.sh
ROM_DIR="${ROM_DIR:-/path/to/roms}"          # <-- generic default path
RECURSIVE="${RECURSIVE:-0}"                  # 0 = only this dir, 1 = recurse subdirs
if command -v nproc >/dev/null 2>&1; then
  JOBS_DEFAULT="$(nproc)"; (( JOBS_DEFAULT>6 )) && JOBS_DEFAULT=6
else
  JOBS_DEFAULT=4
fi
JOBS="${JOBS:-$JOBS_DEFAULT}"
CHECK_ONLY="${CHECK_ONLY:-0}"                # 1 = preflight then exit

# File-type mapping for chdman
DVD_EXTS=("iso" "gcm")                       # PS2/Wii/GameCube
CD_EXTS=("cue" "gdi" "toc")                  # PS1/PS2 CD, Dreamcast, etc.

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }

# ===== APT-aware preflight =====
SEVENZIP_BIN="${SEVENZIP_BIN:-}"             # Will be set to 7zz or 7z
have_pkg() { dpkg-query -W -f='${Status}\n' "$1" 2>/dev/null | grep -q "install ok installed"; }

preflight() {
  log "Preflight: checking required tools and apt packages…"
  local need_pkgs=()

  # Pick 7zip binary
  if [[ -z "${SEVENZIP_BIN}" ]]; then
    if command -v 7zz >/dev/null 2>&1; then
      SEVENZIP_BIN="7zz"
    elif command -v 7z >/dev/null 2>&1; then
      SEVENZIP_BIN="7z"
    else
      have_pkg 7zip       || need_pkgs+=("7zip")
      have_pkg p7zip-full || need_pkgs+=("p7zip-full")
    fi
  fi

  # chdman
  if ! command -v chdman >/dev/null 2>&1; then
    if ! have_pkg mame-tools && ! have_pkg mame; then
      need_pkgs+=("mame-tools")
    fi
  fi

  if (( ${#need_pkgs[@]} )); then
    echo
    echo "Missing requirements detected:"
    for p in "${need_pkgs[@]}"; do echo "  - $p"; done
    echo
    echo "Install with:"
    echo "  sudo apt update && sudo apt install ${need_pkgs[*]}"
    echo
    exit 2
  fi

  # Final resolve in case packages were already installed
  if [[ -z "${SEVENZIP_BIN}" ]]; then
    if command -v 7zz >/dev/null 2>&1; then SEVENZIP_BIN="7zz"; fi
    if [[ -z "${SEVENZIP_BIN}" ]] && command -v 7z >/dev/null 2>&1; then SEVENZIP_BIN="7z"; fi
  fi
  if [[ -z "${SEVENZIP_BIN}" ]]; then
    echo "ERROR: Could not locate 7zz or 7z." >&2
    exit 2
  fi
  if ! command -v chdman >/dev/null 2>&1; then
    echo "ERROR: chdman not found. Install package 'mame-tools'." >&2
    exit 2
  fi

  log "Preflight OK: using ${SEVENZIP_BIN} and chdman."
  export SEVENZIP_BIN   # ensure workers spawned by xargs inherit this
  if (( CHECK_ONLY )); then
    log "CHECK_ONLY=1 set; exiting after preflight."
    exit 0
  fi
}

# ===== Helpers for conversion logic =====
lower_ext() { local f="$1"; echo "${f##*.}" | tr '[:upper:]' '[:lower:]'; }
is_dvd_ext() { local e; e="$(lower_ext "$1")"; for x in "${DVD_EXTS[@]}"; do [[ "$e" == "$x" ]] && return 0; done; return 1; }
is_cd_ext()  { local e; e="$(lower_ext "$1")"; for x in "${CD_EXTS[@]}";  do [[ "$e" == "$x" ]] && return 0; done; return 1; }

unsupported_image_notice() {
  local f="$1"
  case "$(lower_ext "$f")" in
    cso|wbfs|nkit|nkit.iso|nkit.gcm)
      echo "SKIP: '$f' is $(lower_ext "$f"); chdman cannot convert these directly. Convert back to ISO first." >&2 ;;
    *) echo "SKIP: Unsupported source for CHD: $f" >&2 ;;
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
  local input="$1" out="$2"
  if is_cd_ext "$input"; then
    chdman createcd -i "$input" -o "$out"
  elif is_dvd_ext "$input"; then
    chdman createdvd -i "$input" -o "$out"
  else
    unsupported_image_notice "$input"; return 2
  fi
}

safe_cleanup_sources() {
  local chd="$1"; shift
  local sources=("$@")
  if [[ -f "$chd" && -s "$chd" ]]; then
    for s in "${sources[@]}"; do [[ -e "$s" ]] && rm -f -- "$s"; done
  fi
}

process_extracted_set() {
  local workdir="$1" basename_noext="$2" outdir="$3"
  local chd="${outdir}/${basename_noext}.chd"

  local desc
  desc="$(find "$workdir" -maxdepth 1 -type f \( -iname '*.cue' -o -iname '*.gdi' -o -iname '*.toc' \) | head -n1 || true)"
  if [[ -n "$desc" ]]; then
    log "Converting (CD) $basename_noext -> $(basename "$chd")"
    to_chd "$desc" "$chd"
    mapfile -t tracks < <(cue_list_sources "$desc" 2>/dev/null || true)
    safe_cleanup_sources "$chd" "$desc" "${tracks[@]}"
    return 0
  fi

  local dvd
  dvd="$(find "$workdir" -maxdepth 1 -type f \( -iname '*.iso' -o -iname '*.gcm' \) | head -n1 || true)"
  if [[ -n "$dvd" ]]; then
    log "Converting (DVD) $basename_noext -> $(basename "$chd")"
    to_chd "$dvd" "$chd"
    safe_cleanup_sources "$chd" "$dvd"
    return 0
  fi

  log "No convertible image found for $basename_noext — skipping."
  return 2
}

process_archive() {
  local archive="$1" outdir="$2"
  local fname basename_noext workdir
  fname="$(basename "$archive")"
  basename_noext="${fname%.*}"
  workdir="$(mktemp -d --tmpdir="$outdir" ".extract_${basename_noext}_XXXX")"

  log "Extracting: $fname"
  "$SEVENZIP_BIN" x -y -o"$workdir" -- "$archive" >/dev/null || {
    log "Extraction failed: $fname"
    rm -rf -- "$workdir"; return 2
  }

  process_extracted_set "$workdir" "$basename_noext" "$outdir" || {
    log "FAILED to find/convert content for $fname"
    rm -rf -- "$workdir"; return 2
  }

  if [[ -s "${outdir}/${basename_noext}.chd" ]]; then
    log "Success: ${basename_noext}.chd created. Cleaning archive."
    rm -f -- "$archive"
  else
    log "CHD not created for $fname; leaving archive."
  fi
  rm -rf -- "$workdir"
}

process_loose_single() {
  local f="$1" outdir="$2"
  local stem chd
  stem="${f%.*}"
  chd="${stem}.chd"

  if [[ -s "$chd" ]]; then
    log "CHD already exists for $(basename "$f"); skipping."
    return 0
  fi

  if is_cd_ext "$f"; then
    log "Converting (CD) $(basename "$stem") -> $(basename "$chd")"
    to_chd "$f" "$chd"
    mapfile -t refs < <(cue_list_sources "$f" 2>/dev/null || true)
    safe_cleanup_sources "$chd" "$f" "${refs[@]}"
  elif is_dvd_ext "$f"; then
    log "Converting (DVD) $(basename "$stem") -> $(basename "$chd")"
    to_chd "$f" "$chd"
    safe_cleanup_sources "$chd" "$f"
  else
    unsupported_image_notice "$f"
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
  [[ -d "$ROM_DIR" ]] || { echo "ERROR: ROM_DIR does not exist: $ROM_DIR" >&2; exit 1; }

  preflight   # resolves tools and exports SEVENZIP_BIN

  log "Starting ROMs -> CHD in: $ROM_DIR  (JOBS=$JOBS, RECURSIVE=$RECURSIVE)"

  # ---- Parallel: archives first ----
  mapfile -d '' -t ARCHIVES < <( gfind -type f \( -iname '*.7z' -o -iname '*.zip' \) )
  log "Archives found: ${#ARCHIVES[@]}"
  if (( ${#ARCHIVES[@]} )); then
    printf '%s\0' "${ARCHIVES[@]}" | xargs -0 -I{} -P "$JOBS" bash -c '
      set -euo pipefail
      "'"$0"'" __proc_archive "$@" 
    ' _ {} "$ROM_DIR"
  else
    log "No archives found (.7z/.zip)."
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
    ' _ {} "$ROM_DIR"
  fi
  if (( ${#LOOSER_DVD[@]} )); then
    printf '%s\0' "${LOOSER_DVD[@]}" | xargs -0 -I{} -P "$JOBS" bash -c '
      set -euo pipefail
      "'"$0"'" __proc_loose "$@" 
    ' _ {} "$ROM_DIR"
  fi

  log "Done."
}

main "$@"