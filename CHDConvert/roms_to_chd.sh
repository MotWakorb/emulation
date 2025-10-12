#!/usr/bin/env bash
set -euo pipefail

# ========= CLI / Defaults =========
ROM_DIR=""; OUT_DIR=""; LOG_DIR=""
RECURSIVE=0; DRYRUN=0; CHECK_ONLY=0; AUTO_INSTALL=0; SEVENZIP_BIN=""
FORCE=0; KEEP_ARCHIVES=0; ONLY_PLATFORM=""

# Jobs = min(cores,6)
if command -v nproc >/dev/null 2>&1; then _J="$(nproc)"
elif [[ "$(uname -s)" == "Darwin" ]]; then _J="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
else _J=4; fi
JOBS="$(( _J>6 ? 6 : _J ))"

# ========= Colors / logs =========
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_OK=$'\033[1;32m'; C_INFO=$'\033[1;36m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; Z=$'\033[0m'
else C_OK=; C_INFO=; C_WARN=; C_ERR=; Z=; fi
ts(){ date '+%F %T'; }
log(){ printf '[%s] %s%s%s\n' "$(ts)" "$C_INFO" "$*" "$Z"; }
ok() { printf '[%s] %s%s%s\n' "$(ts)" "$C_OK"  "$*" "$Z"; }
warn(){ printf '[%s] %s%s%s\n' "$(ts)" "$C_WARN" "$*" "$Z"; }
err(){ printf '[%s] %s%s%s\n' "$(ts)" "$C_ERR" "$*" "$Z" >&2; }

usage() {
  cat <<'H'
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

Supported inputs:
  Archives: .7z, .zip
  CDs:      .cue, .gdi, .toc
  DVDs:     .iso, .gcm
  Note: Dreamcast .cdi is detected and skipped (convert to CUE/BIN or GDI first)
H
}

die_usage(){ err "$1"; echo; usage; exit 2; }

# ========= Arg parsing =========
parse() {
  while (( $# )); do
    case "$1" in
      -d|--rom-dir) ROM_DIR="${2:-}"; shift 2;;
      -r|--recursive) RECURSIVE=1; shift;;
      -o|--out-dir) OUT_DIR="${2:-}"; shift 2;;
      -l|--log-dir) LOG_DIR="${2:-}"; shift 2;;
      -j|--jobs) JOBS="${2:-}"; shift 2;;
      -n|--dry-run) DRYRUN=1; shift;;
      -c|--check-only) CHECK_ONLY=1; shift;;
      -a|--auto-install) AUTO_INSTALL=1; shift;;
          --7z) SEVENZIP_BIN="${2:-}"; shift 2;;
      -f|--force) FORCE=1; shift;;
         --keep-archives) KEEP_ARCHIVES=1; shift;;
         --only-platform) ONLY_PLATFORM="${2:-}"; shift 2;;
      -h|--help) usage; exit 0;;
      -*) die_usage "Unknown option: $1";;
      *)  die_usage "Unexpected argument: $1";;
    esac
  done
  [[ -n "$ROM_DIR" && -d "$ROM_DIR" ]] || die_usage "Missing/invalid --rom-dir"
  [[ -z "${SEVENZIP_BIN}" || "$SEVENZIP_BIN" == "7z" || "$SEVENZIP_BIN" == "7zz" ]] || die_usage "--7z must be 7z or 7zz"
  [[ "$JOBS" =~ ^[0-9]+$ ]] || die_usage "--jobs must be an integer"
  (( JOBS>0 )) || die_usage "--jobs must be > 0"
  if [[ -n "$ONLY_PLATFORM" && ! "$ONLY_PLATFORM" =~ ^(dreamcast|ps2|psx|gc)$ ]]; then
    die_usage "--only-platform must be one of: dreamcast|ps2|psx|gc"
  fi
}

