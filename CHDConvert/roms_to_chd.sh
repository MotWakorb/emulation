#!/usr/bin/env bash
set -euo pipefail

# =========================
# Flag-only CLI (no env vars)
# =========================
ROM_DIR=""
RECURSIVE=0
OUT_DIR=""
LOG_DIR=""
DRYRUN=0
CHECK_ONLY=0
AUTO_INSTALL=0
SEVENZIP_BIN=""
# Jobs default: min(cores,6)
if command -v nproc >/dev/null 2>&1; then
  _J="$(nproc)"
elif [[ "$(uname -s)" == "Darwin" ]]; then
  _J="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
else
  _J=4
fi
JOBS="$(( _J>6 ? 6 : _J ))"

# ------------- Colors (TTY-aware, respects NO_COLOR) -------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  B=$'\033[1m'; C_OK=$'\033[1;32m'; C_INFO=$'\033[1;36m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; Z=$'\033[0m'
else
  B=; C_OK=; C_INFO=; C_WARN=; C_ERR=; Z=
fi
ts()   { date '+%F %T'; }
log()  { printf '[%s] %s%s%s\n' "$(ts)" "$C_INFO" "$*" "$Z"; }
ok()   { printf '[%s] %s%s%s\n' "$(ts)" "$C_OK"  "$*" "$Z"; }
warn() { printf '[%s] %s%s%s\n' "$(ts)" "$C_WARN" "$*" "$Z"; }
err()  { printf '[%s] %s%s%s\n' "$(ts)" "$C_ERR" "$*" "$Z" >&2; }

print_usage() {
  cat <<'EOF'
roms_to_chd.sh — Convert ROM archives & images to CHD (parallel, per-title logs, auto-preflight)

USAGE
  roms_to_chd.sh [options]

REQUIRED
  -d, --rom-dir DIR        Root directory containing ROMs

OPTIONS
  -r, --recursive          Recurse into subfolders (default: off)
  -o, --out-dir DIR        Write CHDs under this directory (mirrors rom-dir structure)
  -l, --log-dir DIR        Per-title logs directory (default: <rom-dir>/.chd_logs)
  -j, --jobs N             Parallel workers (default: min(cpu,6))
  -n, --dry-run            Preview actions; no extraction/convert/delete
  -a, --auto-install       Try to install missing deps (apt/dnf/yum/zypper/brew)
  -c, --check-only         Only check dependencies and exit
      --7z BIN             Force extractor (7zz or 7z)
  -h, --help               Show this help

SUPPORTED INPUTS
  Archives: .7z, .zip
  CDs:      .cue, .gdi, .toc
  DVDs:     .iso, .gcm
  (Unsupported: .wbfs/.cso/.nkit — convert back to .iso first)

EXAMPLES
  roms_to_chd.sh -d /path/to/roms/ps2 -r -j 6
  roms_to_chd.sh -d /path/to/roms -o /srv/chd -r -j 6
  roms_to_chd.sh -d /path/to/roms -c -a
EOF
}

die_usage() { err "$1"; echo; print_usage; exit 2; }

# ------------- Arg parsing (short + long) -------------
parse_args() {
  while (( $# )); do
    case "$1" in
      -d|--rom-dir)      ROM_DIR="${2:-}"; shift 2 ;;
      -r|--recursive)    RECURSIVE=1; shift ;;
      -o|--out-dir)      OUT_DIR="${2:-}"; shift 2 ;;
      -l|--log-dir)      LOG_DIR="${2:-}"; shift 2 ;;
      -j|--jobs)         JOBS="${2:-}"; shift 2 ;;
      -n|--dry-run)      DRYRUN=1; shift ;;
      -a|--auto-install) AUTO_INSTALL=1; shift ;;
      -c|--check-only)   CHECK_ONLY=1; shift ;;
          --7z)          SEVENZIP_BIN="${2:-}"; shift 2 ;;
      -h|--help)         print_usage; exit 0 ;;
      --) shift; break ;;
      -*) die_usage "Unknown option: $1" ;;
      *)  die_usage "Unexpected argument: $1" ;;
    esac
  done
  [[ -n "$ROM_DIR" ]] || die_usage "Missing required: --rom-dir"
  [[ -d "$ROM_DIR" ]] || { err "rom-dir not found: $ROM_DIR"; exit 1; }
  [[ -z "${SEVENZIP_BIN}" || "$SEVENZIP_BIN" == "7z" || "$SEVENZIP_BIN" == "7zz" ]] || die_usage "--7z must be 7z or 7zz"
  [[ "$JOBS" =~ ^[0-9]+$ ]] || die_usage "--jobs must be an integer"
  (( JOBS>0 )) || die_usage "--jobs must be > 0"
}

