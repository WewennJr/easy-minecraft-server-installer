#!/usr/bin/env bash
#
# Easy Minecraft Server Installer
# Creates a ready-to-run Minecraft server (vanilla, Fabric, Forge, NeoForge)
# by downloading the correct files from official sources and preparing the folder.
#
set -euo pipefail

APP_NAME="Easy Minecraft Server Installer"
APP_VERSION="1.5"

VERSIONS=(
  26.3 26.2 26.1.2 26.1.1 26.1
  1.21.11 1.21.10 1.21.9 1.21.8 1.21.7 1.21.6 1.21.5 1.21.4 1.21.3 1.21.2 1.21.1 1.21
  1.20.6 1.20.5 1.20.4 1.20.3 1.20.2 1.20.1 1.20
  1.19.4 1.19.3 1.19.2 1.19.1 1.19
  1.18.2
)

MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
FORGE_PROMOS_URL="https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json"
FABRIC_LOADER_URL="https://meta.fabricmc.net/v2/versions/loader"
FABRIC_INSTALLER_URL="https://meta.fabricmc.net/v2/versions/installer"
NEOFORGE_MAVEN="https://maven.neoforged.net/releases/net/neoforged"
ADOPTIUM_ASSETS_URL="https://api.adoptium.net/v3/assets/latest"
EULA_URL="https://www.minecraft.net/eula"
CURL_HTTPS=(--proto '=https' --proto-redir '=https')

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""
  C_BOLD=""
  C_DIM=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
  C_CYAN=""
fi

NAME=""
VERSION=""
LOADER=""
RAM_GB=""
JAR_NAME=""
JAR_URL=""
JAR_SHA1=""
LOADER_DETAIL=""
JAVA_REQUIRED=""
MC_META=""
SERVER_DIR=""
EULA_ACCEPTED=0

JAVA_MODE="system"
JAVA_BIN="java"
JAVA_DETAIL=""
SYS_JAVA_MAJOR=""
JDK_FEATURE=""
LOCAL_JAVA_HOME=""
LOG_FILE=""
LOG_BUFFER=()

AC_CANDIDATES=()

log_line() {
  local line
  printf -v line '[%(%Y-%m-%d %H:%M:%S)T] %s' -1 "$*"
  if [[ -n "$LOG_FILE" ]]; then
    printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
  else
    LOG_BUFFER+=("$line")
  fi
}

start_logging() {
  LOG_FILE="$SERVER_DIR/install-server-$NAME.log"
  if ! : > "$LOG_FILE" 2>/dev/null; then
    LOG_FILE=""
    return 1
  fi
  local line
  for line in "${LOG_BUFFER[@]}"; do
    printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
  done
  LOG_BUFFER=()
}