# ========= Preflight =========
PKG_MGR=""; PKG_INSTALL=""
pkgmgr() {
  if command -v apt-get >/dev/null; then PKG_MGR=apt;    PKG_INSTALL="sudo apt update && sudo apt install -y"
  elif command -v dnf     >/dev/null; then PKG_MGR=dnf;    PKG_INSTALL="sudo dnf install -y"
  elif command -v yum     >/dev/null; then PKG_MGR=yum;    PKG_INSTALL="sudo yum install -y"
  elif command -v zypper  >/dev/null; then PKG_MGR=zypper; PKG_INSTALL="sudo zypper install -y"
  elif command -v brew    >/dev/null; then PKG_MGR=brew;   PKG_INSTALL="brew install"
  else PKG_MGR=unknown; fi
}
autoinstall() {
  (( AUTO_INSTALL )) || return 1
  [[ -n "$PKG_INSTALL" ]] || return 1
  if [[ "$PKG_MGR" == "brew" ]]; then
    for p in "$@"; do brew list --versions "$p" >/dev/null 2>&1 || brew install "$p"; done
  else
    eval "$PKG_INSTALL $*"
  fi
}
resolve_7z() {
  local ex="${SEVENZIP_BIN:-}"
  if [[ -n "$ex" && "$(command -v "$ex" 2>/dev/null || true)" ]]; then printf '%s\n' "$ex"; return 0; fi
  if command -v 7zz >/dev/null 2>&1; then printf '%s\n' 7zz; return 0; fi
  if command -v 7z  >/dev/null 2>&1; then printf '%s\n' 7z;  return 0; fi
  return 1
}
preflight() {
  pkgmgr
  [[ -z "${SEVENZIP_BIN:-}" ]] && SEVENZIP_BIN="$(resolve_7z || true || echo '')"
  local need_7z= need_chd=
  [[ -z "${SEVENZIP_BIN:-}" ]] && need_7z=1
  command -v chdman >/dev/null || need_chd=1
  if [[ -n "$need_7z" || -n "$need_chd" ]]; then
    case "$PKG_MGR" in
      apt)    p7=(7zip p7zip-full); pm=(mame-tools mame) ;;
      dnf|yum|zypper) p7=(7zip p7zip); pm=(mame-tools mame) ;;
      brew)   p7=(7zip p7zip); pm=(mame) ;;
      *)      ;;
    esac
    [[ -n "$need_7z" ]] && autoinstall "${p7[@]:-}" || true
    [[ -n "$need_chd" ]] && autoinstall "${pm[@]:-}" || true
    [[ -z "${SEVENZIP_BIN:-}" ]] && SEVENZIP_BIN="$(resolve_7z || true || echo '')"
  fi
  [[ -n "${SEVENZIP_BIN:-}" ]] || { err "Missing 7-Zip CLI (7z/7zz)."; exit 2; }
  command -v chdman >/dev/null || { err "Missing chdman (mame-tools/mame)."; exit 2; }
  ok "Preflight OK: using ${SEVENZIP_BIN} and chdman."
  (( CHECK_ONLY )) && { warn "check-only complete; exiting."; exit 0; }
}

# ========= Helpers =========
DVD_EXTS="iso gcm"; CD_EXTS="cue gdi toc"
is_ext_in(){ local e="${1##*.}"; e="${e,,}"; shift; for x in "$@"; do [[ "$e" == "$x" ]] && return 0; done; return 1; }
is_cd(){  is_ext_in "$1" $CD_EXTS; }
is_dvd(){ is_ext_in "$1" $DVD_EXTS; }

# Only-platform filter (for loose images and extracted descriptors)
accept_by_platform(){ # path -> 0/1
  if [[ -z "$ONLY_PLATFORM" ]]; then return 0; fi
  local ext="${1##*.}"; ext="${ext,,}"
  case "$ONLY_PLATFORM" in
    dreamcast) [[ "$ext" == "gdi" || "$ext" == "toc" ]] && return 0 || return 1 ;; # avoid PSX *.cue overlap
    ps2)       [[ "$ext" == "iso" ]] && return 0 || return 1 ;;
    psx)       [[ "$ext" == "cue" ]] && return 0 || return 1 ;;
    gc)        [[ "$ext" == "gcm" || "$ext" == "iso" ]] && return 0 || return 1 ;;
  esac
}

