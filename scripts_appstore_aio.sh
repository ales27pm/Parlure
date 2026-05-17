#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
DEFAULT_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/parlure-appstore"
DEFAULT_CONFIG_FILE="$DEFAULT_CONFIG_DIR/config.env"
KEYCHAIN_SERVICE="parlure.appstore.aio"
START_TS="$(date +%s)"
METRICS_STEPS_TOTAL=0
METRICS_STEPS_DONE=0
CURRENT_ACTION=""

log() { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }
err() { printf '[%s] ERROR: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }

usage() {
  cat <<USAGE
$SCRIPT_NAME — Refined Apple Developer AIO Pipeline (Verbose + Metrics)

USAGE:
  $SCRIPT_NAME init [--config <path>] [--non-interactive]
  $SCRIPT_NAME build [--config <path>] [--non-interactive]
  $SCRIPT_NAME publish [--config <path>] [--non-interactive]
  $SCRIPT_NAME all [--config <path>] [--non-interactive]

DESCRIPTION:
  init    : Persist default config values.
  build   : Resolve packages, archive, and export IPA.
  publish : Upload IPA to App Store Connect via iTMSTransporter.
  all     : Run init (if needed), build, and publish.
USAGE
}

ascii_banner() { cat <<'ART'
╔══════════════════════════════════════════════════════════════════╗
║    APPLE DEVELOPER AIO DEPLOYMENT • SIGNING • BUILD • METRICS   ║
╠══════════════════════════════════════════════════════════════════╣
║   [··········] init   -> defaults + secure config               ║
║   [··········] build  -> resolve deps + archive + export ipa    ║
║   [··········] upload -> app store connect publish              ║
╚══════════════════════════════════════════════════════════════════╝
ART
}

progress_bar() {
  local label="$1" percent="$2" width=30
  local fill=$((percent * width / 100))
  local empty=$((width - fill))
  printf '%-24s [' "$label"
  if (( fill > 0 )); then printf '%0.s#' $(seq 1 "$fill"); fi
  if (( empty > 0 )); then printf '%0.s.' $(seq 1 "$empty"); fi
  printf '] %3d%%\n' "$percent"
}

record_step() {
  local label="$1"
  METRICS_STEPS_DONE=$((METRICS_STEPS_DONE + 1))
  local pct=$((METRICS_STEPS_DONE * 100 / METRICS_STEPS_TOTAL))
  progress_bar "$label" "$pct"
}

emit_metrics() {
  local elapsed=$(( $(date +%s) - START_TS ))
  cat <<EOF_METRIC

┌──────────────────────────── run metrics ─────────────────────────────┐
│ steps completed : ${METRICS_STEPS_DONE}/${METRICS_STEPS_TOTAL}
│ elapsed seconds : ${elapsed}
│ action          : ${CURRENT_ACTION}
│ config file     : ${CONFIG_FILE}
└──────────────────────────────────────────────────────────────────────┘
EOF_METRIC
}

on_error() { err "Failed at line $1: $2"; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }; }
validate_team_id() { [[ "$1" =~ ^[A-Z0-9]{10}$ ]] || { err "TEAM_ID must be exactly 10 alphanumeric uppercase characters."; exit 1; }; }
validate_file_exists() { [[ -f "$1" ]] || { err "Required file does not exist: $1"; exit 1; }; }
validate_path_exists() { [[ -e "$1" ]] || { err "Required path does not exist: $1"; exit 1; }; }
validate_parent_writable() {
  local p="$1" d
  d="$(dirname "$p")"
  mkdir -p "$d"
  [[ -w "$d" ]] || { err "Parent directory is not writable: $d (for $p)"; exit 1; }
}

expand_user_path() {
  local p="$1"
  case "$p" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${p#~/}" ;;
    *) printf '%s\n' "$p" ;;
  esac
}