log()  { printf '%s\n' "$*"; log_line "$*"; }
warn() { printf '%sWarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; log_line "Warning: $*"; }
die()  {
  printf '%sError:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2
  log_line "Error: $*"
  if [[ -n "$LOG_FILE" ]]; then
    printf 'Log: %s\n' "$LOG_FILE" >&2
  fi
  exit 1
}
ok()   { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET"; log_line "$*"; }
cancel() {
  if (($#)); then
    printf '%sCancelled:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2
    log_line "Cancelled: $*"
  else
    printf '%sCancelled.%s\n' "$C_YELLOW" "$C_RESET"
    log_line "Cancelled."
  fi
  if [[ -n "$LOG_FILE" ]]; then
    printf 'Log: %s\n' "$LOG_FILE"
  fi
  exit 0
}

require_https() {
  local url=$1
  [[ "${url,,}" == https://* ]] || cancel "Refusing non-HTTPS URL: $url"
}

section() {
  printf '\n%s▸ %s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"
  log_line "== $* =="
}

print_banner() {
  printf '\n%s%s%s%s v%s%s\n' "$C_BOLD" "$C_CYAN" "$APP_NAME" "$C_RESET$C_DIM" "$APP_VERSION" "$C_RESET"
  printf '%sCreate a Minecraft server in a few steps.%s\n' "$C_DIM" "$C_RESET"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but was not found."
}

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  die "Do not run this installer as root."
fi

log_line "Starting $APP_NAME v$APP_VERSION"
log_line "Working directory: $PWD"
log_line "Script: $0"

require_https "$MANIFEST_URL"
require_https "$FORGE_PROMOS_URL"
require_https "$FABRIC_LOADER_URL"
require_https "$FABRIC_INSTALLER_URL"
require_https "$NEOFORGE_MAVEN"
require_https "$ADOPTIUM_ASSETS_URL"

need_cmd curl
need_cmd tar

TMP_DIR=$(mktemp -d) || die "Could not create a temporary directory."
trap 'rm -rf "$TMP_DIR"' EXIT

compact_json() {
  tr -d '[:space:]' < "$1"
}

manifest_url() {
  compact_json "$1" \
    | tr '}' '\n' \
    | grep -F "\"id\":\"$2\"" \
    | head -n1 \
    | sed -n 's/.*"url":"\([^"]*\)".*/\1/p' || true
}

mc_server_url() {
  compact_json "$1" \
    | grep -o '"server":{[^}]*}' \
    | head -n1 \
    | sed -n 's/.*"url":"\([^"]*\)".*/\1/p' || true
}

mc_server_sha1() {
  compact_json "$1" \
    | grep -o '"server":{[^}]*}' \
    | head -n1 \
    | sed -n 's/.*"sha1":"\([^"]*\)".*/\1/p' || true
}

mc_java_major() {
  compact_json "$1" \
    | grep -o '"javaVersion":{[^}]*}' \
    | head -n1 \
    | sed -n 's/.*"majorVersion":\([0-9]*\).*/\1/p' || true
}

fabric_loader_version() {
  local compact first_any="" first_stable="" obj ver
  compact=$(compact_json "$1")
  while IFS= read -r obj; do
    ver=$(printf '%s' "$obj" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
    [[ -n "$ver" ]] || continue
    if [[ -z "$first_any" ]]; then first_any=$ver; fi
    if [[ "$obj" == *'"stable":true'* ]]; then
      first_stable=$ver
      break
    fi
  done < <(printf '%s' "$compact" | grep -o '"loader":{[^}]*}')
  printf '%s\n' "${first_stable:-$first_any}"
}

fabric_installer_version() {
  local compact first_any="" first_stable="" obj ver
  compact=$(compact_json "$1")
  while IFS= read -r obj; do
    ver=$(printf '%s' "$obj" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
    [[ -n "$ver" ]] || continue
    if [[ -z "$first_any" ]]; then first_any=$ver; fi
    if [[ "$obj" == *'"stable":true'* ]]; then
      first_stable=$ver
      break
    fi
  done < <(printf '%s' "$compact" | grep -o '{[^{}]*}')
  printf '%s\n' "${first_stable:-$first_any}"
}

forge_promoted_version() {
  local compact key key_re line
  compact=$(compact_json "$1")
  key="$2-recommended"
  key_re=${key//./\\.}
  line=$(printf '%s' "$compact" | grep -o "\"${key_re}\":\"[^\"]*\"" | head -n1 || true)
  if [[ -z "$line" ]]; then
    key="$2-latest"
    key_re=${key//./\\.}
    line=$(printf '%s' "$compact" | grep -o "\"${key_re}\":\"[^\"]*\"" | head -n1 || true)
  fi
  printf '%s\n' "$line" | sed 's/^[^:]*:"//; s/"$//'
}

neoforge_build_version() {
  local xml=$1 mc=$2 prefix base
  if [[ "$mc" == "1.20.1" ]]; then
    prefix="1.20.1-"
  elif [[ "$mc" == 1.* ]]; then
    base=${mc#1.}
    if [[ "$base" != *.* ]]; then base="$base.0"; fi
    prefix="$base."
  else
    if [[ "$mc" == *.*.* ]]; then
      prefix="$mc."
    else
      prefix="$mc.0."
    fi
  fi
  grep -o '<version>[^<]*</version>' "$xml" \
    | sed 's/<[^>]*>//g' \
    | awk -v p="$prefix" 'index($0,p)==1' \
    | grep -Ev -- '-(beta|alpha)|snapshot' \
    | awk -F. '{print $NF "\t" $0}' \
    | sort -k1,1n \
    | tail -n1 \
    | cut -f2- || true
}

adoptium_package_field() {
  local compact pkg
  compact=$(compact_json "$1")
  pkg=$(printf '%s' "$compact" | grep -o '"package":{[^}]*}' | head -n1 || true)
  if [[ "$2" == "size" ]]; then
    printf '%s\n' "$pkg" | sed -n 's/.*"size":\([0-9]*\).*/\1/p'
  else
    printf '%s\n' "$pkg" | sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p"
  fi
}

sha256_of() {
  local file=$1 out
  if command -v sha256sum >/dev/null 2>&1; then
    out=$(sha256sum "$file") || return 1
    printf '%s\n' "${out%% *}"
  elif command -v shasum >/dev/null 2>&1; then
    out=$(shasum -a 256 "$file") || return 1
    printf '%s\n' "${out%% *}"
  elif command -v openssl >/dev/null 2>&1; then
    out=$(openssl dgst -sha256 "$file") || return 1
    printf '%s\n' "${out##* }"
  else
    return 1
  fi
}

sha1_of() {
  local file=$1 out
  if command -v sha1sum >/dev/null 2>&1; then
    out=$(sha1sum "$file") || return 1
    printf '%s\n' "${out%% *}"
  elif command -v shasum >/dev/null 2>&1; then
    out=$(shasum -a 1 "$file") || return 1
    printf '%s\n' "${out%% *}"
  elif command -v openssl >/dev/null 2>&1; then
    out=$(openssl dgst -sha1 "$file") || return 1
    printf '%s\n' "${out##* }"
  else
    return 1
  fi
}

_ac_complete() {
  local line=$READLINE_LINE
  local point=$READLINE_POINT
  local left=${line:0:point}
  local word=${left##* }
  local before=${left%"$word"}
  local rest=${line:point}
  local matches=()
  local m lcp
  for m in "${AC_CANDIDATES[@]}"; do
    [[ "$m" == "$word"* ]] && matches+=("$m")
  done
  ((${#matches[@]})) || return 0
  if [[ -z "$word" && ${#matches[@]} -gt 10 ]]; then
    printf '\n  Type a prefix, then press Tab (e.g. 1.21, 26)\n'
    return 0
  fi
  if ((${#matches[@]} == 1)); then
    READLINE_LINE="$before${matches[0]}$rest"
    READLINE_POINT=$(( ${#before} + ${#matches[0]} ))
    return 0
  fi
  lcp=${matches[0]}
  for m in "${matches[@]:1}"; do
    while [[ "$m" != "$lcp"* ]]; do lcp=${lcp%?}; done
  done
  if ((${#lcp} > ${#word})); then
    READLINE_LINE="$before$lcp$rest"
    READLINE_POINT=$(( ${#before} + ${#lcp} ))
  else
    printf '\n  %s\n' "${matches[*]}"
  fi
}

read_complete() {
  local prompt="$1"
  shift
  AC_CANDIDATES=("$@")
  bind -x '"\t":_ac_complete' 2>/dev/null || true
  local answer=""
  if ! IFS= read -r -e -p "$prompt" answer; then
    bind '"\t": complete' 2>/dev/null || true
    AC_CANDIDATES=()
    die "Input interrupted."
  fi
  bind '"\t": complete' 2>/dev/null || true
  AC_CANDIDATES=()
  REPLY="$answer"
}

contains_version() {
  local v
  for v in "${VERSIONS[@]}"; do
    [[ "$v" == "$1" ]] && return 0
  done
  return 1
}

print_version_range() {
  local label=$1 lowest=$2 highest=$3
  if [[ "$lowest" == "$highest" ]]; then
    printf '  %s%-8s%s %s\n' "$C_DIM" "$label" "$C_RESET" "$lowest"
  else
    printf '  %s%-8s%s %s - %s\n' "$C_DIM" "$label" "$C_RESET" "$lowest" "$highest"
  fi
}

show_versions() {
  local v key rest last_key="" lowest="" highest=""
  for v in "${VERSIONS[@]}"; do
    if [[ "$v" == 1.* ]]; then
      rest=${v#1.}
      key="1.${rest%%.*}.x"
    else
      key="${v%%.*}.x"
    fi
    if [[ "$key" != "$last_key" ]]; then
      if [[ -n "$last_key" ]]; then
        print_version_range "$last_key" "$lowest" "$highest"
      fi
      last_key=$key
      highest=$v
      lowest=$v
    else
      lowest=$v
    fi
  done
  if [[ -n "$last_key" ]]; then
    print_version_range "$last_key" "$lowest" "$highest"
  fi
}

ask_name() {
  local name
  while :; do
    printf 'Server name %s(folder name)%s: ' "$C_DIM" "$C_RESET"
    IFS= read -r name || die "Input interrupted."
    case "$name" in
      ''|.|..) warn "Invalid name."; continue ;;
    esac
    if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
      warn "Use only letters, digits, '.', '_' and '-'."
      continue
    fi
    if [[ -e "./$name" ]]; then
      warn "Folder './$name' already exists."
      continue
    fi
    NAME="$name"
    SERVER_DIR="$PWD/$NAME"
    return
  done
}

ask_version() {
  section "Game version"
  log "Available versions (snapshots excluded):"
  show_versions
  local v
  while :; do
    read_complete "Version ${C_DIM}[${VERSIONS[0]}]${C_RESET}: " "${VERSIONS[@]}"
    v=$REPLY
    [[ -z "$v" ]] && v=${VERSIONS[0]}
    if contains_version "$v"; then
      VERSION="$v"
      break
    fi
    warn "'$v' is not a valid release from the list."
  done
  ok "Selected version: $VERSION"
}

ask_loader() {
  section "Mod loader"
  printf '  %s1%s vanilla   %sofficial server%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
  printf '  %s2%s fabric    %slightweight mods%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
  printf '  %s3%s forge     %sclassic mods%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
  printf '  %s4%s neoforge  %smodern Forge fork%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
  local v
  while :; do
    read_complete "Mod loader ${C_DIM}[vanilla]${C_RESET}: " vanilla fabric forge neoforge
    v=$REPLY
    [[ -z "$v" ]] && v="vanilla"
    case "$v" in
      1|vanilla) LOADER="vanilla"; break ;;
      2|fabric) LOADER="fabric"; break ;;
      3|forge) LOADER="forge"; break ;;
      4|neoforge) LOADER="neoforge"; break ;;
      *) warn "Invalid choice (1-4 or vanilla/fabric/forge/neoforge)." ;;
    esac
  done
  ok "Selected mod loader: $LOADER"
}

ask_memory() {
  section "Memory"
  local value
  while :; do
    printf 'Maximum memory in GB %s[2]%s: ' "$C_DIM" "$C_RESET"
    IFS= read -r value || die "Input interrupted."
    if [[ -z "$value" ]]; then
      value=2
    fi
    if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
      RAM_GB=$value
      break
    fi
    warn "Enter a whole number of gigabytes (1 or more)."
  done
  ok "Maximum memory: ${RAM_GB} GB"
}

fetch_mc_meta() {
  local manifest="$TMP_DIR/manifest.json"
  local meta_url
  curl "${CURL_HTTPS[@]}" -fsSL --retry 3 "$MANIFEST_URL" -o "$manifest" || die "Could not download the Mojang manifest."
  meta_url=$(manifest_url "$manifest" "$VERSION")
  [[ -n "$meta_url" ]] || die "Version $VERSION was not found in the Mojang manifest."
  require_https "$meta_url"
  MC_META="$TMP_DIR/mc-$VERSION.json"
  curl "${CURL_HTTPS[@]}" -fsSL --retry 3 "$meta_url" -o "$MC_META" || die "Could not download metadata for $VERSION."
  JAVA_REQUIRED=$(mc_java_major "$MC_META")
}

resolve_vanilla() {
  JAR_URL=$(mc_server_url "$MC_META")
  [[ -n "$JAR_URL" ]] || die "Vanilla server URL not found for $VERSION."
  require_https "$JAR_URL"
  JAR_SHA1=$(mc_server_sha1 "$MC_META")
  JAR_NAME="server.jar"
  LOADER_DETAIL="Vanilla"
}

resolve_fabric() {
  local loader_json="$TMP_DIR/fabric-loader.json"
  local installer_json="$TMP_DIR/fabric-installer.json"
  local loader installer
  curl "${CURL_HTTPS[@]}" -fsSL --retry 3 "${FABRIC_LOADER_URL}/${VERSION}" -o "$loader_json" 2>/dev/null \
    || die "Fabric does not support Minecraft $VERSION."
  loader=$(fabric_loader_version "$loader_json")
  [[ -n "$loader" ]] || die "No Fabric loader is available for Minecraft $VERSION."
  curl "${CURL_HTTPS[@]}" -fsSL --retry 3 "$FABRIC_INSTALLER_URL" -o "$installer_json" || die "Could not fetch the Fabric installer."
  installer=$(fabric_installer_version "$installer_json")
  [[ -n "$installer" ]] || die "Fabric installer version not found."
  JAR_URL="${FABRIC_LOADER_URL}/${VERSION}/${loader}/${installer}/server/jar"
  require_https "$JAR_URL"
  JAR_SHA1=""
  JAR_NAME="fabric-server-mc.${VERSION}-loader.${loader}-launcher.${installer}.jar"
  LOADER_DETAIL="Fabric loader ${loader} (installer ${installer})"
}

resolve_forge() {
  local promos="$TMP_DIR/forge-promos.json"
  local fv
  curl "${CURL_HTTPS[@]}" -fsSL --retry 3 "$FORGE_PROMOS_URL" -o "$promos" || die "Could not fetch Forge versions."
  fv=$(forge_promoted_version "$promos" "$VERSION")
  [[ -n "$fv" ]] || die "Forge has no build for Minecraft $VERSION."
  JAR_URL="https://maven.minecraftforge.net/net/minecraftforge/forge/${VERSION}-${fv}/forge-${VERSION}-${fv}-installer.jar"
  require_https "$JAR_URL"
  JAR_NAME="forge-${VERSION}-${fv}-installer.jar"
  JAR_SHA1=$(curl "${CURL_HTTPS[@]}" -fsSL --retry 3 "${JAR_URL}.sha1" 2>/dev/null | tr -d '[:space:]' || true)
  LOADER_DETAIL="Forge ${fv}"
}

resolve_neoforge() {
  local artifact xml fv
  if [[ "$VERSION" == "1.20.1" ]]; then
    artifact="forge"
    xml="$TMP_DIR/neoforge-forge.xml"
    curl "${CURL_HTTPS[@]}" -fsSL --retry 3 "${NEOFORGE_MAVEN}/forge/maven-metadata.xml" -o "$xml" || die "Could not fetch NeoForge versions."
  else
    artifact="neoforge"
    xml="$TMP_DIR/neoforge.xml"
    curl "${CURL_HTTPS[@]}" -fsSL --retry 3 "${NEOFORGE_MAVEN}/neoforge/maven-metadata.xml" -o "$xml" || die "Could not fetch NeoForge versions."
  fi
  fv=$(neoforge_build_version "$xml" "$VERSION")
  [[ -n "$fv" ]] || die "NeoForge has no stable build for Minecraft $VERSION (1.20.1 minimum; some versions are not supported)."
  if [[ "$artifact" == "forge" ]]; then
    JAR_URL="${NEOFORGE_MAVEN}/forge/${fv}/forge-${fv}-installer.jar"
  else
    JAR_URL="${NEOFORGE_MAVEN}/neoforge/${fv}/neoforge-${fv}-installer.jar"
  fi
  require_https "$JAR_URL"
  JAR_NAME="${artifact}-${fv}-installer.jar"
  JAR_SHA1=$(curl "${CURL_HTTPS[@]}" -fsSL --retry 3 "${JAR_URL}.sha1" 2>/dev/null | tr -d '[:space:]' || true)
  LOADER_DETAIL="NeoForge ${fv}"
}

resolve_jar() {
  fetch_mc_meta
  case "$LOADER" in
    vanilla) resolve_vanilla ;;
    fabric) resolve_fabric ;;
    forge) resolve_forge ;;
    neoforge) resolve_neoforge ;;
  esac
}

next_jdk_feature() {
  local required=$1 feature
  for feature in 17 21 25; do
    if (( feature >= required )); then
      printf '%s\n' "$feature"
      return 0
    fi
  done
  return 1
}

detect_system_java() {
  SYS_JAVA_MAJOR=""
  command -v java >/dev/null 2>&1 || return 1
  local raw
  raw=$(java -version 2>&1 | head -n1)
  raw=${raw#*\"}
  raw=${raw%%\"*}
  case "$raw" in
    1.*) SYS_JAVA_MAJOR=${raw#1.}; SYS_JAVA_MAJOR=${SYS_JAVA_MAJOR%%.*} ;;
    *) SYS_JAVA_MAJOR=${raw%%.*} ;;
  esac
  [[ "$SYS_JAVA_MAJOR" =~ ^[0-9]+$ ]] || return 1
  return 0
}

assess_java() {
  section "Java"
  [[ -n "$JAVA_REQUIRED" ]] || JAVA_REQUIRED=8
  JAVA_MODE="system"
  JAVA_BIN="java"
  JAVA_DETAIL=""
  JDK_FEATURE=""

  local have=0
  if detect_system_java; then
    have=1
  fi

  if (( have == 1 && SYS_JAVA_MAJOR >= JAVA_REQUIRED )); then
    JAVA_DETAIL="Java ${SYS_JAVA_MAJOR} (system)"
    ok "Java ${SYS_JAVA_MAJOR} detected (required: ${JAVA_REQUIRED}+)."
    if (( JAVA_REQUIRED <= 8 && SYS_JAVA_MAJOR > 8 )); then
      warn "Minecraft ${VERSION} may require Java ${JAVA_REQUIRED}; Java ${SYS_JAVA_MAJOR} might not work."
    fi
    return
  fi

  if (( have == 1 )); then
    warn "Java ${SYS_JAVA_MAJOR} detected, but Minecraft ${VERSION} requires Java ${JAVA_REQUIRED}+."
  else
    warn "Java was not found on this system."
  fi

  if ! JDK_FEATURE=$(next_jdk_feature "$JAVA_REQUIRED"); then
    die "No local JDK is available for Java ${JAVA_REQUIRED}+. Install it manually."
  fi

  local answer
  printf 'Download a local Temurin %s JDK into the server folder? %s[y/N]%s ' \
    "$JDK_FEATURE" "$C_DIM" "$C_RESET"
  IFS= read -r answer || die "Input interrupted."
  case "$answer" in
    y|Y|yes|Yes)
      JAVA_MODE="local"
      JAVA_DETAIL="Temurin ${JDK_FEATURE} (local, to download)"
      ;;
    *)
      cancel
      ;;
  esac
}

download_local_jdk() {
  local feature=$1
  local system arch api_url json meta link checksum filename size archive actual
  system=$(uname -s)
  [[ "$system" == "Linux" ]] || die "Automatic JDK download is only supported on Linux."
  case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) die "Unsupported architecture for JDK download: $(uname -m)." ;;
  esac

  section "Downloading Java ${feature}"
  log_line "Downloading local Temurin $feature JDK"
  api_url="${ADOPTIUM_ASSETS_URL}/${feature}/hotspot?architecture=${arch}&image_type=jdk&os=linux&vendor=eclipse"
  require_https "$api_url"
  json="$TMP_DIR/adoptium-${feature}.json"
  curl "${CURL_HTTPS[@]}" -fsSL --retry 3 "$api_url" -o "$json" || die "The Adoptium API is unreachable."
  link=$(adoptium_package_field "$json" "link")
  checksum=$(adoptium_package_field "$json" "checksum")
  filename=$(adoptium_package_field "$json" "name")
  size=$(adoptium_package_field "$json" "size")
  [[ -n "$link" && -n "$checksum" ]] || die "No Temurin ${feature} JDK is available for this platform."
  require_https "$link"

  archive="$SERVER_DIR/.jdk.tar.gz"
  log "Downloading ${filename} ($(( size / 1048576 )) MB)..."
  curl "${CURL_HTTPS[@]}" -fL --retry 3 --progress-bar -o "$archive" "$link" || die "JDK download failed."

  actual=$(sha256_of "$archive") || die "No SHA-256 tool found (sha256sum, shasum, or openssl)."
  if [[ "$actual" != "$checksum" ]]; then
    rm -f "$archive"
    die "Invalid SHA-256 checksum for the downloaded JDK."
  fi
  ok "SHA-256 checksum verified."

  LOCAL_JAVA_HOME="$SERVER_DIR/.jdk"
  rm -rf "$LOCAL_JAVA_HOME"
  mkdir -p "$LOCAL_JAVA_HOME"
  tar -xzf "$archive" -C "$LOCAL_JAVA_HOME" --strip-components=1 || die "JDK extraction failed."
  rm -f "$archive"
  [[ -x "$LOCAL_JAVA_HOME/bin/java" ]] || die "The extracted JDK is invalid."
  JAVA_BIN="$LOCAL_JAVA_HOME/bin/java"
  export JAVA_HOME="$LOCAL_JAVA_HOME"
  export PATH="$LOCAL_JAVA_HOME/bin:$PATH"
  log_line "Local JDK ready: $LOCAL_JAVA_HOME"
  ok "JDK ${feature} installed in .jdk"
}

print_summary() {
  section "Summary"
  printf '  %s%-11s%s %s\n' "$C_DIM" "Name" "$C_RESET" "$NAME"
  printf '  %s%-11s%s %s\n' "$C_DIM" "Folder" "$C_RESET" "$SERVER_DIR"
  printf '  %s%-11s%s %s\n' "$C_DIM" "Version" "$C_RESET" "$VERSION"
  printf '  %s%-11s%s %s\n' "$C_DIM" "Mod loader" "$C_RESET" "$LOADER"
  printf '  %s%-11s%s %s\n' "$C_DIM" "Detail" "$C_RESET" "$LOADER_DETAIL"
  printf '  %s%-11s%s %s\n' "$C_DIM" "Jar file" "$C_RESET" "$JAR_NAME"
  printf '  %s%-11s%s %s\n' "$C_DIM" "Max memory" "$C_RESET" "${RAM_GB} GB"
  printf '  %s%-11s%s %s\n' "$C_DIM" "Java" "$C_RESET" "$JAVA_DETAIL"
  printf '  %s%-11s%s\n' "$C_DIM" "Source" "$C_RESET"
  printf '    %s%s%s\n' "$C_DIM" "$JAR_URL" "$C_RESET"
  log_line "Summary: name=$NAME version=$VERSION loader=$LOADER detail=$LOADER_DETAIL jar=$JAR_NAME memory=${RAM_GB}GB java=$JAVA_DETAIL source=$JAR_URL"
}

confirm() {
  local answer
  printf 'Create this server? %s[y/N]%s ' "$C_DIM" "$C_RESET"
  IFS= read -r answer || die "Input interrupted."
  case "$answer" in
    y|Y|yes|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

accept_eula() {
  local answer
  printf 'Do you accept the Minecraft EULA? %s%s%s [y/N] ' "$C_DIM" "$EULA_URL" "$C_RESET"
  IFS= read -r answer || die "Input interrupted."
  case "$answer" in
    y|Y|yes|Yes) EULA_ACCEPTED=1; return 0 ;;
    *) return 1 ;;
  esac
}

write_run_script() {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'cd "$(dirname "$0")"\n'
    if [[ "$JAVA_MODE" == "local" ]]; then
      printf 'export JAVA_HOME="$PWD/.jdk"\n'
      printf 'export PATH="$JAVA_HOME/bin:$PATH"\n'
      printf 'exec "$JAVA_HOME/bin/java" -Xmx%sG -jar "%s" nogui\n' "$RAM_GB" "$JAR_NAME"
    else
      printf 'exec java -Xmx%sG -jar "%s" nogui\n' "$RAM_GB" "$JAR_NAME"
    fi
  } > run.sh
  chmod +x run.sh
}

write_eula() {
  (( EULA_ACCEPTED == 1 )) || die "The Minecraft EULA must be accepted before creating eula.txt."
  printf 'eula=true\n' > eula.txt
  log_line "Wrote eula.txt"
}

apply_forge_memory() {
  local args_file="user_jvm_args.txt"
  if [[ ! -f "$args_file" ]]; then
    warn "user_jvm_args.txt not found; memory settings were not applied."
    return 0
  fi
  local tmp
  tmp=$(mktemp "$TMP_DIR/jvm.XXXXXX") || die "Could not create a temporary file."
  awk -v ram="$RAM_GB" '
    /^[[:space:]]*-Xm[sx]/ { next }
    { print }
    END { printf "-Xmx%sG\n", ram }
  ' "$args_file" > "$tmp"
  mv "$tmp" "$args_file"
}

wrap_forge_run_script() {
  [[ "$JAVA_MODE" == "local" ]] || return 0
  [[ -f run.sh ]] || return 0
  mv run.sh run-server.sh
  {
    printf '#!/usr/bin/env bash\n'
    printf 'cd "$(dirname "$0")"\n'
    printf 'export JAVA_HOME="$PWD/.jdk"\n'
    printf 'export PATH="$JAVA_HOME/bin:$PATH"\n'
    printf 'exec ./run-server.sh "$@"\n'
  } > run.sh
  chmod +x run.sh run-server.sh
}

main() {
  print_banner
  ask_name
  ask_version
  ask_loader
  ask_memory
  resolve_jar
  assess_java
  print_summary
  if ! confirm; then
    log_line "Creation declined"
    cancel
  fi
  log_line "Creation confirmed"
  if ! accept_eula; then
    log_line "EULA declined"
    warn "You must accept the Minecraft EULA to continue."
    cancel
  fi
  log_line "EULA accepted"

  log_line "Creating server folder: $SERVER_DIR"
  mkdir -p "$SERVER_DIR" || die "Could not create folder '$SERVER_DIR'."
  cd "$SERVER_DIR" || die "Could not enter '$SERVER_DIR'."
  if ! start_logging; then
    warn "Could not create log file in $SERVER_DIR."
  fi
  log_line "Entered server folder: $SERVER_DIR"

  if [[ "$JAVA_MODE" == "local" ]]; then
    download_local_jdk "$JDK_FEATURE"
  fi

  section "Downloading server"
  log "File: $JAR_NAME"
  require_https "$JAR_URL"
  log_line "Downloading server: $JAR_URL"
  curl "${CURL_HTTPS[@]}" -fL --retry 3 --progress-bar -o "$JAR_NAME" "$JAR_URL" || die "Download failed."
  [[ -s "$JAR_NAME" ]] || die "The downloaded file is empty."

  if [[ -n "$JAR_SHA1" ]]; then
    local actual want
    if actual=$(sha1_of "$JAR_NAME"); then
      actual=$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')
      want=$(printf '%s' "$JAR_SHA1" | tr '[:upper:]' '[:lower:]')
      if [[ "$actual" != "$want" ]]; then
        rm -f "$JAR_NAME"
        die "Invalid SHA-1 checksum for the downloaded file."
      fi
      ok "SHA-1 checksum verified."
    else
      warn "No SHA-1 tool found (sha1sum, shasum, or openssl); skipping verification."
    fi
  fi

  if [[ "$LOADER" == "forge" || "$LOADER" == "neoforge" ]]; then
    section "Installing server ($LOADER)"
    log_line "Running $LOADER installer: $JAR_NAME"
    "$JAVA_BIN" -jar "$JAR_NAME" --installServer || die "Server installation failed."
    apply_forge_memory
    write_eula
    wrap_forge_run_script
    [[ -f run.sh ]] && chmod +x run.sh
    log_line "$LOADER installation finished"
  else
    write_run_script
    write_eula
  fi

  log_line "Server ready: $SERVER_DIR"
  printf '\n%s✔ Server ready%s in %s%s%s\n' "$C_BOLD$C_GREEN" "$C_RESET" "$C_BOLD" "$SERVER_DIR" "$C_RESET"
  printf '  Start: %scd "%s" && ./run.sh%s\n' "$C_DIM" "$SERVER_DIR" "$C_RESET"
  if [[ -n "$LOG_FILE" ]]; then
    printf '  Log: %s%s%s\n' "$C_DIM" "$LOG_FILE" "$C_RESET"
  fi
}

main "$@"
