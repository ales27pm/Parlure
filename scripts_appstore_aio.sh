#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
DEFAULT_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/parlure-appstore"
DEFAULT_CONFIG_FILE="$DEFAULT_CONFIG_DIR/config.env"
KEYCHAIN_SERVICE="parlure.appstore.aio"
START_TS="$(date +%s)"
METRICS_STEPS_TOTAL=0
METRICS_STEPS_DONE=0

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
  init    : Persist default config and securely store optional secrets in Keychain.
  build   : Resolve packages, archive, and export IPA.
  publish : Upload IPA to App Store Connect.
  all     : Run init (if needed), build, and publish.
USAGE
}

ascii_banner() { cat <<'ART'
╔══════════════════════════════════════════════════════════════════════════════╗
║    APPLE DEVELOPER AIO DEPLOYMENT • SIGNING • BUILD • PUBLISH • METRICS     ║
╠══════════════════════════════════════════════════════════════════════════════╣
║   [▒▒▒▒▒▒▒▒▒▒] init   -> defaults + secure keychain storage                  ║
║   [▒▒▒▒▒▒▒▒▒▒] build  -> resolve deps + archive + export ipa                 ║
║   [▒▒▒▒▒▒▒▒▒▒] upload -> app store connect publish                           ║
╚══════════════════════════════════════════════════════════════════════════════╝
ART
}

progress_bar() {
  local label="$1" percent="$2" width=30
  local fill=$((percent * width / 100))
  local empty=$((width - fill))
  printf '%-24s [' "$label"
  printf '%0.s#' $(seq 1 "$fill")
  printf '%0.s.' $(seq 1 "$empty")
  printf '] %3d%%\n' "$percent"
}

record_step() {
  local label="$1"
  METRICS_STEPS_DONE=$((METRICS_STEPS_DONE + 1))
  local pct=$((METRICS_STEPS_DONE * 100 / METRICS_STEPS_TOTAL))
  progress_bar "$label" "$pct"
}

emit_metrics() {
  local end_ts elapsed
  end_ts="$(date +%s)"
  elapsed=$((end_ts - START_TS))
  printf '\n'
  cat <<EOF_METRIC
┌─────────────────────────── run metrics ───────────────────────────┐
│ steps completed : ${METRICS_STEPS_DONE}/${METRICS_STEPS_TOTAL}
│ elapsed seconds : ${elapsed}
│ config file     : ${CONFIG_FILE}
└────────────────────────────────────────────────────────────────────┘
EOF_METRIC
}

on_error() {
  local line="$1" cmd="$2"
  err "Failed at line ${line}: ${cmd}"
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }; }
validate_team_id() { [[ "$1" =~ ^[A-Z0-9]{10}$ ]] || { err "TEAM_ID must be exactly 10 alphanumeric uppercase characters."; exit 1; }; }
validate_file_exists() { [[ -f "$1" ]] || { err "Required file does not exist: $1"; exit 1; }; }

ensure_tools() {
  require_cmd xcodebuild
  require_cmd security
  require_cmd xcrun
  require_cmd find
}

ensure_config_dir() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  chmod 700 "$(dirname "$CONFIG_FILE")"
}

save_kv() {
  local key="$1" value="$2"
  awk -F= -v k="$key" -v v="$value" '
    BEGIN { u=0 }
    $1==k { print k"="v; u=1; next }
    { print }
    END { if (!u) print k"="v }
  ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
}

set_keychain_secret() {
  local account="$1" secret="$2"
  security delete-generic-password -s "$KEYCHAIN_SERVICE" -a "$account" >/dev/null 2>&1 || true
  security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$account" -w "$secret" >/dev/null
}

prompt_if_empty() {
  local var_name="$1" prompt="$2" default_val="${3:-}" current="${!var_name:-}"
  if [[ -z "$current" ]]; then
    if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
      [[ -n "$default_val" ]] || { err "Missing required value for $var_name in non-interactive mode."; exit 1; }
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

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi
}

write_export_options() {
  cat > "$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>stripSwiftSymbols</key><true/>
  <key>uploadBitcode</key><false/>
  <key>compileBitcode</key><false/>
</dict></plist>
PLIST
}