dest_dir_for(){
  local srcd="$1"
  if [[ -z "$OUT_DIR" ]]; then printf '%s\n' "$srcd"; return; fi
  case "$srcd" in
    "$ROM_DIR"/*) printf '%s/%s\n' "${OUT_DIR%/}" "${srcd#"$ROM_DIR"/}" ;;
    "$ROM_DIR")   printf '%s\n' "${OUT_DIR%/}" ;;
    *)            printf '%s\n' "${OUT_DIR%/}" ;;
  esac
}
ensure_dir(){ if (( DRYRUN )); then log "DRYRUN: mkdir -p -- $1"; else mkdir -p -- "$1"; fi; }
chd_path_for(){ local d; d="$(dirname "$1")"; local b="${1##*/}"; b="${b%.*}"; printf '%s/%s.chd\n' "$(dest_dir_for "$d")" "$b"; }
sanitize(){ printf '%s' "${1// /_}" | tr -cd '[:alnum:]_.-'; }
log_path_for(){ local t; t="$(sanitize "$1")"; printf '%s/%s.log\n' "$LOG_DIR" "$t"; }

run_log(){
  local lf="$1"; shift
  if (( DRYRUN )); then log "DRYRUN: $*"; printf '[%s] DRYRUN: %s\n' "$(ts)" "$*" >>"$lf"; return 0; fi
  printf '[%s] RUN: %s\n' "$(ts)" "$*" >>"$lf"
  set +e; ( "$@" ) 2>&1 | tee -a "$lf"; local rc=${PIPESTATUS[0]}; set -e; return $rc
}
safe_cleanup(){
  local chd="$1"; shift; local lf="$1"; shift
  if (( DRYRUN )); then printf '[%s] DRYRUN: would delete: %s\n' "$(ts)" "$*" >>"$lf"; return; fi
  [[ -s "$chd" ]] || return
  for s in "$@"; do [[ -e "$s" ]] && { printf '[%s] DELETE: %s\n' "$(ts)" "$s" >>"$lf"; rm -f -- "$s"; }; done
}
cue_sources(){
  local cue="$1" dir; dir="$(dirname "$cue")"
  awk 'BEGIN{IGNORECASE=1} $1=="FILE"{ s=$0; sub(/^.*FILE[ \t]+"/,"",s); sub(/"[ \t]+.*/,"",s); if (s=="") {split($0,a,/FILE[ \t]+/); split(a[2],b,/ /); s=b[1]} print s }' "$cue" |
  while IFS= read -r r; do [[ -e "$dir/$r" ]] && printf '%s\n' "$dir/$r"; done
}

# ========= Progress Summary =========
SUMMARY_FILE=""
summary_note(){ printf '%s\t%s\n' "$1" "$2" >>"$SUMMARY_FILE"; }
print_summary(){
  echo
  log "Summary:"
  awk -F '\t' '
    { total++; c[$1]++ }
    END {
      printf("  Total items: %d\n", total);
      printf("    OK:        %d\n", c["OK"]+0);
      printf("    FAIL:      %d\n", c["FAIL"]+0);
      printf("    SKIP:      %d\n", c["SKIP"]+0);
      printf("    EXIST:     %d\n", c["EXIST"]+0);
      printf("    WARN_CDI:  %d\n", c["WARN_CDI"]+0);
      printf("    WOULD:     %d\n", c["WOULD"]+0);
    }
  ' "$SUMMARY_FILE" 2>/dev/null || true
}