absolute_path() {
  local p="$1" dir base
  if [[ "$p" = /* ]]; then
    printf '%s\n' "$p"
    return
  fi

  dir="$(dirname "$p")"
  base="$(basename "$p")"
  if [[ -d "$dir" ]]; then
    printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
  else
    printf '%s/%s\n' "$(pwd -P)" "$p"
  fi
}

resolve_app_store_key_path() {
  APP_STORE_KEY_PATH="$(expand_user_path "$APP_STORE_KEY_PATH")"
  if [[ -d "$APP_STORE_KEY_PATH" ]]; then
    APP_STORE_KEY_PATH="${APP_STORE_KEY_PATH%/}/AuthKey_${APP_STORE_KEY_ID}.p8"
  fi
  APP_STORE_KEY_PATH="$(absolute_path "$APP_STORE_KEY_PATH")"
  validate_file_exists "$APP_STORE_KEY_PATH"
}

ensure_tools() {
  require_cmd xcodebuild
  require_cmd security
  require_cmd xcrun
  require_cmd find
}

find_transporter() {
  local candidate
  for candidate in \
    "/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter" \
    "$(command -v iTMSTransporter 2>/dev/null || true)" \
    "$(xcrun -f iTMSTransporter 2>/dev/null || true)"; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    if "$candidate" -version >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 0
}

run_transporter_upload() {
  local transporter="$1"
  API_PRIVATE_KEYS_DIR="$(dirname "$APP_STORE_KEY_PATH")" \
    "$transporter" -m upload \
    -assetFile "$IPA_PATH" \
    -apiKey "$APP_STORE_KEY_ID" \
    -apiIssuer "$APP_STORE_ISSUER_ID" \
    -v eXtreme
}

run_altool_upload() {
  API_PRIVATE_KEYS_DIR="$(dirname "$APP_STORE_KEY_PATH")" \
    xcrun altool --upload-app \
    -f "$IPA_PATH" \
    --api-key "$APP_STORE_KEY_ID" \
    --api-issuer "$APP_STORE_ISSUER_ID" \
    --p8-file-path "$APP_STORE_KEY_PATH" \
    --verbose
}

run_app_store_upload() {
  local transporter
  transporter="$(find_transporter)"
  if [[ -n "$transporter" ]]; then
    log "Uploading with iTMSTransporter: $transporter"
    run_transporter_upload "$transporter"
    return
  fi

  if xcrun -f altool >/dev/null 2>&1; then
    warn "Usable iTMSTransporter not found; falling back to xcrun altool."
    run_altool_upload
    return
  fi

  err "No usable App Store uploader found. Install Apple's Transporter app from the Mac App Store, then rerun publish."
  exit 1
}

ensure_config_dir() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  chmod 700 "$(dirname "$CONFIG_FILE")"
}

# Store a key=value pair. Values can contain '=' and are safe from backslash interpretation.
save_kv() {
  local key="$1" value="$2"
  export AWK_KEY="$key" AWK_VALUE="$value"
  touch "$CONFIG_FILE"
  awk 'BEGIN { FS="="; OFS="="; updated=0 }
       $1==ENVIRON["AWK_KEY"] { print $1, ENVIRON["AWK_VALUE"]; updated=1; next }
       { print }
       END { if (!updated) print ENVIRON["AWK_KEY"], ENVIRON["AWK_VALUE"] }' \
       "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

prompt_if_empty() {
  local var_name="$1" prompt="$2" default_val="${3:-}"
  local current="${!var_name:-}"
  if [[ -z "$current" ]]; then
    if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
      [[ -n "$default_val" ]] || {
        local ctx="non-interactive mode"
        [[ -n "${CURRENT_ACTION:-}" ]] && ctx+=" during '${CURRENT_ACTION}'"
        [[ -n "${CONFIG_FILE:-}" ]] && ctx+=" (config: ${CONFIG_FILE})"
        err "Missing required value for '${var_name}' in ${ctx}."
        exit 1
      }
      current="$default_val"
    elif [[ -n "$default_val" ]]; then
      read -r -p "$prompt [$default_val]: " current
      current="${current:-$default_val}"
    else
      read -r -p "$prompt: " current
    fi
    printf -v "$var_name" '%s' "$current"
  fi
}

# Load config file. Splits only on the first '=', allowing values to contain '='.
load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    while IFS='=' read -r raw_key raw_val; do
      [[ -z "${raw_key}" ]] && continue
      [[ "${raw_key}" =~ ^[[:space:]]*# ]] && continue
      # Strip any trailing whitespace/carriage return from key
      local key="${raw_key//[$'\t\r ']/}"
      local val="${raw_val:-}"
      case "$key" in
        WORKSPACE|SCHEME|CONFIGURATION|TEAM_ID|BUNDLE_ID|EXPORT_PATH|ARCHIVE_PATH|APP_STORE_KEY_ID|APP_STORE_ISSUER_ID|APP_STORE_KEY_PATH)
          printf -v "$key" '%s' "$val"
          ;;
        *) warn "Ignoring unknown config key: $key" ;;
      esac
    done < "$CONFIG_FILE"
  fi
}

write_export_options() {
  cat > "$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>stripSwiftSymbols</key><true/>
  <key>uploadBitcode</key><false/>
  <key>compileBitcode</key><false/>
</dict></plist>
PLIST
}

cmd_init() {
  # Only set total steps if NOT part of 'all' pipeline
  [[ "${CURRENT_ACTION}" != all:* ]] && METRICS_STEPS_TOTAL=4
  ascii_banner
  ensure_config_dir
  touch "$CONFIG_FILE" && chmod 600 "$CONFIG_FILE"
  record_step "init: secure config"

  load_config
  prompt_if_empty WORKSPACE "Xcode workspace (.xcworkspace path)" "ios/Parlure.xcodeproj/project.xcworkspace"
  prompt_if_empty SCHEME "Xcode scheme" "Parlure"
  prompt_if_empty CONFIGURATION "Build configuration" "Release"
  prompt_if_empty TEAM_ID "Apple Team ID (10 chars)"
  prompt_if_empty BUNDLE_ID "Bundle Identifier" "com.example.app"
  prompt_if_empty EXPORT_PATH "Export IPA directory" "build/export"
  prompt_if_empty ARCHIVE_PATH "Archive path" "build/Parlure.xcarchive"
  prompt_if_empty APP_STORE_KEY_ID "App Store Connect API Key ID"
  prompt_if_empty APP_STORE_ISSUER_ID "App Store Connect Issuer ID"
  prompt_if_empty APP_STORE_KEY_PATH "Path to AuthKey_<KEYID>.p8"
  validate_team_id "$TEAM_ID"
  resolve_app_store_key_path
  record_step "init: collect values"

  save_kv WORKSPACE "$WORKSPACE"; save_kv SCHEME "$SCHEME"; save_kv CONFIGURATION "$CONFIGURATION"
  save_kv TEAM_ID "$TEAM_ID"; save_kv BUNDLE_ID "$BUNDLE_ID"; save_kv EXPORT_PATH "$EXPORT_PATH"
  save_kv ARCHIVE_PATH "$ARCHIVE_PATH"; save_kv APP_STORE_KEY_ID "$APP_STORE_KEY_ID"
  save_kv APP_STORE_ISSUER_ID "$APP_STORE_ISSUER_ID"; save_kv APP_STORE_KEY_PATH "$APP_STORE_KEY_PATH"
  record_step "init: persist config"

  log "Initialization complete."
  record_step "init: finalize"
}

cmd_build() {
  [[ "${CURRENT_ACTION}" != all:* ]] && METRICS_STEPS_TOTAL=6
  load_config
  prompt_if_empty WORKSPACE "Xcode workspace (.xcworkspace path)"
  prompt_if_empty SCHEME "Xcode scheme"
  prompt_if_empty CONFIGURATION "Build configuration" "Release"
  prompt_if_empty TEAM_ID "Apple Team ID"
  prompt_if_empty APP_STORE_KEY_ID "App Store Connect API Key ID"
  prompt_if_empty APP_STORE_ISSUER_ID "App Store Connect Issuer ID"
  prompt_if_empty APP_STORE_KEY_PATH "Path to AuthKey_<KEYID>.p8"
  prompt_if_empty EXPORT_PATH "Export IPA directory" "build/export"
  prompt_if_empty ARCHIVE_PATH "Archive path" "build/Parlure.xcarchive"
  validate_team_id "$TEAM_ID"
  resolve_app_store_key_path
  validate_path_exists "$WORKSPACE"
  validate_parent_writable "$ARCHIVE_PATH"
  validate_parent_writable "$EXPORT_PATH/.ipa-check"
  record_step "build: validate"

  EXPORT_OPTIONS_PLIST="$(dirname "$ARCHIVE_PATH")/ExportOptions.plist"
  mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_PATH"
  write_export_options
  record_step "build: prep plist"

  local -a xcode_auth_args=(
    -authenticationKeyPath "$APP_STORE_KEY_PATH"
    -authenticationKeyID "$APP_STORE_KEY_ID"
    -authenticationKeyIssuerID "$APP_STORE_ISSUER_ID"
  )

  xcodebuild -resolvePackageDependencies -workspace "$WORKSPACE" -scheme "$SCHEME"
  record_step "build: resolve deps"

  xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -destination generic/platform=iOS \
    -allowProvisioningUpdates \
    "${xcode_auth_args[@]}" \
    DEVELOPMENT_TEAM="$TEAM_ID"
  record_step "build: archive"

  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
    -exportPath "$EXPORT_PATH" \
    -allowProvisioningUpdates \
    "${xcode_auth_args[@]}"
  record_step "build: export"

  # Pick the newest IPA by modification time (robust against stale builds)
  IPA_PATH="$(ls -t "$EXPORT_PATH"/*.ipa 2>/dev/null | head -1 || true)"
  [[ -n "$IPA_PATH" ]] || { err "No IPA found in $EXPORT_PATH"; exit 1; }
  log "IPA ready: $IPA_PATH"
  record_step "build: complete"
}

cmd_publish() {
  [[ "${CURRENT_ACTION}" != all:* ]] && METRICS_STEPS_TOTAL=4
  load_config
  prompt_if_empty EXPORT_PATH "Export IPA directory" "build/export"
  prompt_if_empty APP_STORE_KEY_ID "App Store Connect API Key ID"
  prompt_if_empty APP_STORE_ISSUER_ID "App Store Connect Issuer ID"
  prompt_if_empty APP_STORE_KEY_PATH "Path to AuthKey_<KEYID>.p8"
  resolve_app_store_key_path
  record_step "publish: validate"

  IPA_PATH="$(ls -t "$EXPORT_PATH"/*.ipa 2>/dev/null | head -1 || true)"
  [[ -n "$IPA_PATH" ]] || { err "No IPA found in $EXPORT_PATH"; exit 1; }
  record_step "publish: locate ipa"

  run_app_store_upload
  record_step "publish: upload"

  log "Publish submitted."
  record_step "publish: complete"
}

main() {
  trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR
  CONFIG_FILE="$DEFAULT_CONFIG_FILE"
  NON_INTERACTIVE=0
  action="${1:-help}"
  shift || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        [[ ${2:-} ]] || { err "--config requires a path argument"; exit 1; }
        CONFIG_FILE="$2"
        shift 2
        ;;
      --non-interactive) NON_INTERACTIVE=1; shift ;;
      --help|-h) usage; exit 0 ;;
      *) err "Unknown argument: $1"; usage; exit 1 ;;
    esac
  done

  ensure_tools

  case "$action" in
    init)
      CURRENT_ACTION="init"
      cmd_init
      ;;
    build)
      CURRENT_ACTION="build"
      cmd_build
      ;;
    publish)
      CURRENT_ACTION="publish"
      cmd_publish
      ;;
    all)
      # Determine total steps for the full pipeline
      if [[ -f "$CONFIG_FILE" ]]; then
        METRICS_STEPS_TOTAL=$(( 6 + 4 ))   # build + publish
      else
        METRICS_STEPS_TOTAL=$(( 4 + 6 + 4 ))   # init + build + publish
      fi
      METRICS_STEPS_DONE=0

      CURRENT_ACTION="all:init"
      [[ -f "$CONFIG_FILE" ]] || cmd_init

      CURRENT_ACTION="all:build"
      cmd_build

      CURRENT_ACTION="all:publish"
      cmd_publish
      ;;
    help|--help|-h) usage ;;
    *)
      err "Unknown action: $action"
      usage
      exit 1
      ;;
  esac

  emit_metrics
}

main "$@"