# ------------- Preflight (pkg mgr + deps) -------------
PKG_MGR=""; PKG_INSTALL=""
detect_pkg_mgr() {
  if command -v apt-get >/dev/null; then PKG_MGR=apt;    PKG_INSTALL="sudo apt update && sudo apt install -y"
  elif command -v dnf     >/dev/null; then PKG_MGR=dnf;    PKG_INSTALL="sudo dnf install -y"
  elif command -v yum     >/dev/null; then PKG_MGR=yum;    PKG_INSTALL="sudo yum install -y"
  elif command -v zypper  >/dev/null; then PKG_MGR=zypper; PKG_INSTALL="sudo zypper install -y"
  elif command -v brew    >/dev/null; then PKG_MGR=brew;   PKG_INSTALL="brew install"
  else PKG_MGR=unknown; fi
}
auto_install() {
  (( AUTO_INSTALL )) || return 1
  [[ -n "$PKG_INSTALL" ]] || return 1
  if [[ "$PKG_MGR" == "brew" ]]; then
    for p in "$@"; do brew list --versions "$p" >/dev/null 2>&1 || brew install "$p"; done
  else
    eval "$PKG_INSTALL $*"
  fi
}

preflight() {
  detect_pkg_mgr
  [[ -n "$SEVENZIP_BIN" ]] || { command -v 7zz >/dev/null && SEVENZIP_BIN=7zz || command -v 7z >/dev/null && SEVENZIP_BIN=7z || true; }

  local need_7z= need_chd=
  [[ -z "${SEVENZIP_BIN:-}" ]] && need_7z=1
  command -v chdman >/dev/null || need_chd=1

  if [[ -n "$need_7z" || -n "$need_chd" ]]; then
    case "$PKG_MGR" in
      apt)    p_7z=(7zip p7zip-full); p_chd=(mame-tools mame) ;;
      dnf|yum|zypper) p_7z=(7zip p7zip); p_chd=(mame-tools mame) ;;
      brew)   p_7z=(7zip p7zip); p_chd=(mame) ;;
      *)      ;;
    esac
    [[ -n "$need_7z" ]] && auto_install "${p_7z[@]:-}" || true
    [[ -n "$need_chd" ]] && auto_install "${p_chd[@]:-}" || true
    [[ -z "${SEVENZIP_BIN:-}" ]] && { command -v 7zz >/dev/null && SEVENZIP_BIN=7zz || command -v 7z >/dev/null && SEVENZIP_BIN=7z || true; }
  fi

  if [[ -z "${SEVENZIP_BIN:-}" ]]; then
    echo -e "\nMissing 7-Zip CLI (7zz/7z). Install via:"
    case "$PKG_MGR" in
      apt) echo "  sudo apt install 7zip    # or: sudo apt install p7zip-full" ;;
      dnf) echo "  sudo dnf install 7zip    # or: sudo dnf install p7zip" ;;
      yum) echo "  sudo yum install 7zip    # or: sudo yum install p7zip" ;;
      zypper) echo "  sudo zypper install 7zip # or: sudo zypper install p7zip" ;;
      brew) echo "  brew install 7zip        # or: brew install p7zip" ;;
      *) echo "  Install 7-Zip via your package manager." ;;
    esac
    exit 2
  fi
  if ! command -v chdman >/dev/null; then
    echo -e "\nMissing chdman (mame-tools/mame). Install via:"
    case "$PKG_MGR" in
      apt) echo "  sudo apt install mame-tools  # or: sudo apt install mame" ;;
      dnf) echo "  sudo dnf install mame-tools  # or: sudo dnf install mame" ;;
      yum) echo "  sudo yum install mame-tools  # or: sudo yum install mame" ;;
      zypper) echo "  sudo zypper install mame-tools  # or: sudo zypper install mame" ;;
      brew) echo "  brew install mame" ;;
      *) echo "  Install mame-tools/mame via your package manager." ;;
    esac
    exit 2
  fi

  ok "Preflight OK: using ${SEVENZIP_BIN} and chdman."
  (( CHECK_ONLY )) && { warn "check-only complete; exiting."; exit 0; }
}

# ------------- Helpers -------------
DVD_EXTS="iso gcm"
CD_EXTS="cue gdi toc"