# ========= Conversion workers =========
process_extracted(){ # work base srcdir lf
  local work="$1" base="$2" srcdir="$3" lf="$4" outd; outd="$(dest_dir_for "$srcdir")"; ensure_dir "$outd"
  local chd="$outd/$base.chd"
  local desc dvd cdi

  desc="$(find "$work" -maxdepth 1 -type f \( -iname '*.gdi' -o -iname '*.toc' -o -iname '*.cue' \) -print -quit)"
  dvd="$(find "$work" -maxdepth 1 -type f \( -iname '*.iso' -o -iname '*.gcm' \) -print -quit)"
  cdi="$(find "$work" -maxdepth 1 -type f -iname '*.cdi' -print -quit)"

  # Apply platform filter
  if [[ -n "$desc" ]] && ! accept_by_platform "$desc"; then desc=""; fi
  if [[ -n "$dvd"  ]] && ! accept_by_platform "$dvd";  then dvd="";  fi

  if [[ -n "$desc" ]]; then
    log "Converting (CD) $base -> $(basename "$chd")"
    if (( DRYRUN )); then summary_note "WOULD" "$base"; printf '[%s] DRYRUN: chdman createcd -i "%s" -o "%s"\n' "$(ts)" "$desc" "$chd" >>"$lf"; return 0; fi
    local forceFlag=(); (( FORCE )) && forceFlag=(-f)
    if run_log "$lf" chdman createcd "${forceFlag[@]}" -i "$desc" -o "$chd"; then
      mapfile -t tracks < <(cue_sources "$desc" 2>/dev/null || true)
      safe_cleanup "$chd" "$lf" "$desc" "${tracks[@]}"
      summary_note "OK" "$base"
    else
      summary_note "FAIL" "$base"; return 2
    fi
    return 0
  fi

  if [[ -n "$dvd" ]]; then
    log "Converting (DVD) $base -> $(basename "$chd")"
    if (( DRYRUN )); then summary_note "WOULD" "$base"; printf '[%s] DRYRUN: chdman createdvd -i "%s" -o "%s"\n' "$(ts)" "$dvd" "$chd" >>"$lf"; return 0; fi
    local forceFlag=(); (( FORCE )) && forceFlag=(-f)
    if run_log "$lf" chdman createdvd "${forceFlag[@]}" -i "$dvd" -o "$chd"; then
      safe_cleanup "$chd" "$lf" "$dvd"; summary_note "OK" "$base"
    else
      summary_note "FAIL" "$base"; return 2
    fi
    return 0
  fi

  if [[ -n "$cdi" ]]; then
    warn "Found .cdi for $base — convert to CUE/BIN or GDI first. Skipping."
    printf '[%s] WARN: .cdi not supported by chdman\n' "$(ts)" >>"$lf"
    summary_note "WARN_CDI" "$base"
    return 2
  fi

  warn "No convertible image found for $base — skipping."
  summary_note "SKIP" "$base"
  return 2
}

choose_extractor(){
  local ex="${SEVENZIP_BIN:-}"
  if [[ -n "$ex" && "$(command -v "$ex" 2>/dev/null || true)" ]]; then echo "$ex"; return 0; fi
  if command -v 7zz >/dev/null 2>&1; then echo 7zz; return 0; fi
  if command -v 7z  >/dev/null 2>&1; then echo 7z;  return 0; fi
  return 1
}

# Workers take an explicit DRYRUN flag to avoid env inheritance issues.
w_arc(){ # __w_arc <archive> <srcdir> <dryflag>
  local arc="$1" srcd="$2" dryflag="${3:-0}"; if [[ "$dryflag" == "1" ]]; then DRYRUN=1; else DRYRUN=0; fi
  local name base lf; name="$(basename "$arc")"; base="${name%.*}"; lf="$(log_path_for "$base")"
  printf 'Title: %s\nSource: %s\n\n' "$base" "$arc" >"$lf"
  if (( DRYRUN )); then
    log "DRYRUN: would extract: $name"
    printf '[%s] DRYRUN: extract "%s"\n' "$(ts)" "$arc" >>"$lf"
    summary_note "WOULD" "$base"
    return 0
  fi
  log "Extracting: $name"
  local tmp; tmp="$(mktemp -d --tmpdir="$srcd" ".extract_${base}_XXXX")"
  local EX; EX="$(choose_extractor)" || { err "No 7z extractor available in worker"; printf '[%s] ERROR: 7z extractor not found\n' "$(ts)" >>"$lf"; summary_note "FAIL" "$base"; rm -rf -- "$tmp"; return 2; }
  if ! run_log "$lf" "$EX" x -y -o"$tmp" -- "$arc"; then
    err "Extraction failed: $name"; printf '[%s] ERROR: extraction failed\n' "$(ts)" >>"$lf"; summary_note "FAIL" "$base"; rm -rf -- "$tmp"; return 2
  fi
  if process_extracted "$tmp" "$base" "$srcd" "$lf"; then
    local outchd; outchd="$(dest_dir_for "$srcd")/$base.chd"
    if [[ -s "$outchd" && "$KEEP_ARCHIVES" -eq 0 ]]; then
      safe_cleanup "$outchd" "$lf" "$arc"
    fi
  fi
  rm -rf -- "$tmp"
}