cmd_init() {
  METRICS_STEPS_TOTAL=5
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
  record_step "init: collect values"

  save_kv WORKSPACE "$WORKSPACE"; save_kv SCHEME "$SCHEME"; save_kv CONFIGURATION "$CONFIGURATION"
  save_kv TEAM_ID "$TEAM_ID"; save_kv BUNDLE_ID "$BUNDLE_ID"; save_kv EXPORT_PATH "$EXPORT_PATH"
  save_kv ARCHIVE_PATH "$ARCHIVE_PATH"; save_kv APP_STORE_KEY_ID "$APP_STORE_KEY_ID"
  save_kv APP_STORE_ISSUER_ID "$APP_STORE_ISSUER_ID"; save_kv APP_STORE_KEY_PATH "$APP_STORE_KEY_PATH"
  record_step "init: persist config"

  local app_specific_password=""
  if [[ "${NON_INTERACTIVE:-0}" == "0" ]]; then
    read -r -s -p "Optional app-specific password (leave blank to skip): " app_specific_password; echo
  fi
  if [[ -n "$app_specific_password" ]]; then
    set_keychain_secret "app_specific_password" "$app_specific_password"
  fi
  record_step "init: keychain sync"

  log "Initialization complete."
  record_step "init: finalize"
}

cmd_build() {
  METRICS_STEPS_TOTAL=6
  load_config
  prompt_if_empty WORKSPACE "Xcode workspace (.xcworkspace path)"
  prompt_if_empty SCHEME "Xcode scheme"
  prompt_if_empty CONFIGURATION "Build configuration" "Release"
  prompt_if_empty TEAM_ID "Apple Team ID"
  prompt_if_empty EXPORT_PATH "Export IPA directory" "build/export"
  prompt_if_empty ARCHIVE_PATH "Archive path" "build/Parlure.xcarchive"
  validate_team_id "$TEAM_ID"
  record_step "build: validate"

  EXPORT_OPTIONS_PLIST="$(dirname "$ARCHIVE_PATH")/ExportOptions.plist"
  mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_PATH"
  write_export_options
  record_step "build: prep plist"

  xcodebuild -resolvePackageDependencies -workspace "$WORKSPACE" -scheme "$SCHEME"
  record_step "build: resolve deps"

  xcodebuild archive -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration "$CONFIGURATION" -archivePath "$ARCHIVE_PATH" -destination generic/platform=iOS DEVELOPMENT_TEAM="$TEAM_ID"
  record_step "build: archive"

  xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" -exportPath "$EXPORT_PATH"
  record_step "build: export"

  IPA_PATH="$(find "$EXPORT_PATH" -maxdepth 1 -name '*.ipa' | head -n 1 || true)"
  [[ -n "$IPA_PATH" ]] || { err "No IPA found in $EXPORT_PATH"; exit 1; }
  log "IPA ready: $IPA_PATH"
  record_step "build: complete"
}

cmd_publish() {
  METRICS_STEPS_TOTAL=4
  load_config
  prompt_if_empty EXPORT_PATH "Export IPA directory" "build/export"
  prompt_if_empty APP_STORE_KEY_ID "App Store Connect API Key ID"
  prompt_if_empty APP_STORE_ISSUER_ID "App Store Connect Issuer ID"
  prompt_if_empty APP_STORE_KEY_PATH "Path to AuthKey_<KEYID>.p8"
  validate_file_exists "$APP_STORE_KEY_PATH"
  record_step "publish: validate"

  IPA_PATH="$(find "$EXPORT_PATH" -maxdepth 1 -name '*.ipa' | head -n 1 || true)"
  [[ -n "$IPA_PATH" ]] || { err "No IPA found in $EXPORT_PATH"; exit 1; }
  record_step "publish: locate ipa"

  xcrun altool --upload-app --type ios --file "$IPA_PATH" --apiKey "$APP_STORE_KEY_ID" --apiIssuer "$APP_STORE_ISSUER_ID" --verbose
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
      --config) CONFIG_FILE="$2"; shift 2 ;;
      --non-interactive) NON_INTERACTIVE=1; shift ;;
      --help|-h) usage; exit 0 ;;
      *) err "Unknown argument: $1"; usage; exit 1 ;;
    esac
  done

  ensure_tools
  case "$action" in
    init) cmd_init ;;
    build) cmd_build ;;
    publish) cmd_publish ;;
    all)
      [[ -f "$CONFIG_FILE" ]] || cmd_init
      cmd_build
      cmd_publish
      ;;
    help|--help|-h) usage ;;
    *) err "Unknown action: $action"; usage; exit 1 ;;
  esac

  emit_metrics
}

main "$@"