is_ext_in() { local e="${1##*.}"; e="${e,,}"; shift; for x in "$@"; do [[ "$e" == "$x" ]] && return 0; done; return 1; }
is_cd()  { is_ext_in "$1" $CD_EXTS; }
is_dvd() { is_ext_in "$1" $DVD_EXTS; }

dest_dir_for() {
  local srcd="$1"
  [[ -z "$OUT_DIR" ]] && { printf '%s\n' "$srcd"; return; }
  case "$srcd" in
    "$ROM_DIR"/*) printf '%s/%s\n' "${OUT_DIR%/}" "${srcd#"$ROM_DIR"/}" ;;
    "$ROM_DIR")   printf '%s\n' "${OUT_DIR%/}" ;;
    *)            printf '%s\n' "${OUT_DIR%/}" ;;
  esac
}
ensure_dir() { (( DRYRUN )) && { log "DRYRUN: mkdir -p -- $1"; return; } ; mkdir -p -- "$1"; }
chd_path_for(){ local d; d="$(dirname "$1")"; local b="${1##*/}"; b="${b%.*}"; printf '%s/%s.chd\n' "$(dest_dir_for "$d")" "$b"; }
sanitize(){ printf '%s' "${1// /_}" | tr -cd '[:alnum:]_.-'; }
log_path_for(){ local t; t="$(sanitize "$1")"; printf '%s/%s.log\n' "$LOG_DIR" "$t"; }

run_log() { # log, cmd...
  local lf="$1"; shift
  (( DRYRUN )) && { log "DRYRUN: $*"; printf '[%s] DRYRUN: %s\n' "$(ts)" "$*" >>"$lf"; return 0; }
  printf '[%s] RUN: %s\n' "$(ts)" "$*" >>"$lf"
  set +e; ( "$@" ) 2>&1 | tee -a "$lf"; local rc=${PIPESTATUS[0]}; set -e; return $rc
}
safe_cleanup() { # chd log sources...
  local chd="$1"; shift; local lf="$1"; shift
  (( DRYRUN )) && { printf '[%s] DRYRUN: would delete: %s\n' "$(ts)" "$*" >>"$lf"; return; }
  [[ -s "$chd" ]] || return
  for s in "$@"; do [[ -e "$s" ]] && { printf '[%s] DELETE: %s\n' "$(ts)" "$s" >>"$lf"; rm -f -- "$s"; }; done
}
cue_sources() { # list files referenced by .cue/.toc
  local cue="$1" dir; dir="$(dirname "$cue")"
  awk 'BEGIN{IGNORECASE=1} $1=="FILE"{ s=$0; sub(/^.*FILE[ \t]+"/,"",s); sub(/"[ \t]+.*/,"",s); if (s=="") {split($0,a,/FILE[ \t]+/); split(a[2],b,/ /); s=b[1]} print s }' "$cue" | \
  while IFS= read -r r; do [[ -e "$dir/$r" ]] && printf '%s\n' "$dir/$r"; done
}

process_extracted() {
  local work="$1" base="$2" srcdir="$3" lf="$4" outd; outd="$(dest_dir_for "$srcdir")"; ensure_dir "$outd"
  local chd="$outd/$base.chd"

  local desc; desc="$(find "$work" -maxdepth 1 -type f \( -iname '*.cue' -o -iname '*.gdi' -o -iname '*.toc' \) -print -quit)"
  if [[ -n "$desc" ]]; then
    log "Converting (CD) $base -> $(basename "$chd")"
    run_log "$lf" chdman createcd -i "$desc" -o "$chd"
    mapfile -t tracks < <(cue_sources "$desc" 2>/dev/null || true)
    safe_cleanup "$chd" "$lf" "$desc" "${tracks[@]}"
    return 0
  fi

  local dvd; dvd="$(find "$work" -maxdepth 1 -type f \( -iname '*.iso' -o -iname '*.gcm' \) -print -quit)"
  if [[ -n "$dvd" ]]; then
    log "Converting (DVD) $base -> $(basename "$chd")"
    run_log "$lf" chdman createdvd -i "$dvd" -o "$chd"
    safe_cleanup "$chd" "$lf" "$dvd"
    return 0
  fi

  warn "No convertible image found for $base — skipping."
  return 2
}