w_loose(){ # __w_loose <file> <dryflag>
  local f="$1" dryflag="${2:-0}"; if [[ "$dryflag" == "1" ]]; then DRYRUN=1; else DRYRUN=0; fi
  local stem title lf; stem="${f%.*}"; title="$(basename "$stem")"; lf="$(log_path_for "$title")"
  printf 'Title: %s\nSource: %s\n\n' "$title" "$f" >"$lf"

  # Platform filter for loose images
  if ! accept_by_platform "$f"; then
    printf '[%s] SKIP: filtered by --only-platform\n' "$(ts)" >>"$lf"
    summary_note "SKIP" "$title"
    return 0
  fi

  local chd; chd="$(chd_path_for "$f")"
  if [[ -s "$chd" && "$FORCE" -eq 0 ]]; then
    warn "CHD exists for $(basename "$f"); use --force to overwrite."
    printf '[%s] SKIP: CHD exists: %s\n' "$(ts)" "$chd" >>"$lf"
    summary_note "EXIST" "$title"
    return 0
  fi

  local ext; ext=".${f##*.}"; ext="${ext,,}"
  if   is_cd "$f";  then
    log "Converting (CD) $title -> $(basename "$chd")"
    if (( DRYRUN )); then summary_note "WOULD" "$title"; printf '[%s] DRYRUN: chdman createcd -i "%s" -o "%s"\n' "$(ts)" "$f" "$chd" >>"$lf"; return 0; fi
    local forceFlag=(); (( FORCE )) && forceFlag=(-f)
    if run_log "$lf" chdman createcd "${forceFlag[@]}" -i "$f" -o "$chd"; then
      mapfile -t refs < <(cue_sources "$f" 2>/dev/null || true)
      safe_cleanup "$chd" "$lf" "$f" "${refs[@]}"; summary_note "OK" "$title"
    else summary_note "FAIL" "$title"; fi
  elif is_dvd "$f"; then
    log "Converting (DVD) $title -> $(basename "$chd")"
    if (( DRYRUN )); then summary_note "WOULD" "$title"; printf '[%s] DRYRUN: chdman createdvd -i "%s" -o "%s"\n' "$(ts)" "$f" "$chd" >>"$lf"; return 0; fi
    local forceFlag=(); (( FORCE )) && forceFlag=(-f)
    if run_log "$lf" chdman createdvd "${forceFlag[@]}" -i "$f" -o "$chd"; then
      safe_cleanup "$chd" "$lf" "$f"; summary_note "OK" "$title"
    else summary_note "FAIL" "$title"; fi
  elif [[ "$ext" == ".cdi" ]]; then
    warn "Found .cdi: convert to CUE/BIN or GDI first (e.g., cdi → cue/bin)."
    printf '[%s] WARN: .cdi not supported by chdman\n' "$(ts)" >>"$lf"
    summary_note "WARN_CDI" "$title"
  else
    warn "Unsupported input: $f"; printf '[%s] WARN: unsupported image type\n' "$(ts)" >>"$lf"
    summary_note "SKIP" "$title"
  fi
}

# Early worker dispatch
if [[ "${1:-}" == "__w_arc" ]];  then shift; w_arc   "$@"; exit $?
elif [[ "${1:-}" == "__w_loose" ]]; then shift; w_loose "$@"; exit $?
fi

# ========= Main =========
main() {
  parse "$@"; preflight

  # Logs & OUT_DIR
  [[ -n "${LOG_DIR:-}" ]] || LOG_DIR="$ROM_DIR/.chd_logs"
  ensure_dir "$LOG_DIR"; log "Logs -> $LOG_DIR"
  if [[ -n "${OUT_DIR:-}" ]]; then ensure_dir "$OUT_DIR"; log "OUT_DIR -> $OUT_DIR (mirroring rom-dir)"; fi
  (( DRYRUN )) && warn "DRY-RUN active — no extraction/convert/delete."
  [[ -n "${ONLY_PLATFORM:-}" ]] && log "--only-platform = $ONLY_PLATFORM"
  (( FORCE )) && log "--force enabled (overwrite CHDs)"
  (( KEEP_ARCHIVES )) && log "--keep-archives enabled"

  # Progress summary file
  SUMMARY_FILE="$(mktemp)"
  export SUMMARY_FILE
  trap 'set +e; [[ -n "${SUMMARY_FILE:-}" && -f "$SUMMARY_FILE" ]] && { print_summary; rm -f "$SUMMARY_FILE"; }; : ' EXIT

  log "Start: rom-dir=$ROM_DIR  jobs=$JOBS  recursive=$RECURSIVE"
  log "Scanning for archives (.7z/.zip) and images (.cue/.gdi/.toc/.iso/.gcm/.cdi)..."

  # Depth options (order matters: -maxdepth BEFORE tests)
  if (( RECURSIVE )); then depth_opts=(); else depth_opts=(-maxdepth 1); fi

  # Safe temp holders
  tmp_arch=""; tmp_img=""
  trap 'set +e; [[ -n "${tmp_arch:-}" && -f "$tmp_arch" ]] && rm -f "$tmp_arch"; [[ -n "${tmp_img:-}" && -f "$tmp_img" ]] && rm -f "$tmp_img"; [[ -n "${SUMMARY_FILE:-}" && -f "$SUMMARY_FILE" ]] && { print_summary; rm -f "$SUMMARY_FILE"; }; : ' EXIT

  # Archives
  tmp_arch="$(mktemp)"
  find "$ROM_DIR" "${depth_opts[@]}" -type f \( -iname '*.7z' -o -iname '*.zip' \) -print0 2>/dev/null > "$tmp_arch" || true
  arch_count=$(tr -cd '\0' < "$tmp_arch" | wc -c | awk '{print $1}')
  log "Archives found: $arch_count"
  if (( arch_count > 0 )); then
    xargs -0 -I{} -P "$JOBS" bash -c '
      set -euo pipefail
      f="{}"; d="$(dirname "{}")"; dry="'"$DRYRUN"'"
      "'"$0"'" __w_arc "$f" "$d" "$dry"
    ' < "$tmp_arch" || true
  fi

  # Loose images (filter by platform up-front)
  tmp_img="$(mktemp)"
  find "$ROM_DIR" "${depth_opts[@]}" -type f \
    \( -iname '*.cue' -o -iname '*.gdi' -o -iname '*.toc' -o -iname '*.iso' -o -iname '*.gcm' -o -iname '*.cdi' \) \
    -print0 2>/dev/null > "$tmp_img" || true

  if [[ -n "$ONLY_PLATFORM" ]]; then
    mapfile -d '' -t _all < "$tmp_img" || true
    : > "$tmp_img"
    for p in "${_all[@]:-}"; do
      if accept_by_platform "$p"; then printf '%s\0' "$p" >> "$tmp_img"; fi
    done
  fi

  img_count=$(tr -cd '\0' < "$tmp_img" | wc -c | awk '{print $1}')
  log "Loose images found: $img_count"

  if (( img_count > 0 )); then
    xargs -0 -I{} -P "$JOBS" bash -c '
      set -euo pipefail
      dry="'"$DRYRUN"'"
      "'"$0"'" __w_loose "{}" "$dry"
    ' < "$tmp_img" || true
  fi

  ok "Done."
}

main "$@"