process_archive() { # archive, srcdir
  local arc="$1" srcd="$2" name="$(basename "$arc")" base="${name%.*}" lf; lf="$(log_path_for "$base")"
  printf 'Title: %s\nSource: %s\n\n' "$base" "$arc" >"$lf"

  log "Extracting: $name"
  (( DRYRUN )) && { printf '[%s] DRYRUN: extract "%s"\n' "$(ts)" "$arc" >>"$lf"; return 0; }

  local tmp; tmp="$(mktemp -d --tmpdir="$srcd" ".extract_${base}_XXXX")"
  run_log "$lf" "$SEVENZIP_BIN" x -y -o"$tmp" -- "$arc" || { err "Extraction failed: $name"; printf '[%s] ERROR: extraction failed\n' "$(ts)" >>"$lf"; rm -rf -- "$tmp"; return 2; }

  process_extracted "$tmp" "$base" "$srcd" "$lf" || { printf '[%s] ERROR: convert step failed\n' "$(ts)" >>"$lf"; rm -rf -- "$tmp"; return 2; }

  local outchd; outchd="$(dest_dir_for "$srcd")/$base.chd"
  if [[ -s "$outchd" ]]; then
    ok "Success: $base.chd created; cleaning archive."
    printf '[%s] SUCCESS: created CHD\n' "$(ts)" >>"$lf"
    safe_cleanup "$outchd" "$lf" "$arc"
  else
    warn "CHD not created for $name; leaving archive."
    printf '[%s] WARN: CHD not created; kept archive\n' "$(ts)" >>"$lf"
  fi
  rm -rf -- "$tmp"
}

process_loose() { # file
  local f="$1" stem="${f%.*}" title="$(basename "$stem")" lf; lf="$(log_path_for "$title")"
  printf 'Title: %s\nSource: %s\n\n' "$title" "$f" >"$lf"
  local chd; chd="$(chd_path_for "$f")"
  [[ -s "$chd" ]] && { warn "CHD exists for $(basename "$f"); skip."; printf '[%s] SKIP: CHD exists: %s\n' "$(ts)" "$chd" >>"$lf"; return 0; }

  if is_cd "$f"; then
    log "Converting (CD) $title -> $(basename "$chd")"
    run_log "$lf" chdman createcd -i "$f" -o "$chd"
    mapfile -t refs < <(cue_sources "$f" 2>/dev/null || true)
    safe_cleanup "$chd" "$lf" "$f" "${refs[@]}"
  elif is_dvd "$f"; then
    log "Converting (DVD) $title -> $(basename "$chd")"
    run_log "$lf" chdman createdvd -i "$f" -o "$chd"
    safe_cleanup "$chd" "$lf" "$f"
  else
    warn "Unsupported input: $f"
    printf '[%s] WARN: unsupported image type\n' "$(ts)" >>"$lf"
  fi
}

# Worker dispatch for xargs
if [[ "${1:-}" == "__w_arc" ]]; then shift; process_archive "$@"; exit $?
elif [[ "${1:-}" == "__w_loose" ]]; then shift; process_loose "$@"; exit $?
fi

main() {
  parse_args "$@"
  preflight

  # Logs
  [[ -n "$LOG_DIR" ]] || LOG_DIR="$ROM_DIR/.chd_logs"
  ensure_dir "$LOG_DIR"
  log "Logs -> $LOG_DIR"

  # OUT_DIR
  [[ -n "$OUT_DIR" ]] && { ensure_dir "$OUT_DIR"; log "OUT_DIR -> $OUT_DIR (mirroring rom-dir)"; }

  (( DRYRUN )) && warn "DRY-RUN active — no extraction/convert/delete."
  log "Start: rom-dir=$ROM_DIR  jobs=$JOBS  recursive=$RECURSIVE"

  # Depth options for find
  if (( RECURSIVE )); then
    depth_opts=()
  else
    depth_opts=("-maxdepth" "1")
  fi

  # Archives
  find "$ROM_DIR" "${depth_opts[@]}" -type f \( -iname '*.7z' -o -iname '*.zip' \) -print0 2>/dev/null \
  | xargs -0 -I{} -P "$JOBS" bash -c '
      set -euo pipefail
      f="{}"; d="$(dirname "{}")"
      "'"$0"'" __w_arc "$f" "$d"
    ' || true

  # Loose images
  find "$ROM_DIR" "${depth_opts[@]}" -type f \
    \( -iname '*.cue' -o -iname '*.gdi' -o -iname '*.toc' -o -iname '*.iso' -o -iname '*.gcm' \) \
    -print0 2>/dev/null \
  | xargs -0 -I{} -P "$JOBS" bash -c '
      set -euo pipefail
      "'"$0"'" __w_loose "{}"
    ' || true

  ok "Done."
}

main "$@"
