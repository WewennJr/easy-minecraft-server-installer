#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Easy Minecraft Server Installer"
APP_VERSION="1.0.0"

VERSIONS=(
  26.3 26.2 26.1.2 26.1.1 26.1
  1.21.11 1.21.10 1.21.9 1.21.8 1.21.7 1.21.6 1.21.5 1.21.4 1.21.3 1.21.2 1.21.1 1.21
  1.20.6 1.20.5 1.20.4 1.20.3 1.20.2 1.20.1 1.20
  1.19.4 1.19.3 1.19.2 1.19.1 1.19
  1.18.2 1.18.1 1.18
  1.17.1 1.17
  1.16.5 1.16.4 1.16.3 1.16.2 1.16.1 1.16
  1.8.9
)

MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
FORGE_PROMOS_URL="https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json"
FABRIC_LOADER_URL="https://meta.fabricmc.net/v2/versions/loader"
FABRIC_INSTALLER_URL="https://meta.fabricmc.net/v2/versions/installer"
NEOFORGE_MAVEN="https://maven.neoforged.net/releases/net/neoforged"
ADOPTIUM_ASSETS_URL="https://api.adoptium.net/v3/assets/latest"

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
JAR_NAME=""
JAR_URL=""
LOADER_DETAIL=""
JAVA_REQUIRED=""
MC_META=""
SERVER_DIR=""

JAVA_MODE="system"
JAVA_BIN="java"
JAVA_DETAIL=""
SYS_JAVA_MAJOR=""
JDK_FEATURE=""
LOCAL_JAVA_HOME=""

AC_CANDIDATES=()

log()  { printf '%s\n' "$*"; }
warn() { printf '%sWarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%sError:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
ok()   { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
cancel() { printf '%sCancelled.%s\n' "$C_YELLOW" "$C_RESET"; exit 0; }

section() {
  printf '\n%s▸ %s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"
}

print_banner() {
  printf '\n%s%s%s%s v%s%s\n' "$C_BOLD" "$C_CYAN" "$APP_NAME" "$C_RESET$C_DIM" "$APP_VERSION" "$C_RESET"
  printf '%sCreate a Minecraft server in a few steps.%s\n' "$C_DIM" "$C_RESET"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but was not found."
}

need_cmd curl
need_cmd python3

TMP_DIR=$(mktemp -d) || die "Could not create a temporary directory."
trap 'rm -rf "$TMP_DIR"' EXIT

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

fetch_mc_meta() {
  local manifest="$TMP_DIR/manifest.json"
  local meta_url
  curl -fsSL --retry 3 "$MANIFEST_URL" -o "$manifest" || die "Could not download the Mojang manifest."
  meta_url=$(python3 - "$manifest" "$VERSION" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
for entry in data.get("versions", []):
    if entry.get("id") == sys.argv[2] and entry.get("type") == "release":
        print(entry["url"])
        break
PY
) || meta_url=""
  [[ -n "$meta_url" ]] || die "Version $VERSION was not found in the Mojang manifest."
  MC_META="$TMP_DIR/mc-$VERSION.json"
  curl -fsSL --retry 3 "$meta_url" -o "$MC_META" || die "Could not download metadata for $VERSION."
  JAVA_REQUIRED=$(python3 - "$MC_META" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
print(data.get("javaVersion", {}).get("majorVersion", ""))
PY
) || JAVA_REQUIRED=""
}

resolve_vanilla() {
  JAR_URL=$(python3 - "$MC_META" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
print(data["downloads"]["server"]["url"])
PY
) || die "Vanilla server URL not found for $VERSION."
  JAR_NAME="server.jar"
  LOADER_DETAIL="Vanilla"
}

resolve_fabric() {
  local loader_json="$TMP_DIR/fabric-loader.json"
  local installer_json="$TMP_DIR/fabric-installer.json"
  local loader installer
  curl -fsSL --retry 3 "${FABRIC_LOADER_URL}/${VERSION}" -o "$loader_json" 2>/dev/null \
    || die "Fabric does not support Minecraft $VERSION."
  loader=$(python3 - "$loader_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
if not data:
    sys.exit(1)
stable = [entry["loader"] for entry in data if entry.get("loader", {}).get("stable")]
print((stable or [data[0]["loader"]])[0]["version"])
PY
) || die "No Fabric loader is available for Minecraft $VERSION."
  curl -fsSL --retry 3 "$FABRIC_INSTALLER_URL" -o "$installer_json" || die "Could not fetch the Fabric installer."
  installer=$(python3 - "$installer_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
stable = [entry for entry in data if entry.get("stable")]
print((stable or data)[0]["version"])
PY
) || die "Fabric installer version not found."
  JAR_URL="${FABRIC_LOADER_URL}/${VERSION}/${loader}/${installer}/server/jar"
  JAR_NAME="fabric-server-mc.${VERSION}-loader.${loader}-launcher.${installer}.jar"
  LOADER_DETAIL="Fabric loader ${loader} (installer ${installer})"
}

resolve_forge() {
  local promos="$TMP_DIR/forge-promos.json"
  local fv
  curl -fsSL --retry 3 "$FORGE_PROMOS_URL" -o "$promos" || die "Could not fetch Forge versions."
  fv=$(python3 - "$promos" "$VERSION" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    promos = json.load(handle).get("promos", {})
mc = sys.argv[2]
print(promos.get(mc + "-recommended") or promos.get(mc + "-latest") or "")
PY
) || fv=""
  [[ -n "$fv" ]] || die "Forge has no build for Minecraft $VERSION."
  JAR_URL="https://maven.minecraftforge.net/net/minecraftforge/forge/${VERSION}-${fv}/forge-${VERSION}-${fv}-installer.jar"
  JAR_NAME="forge-${VERSION}-${fv}-installer.jar"
  LOADER_DETAIL="Forge ${fv}"
}

resolve_neoforge() {
  local artifact xml fv
  if [[ "$VERSION" == "1.20.1" ]]; then
    artifact="forge"
    xml="$TMP_DIR/neoforge-forge.xml"
    curl -fsSL --retry 3 "${NEOFORGE_MAVEN}/forge/maven-metadata.xml" -o "$xml" || die "Could not fetch NeoForge versions."
  else
    artifact="neoforge"
    xml="$TMP_DIR/neoforge.xml"
    curl -fsSL --retry 3 "${NEOFORGE_MAVEN}/neoforge/maven-metadata.xml" -o "$xml" || die "Could not fetch NeoForge versions."
  fi
  fv=$(python3 - "$xml" "$VERSION" <<'PY'
import re
import sys

mc = sys.argv[2]
if mc == "1.20.1":
    prefix = "1.20.1-"
elif mc.startswith("1."):
    base = mc[2:]
    if "." not in base:
        base += ".0"
    prefix = base + "."
else:
    prefix = mc + (".0." if mc.count(".") == 1 else ".")

with open(sys.argv[1], encoding="utf-8") as handle:
    xml = handle.read()
versions = re.findall(r"<version>([^<]+)</version>", xml)
eligible = []
for version in versions:
    low = version.lower()
    if not version.startswith(prefix):
        continue
    if "-beta" in low or "-alpha" in low or "snapshot" in low:
        continue
    eligible.append(version)
eligible.sort(key=lambda value: tuple(int(x) for x in re.findall(r"\d+", value)))
print(eligible[-1] if eligible else "")
PY
) || fv=""
  [[ -n "$fv" ]] || die "NeoForge has no stable build for Minecraft $VERSION (1.20.1 minimum; some versions are not supported)."
  if [[ "$artifact" == "forge" ]]; then
    JAR_URL="${NEOFORGE_MAVEN}/forge/${fv}/forge-${fv}-installer.jar"
  else
    JAR_URL="${NEOFORGE_MAVEN}/neoforge/${fv}/neoforge-${fv}-installer.jar"
  fi
  JAR_NAME="${artifact}-${fv}-installer.jar"
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
  for feature in 8 11 17 21 25; do
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
  need_cmd tar
  local system arch api_url json meta link checksum filename size archive actual
  system=$(uname -s)
  [[ "$system" == "Linux" ]] || die "Automatic JDK download is only supported on Linux."
  case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) die "Unsupported architecture for JDK download: $(uname -m)." ;;
  esac

  section "Downloading Java ${feature}"
  api_url="${ADOPTIUM_ASSETS_URL}/${feature}/hotspot?architecture=${arch}&image_type=jdk&os=linux&vendor=eclipse"
  json="$TMP_DIR/adoptium-${feature}.json"
  curl -fsSL --retry 3 "$api_url" -o "$json" || die "The Adoptium API is unreachable."
  meta=$(python3 - "$json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
for entry in data:
    package = entry.get("binary", {}).get("package", {})
    name = package.get("name", "")
    if name.endswith(".tar.gz"):
        print("\t".join([
            package.get("link", ""),
            package.get("checksum", ""),
            name,
            str(package.get("size", 0)),
        ]))
        break
PY
) || meta=""
  [[ -n "$meta" ]] || die "No Temurin ${feature} JDK is available for this platform."
  IFS=$'\t' read -r link checksum filename size <<<"$meta"
  [[ -n "$link" && -n "$checksum" ]] || die "Incomplete JDK metadata."

  archive="$SERVER_DIR/.jdk.tar.gz"
  log "Downloading ${filename} ($(( size / 1048576 )) MB)..."
  curl -fL --retry 3 --progress-bar -o "$archive" "$link" || die "JDK download failed."

  actual=$(python3 - "$archive" <<'PY'
import hashlib
import sys

digest = hashlib.sha256()
with open(sys.argv[1], "rb") as handle:
    for chunk in iter(lambda: handle.read(1048576), b""):
        digest.update(chunk)
print(digest.hexdigest())
PY
) || actual=""
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
  printf '  %s%-11s%s %s\n' "$C_DIM" "Java" "$C_RESET" "$JAVA_DETAIL"
  printf '  %s%-11s%s\n' "$C_DIM" "Source" "$C_RESET"
  printf '    %s%s%s\n' "$C_DIM" "$JAR_URL" "$C_RESET"
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

write_run_script() {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'cd "$(dirname "$0")"\n'
    if [[ "$JAVA_MODE" == "local" ]]; then
      printf 'export JAVA_HOME="$PWD/.jdk"\n'
      printf 'export PATH="$JAVA_HOME/bin:$PATH"\n'
      printf 'exec "$JAVA_HOME/bin/java" -jar "%s" nogui\n' "$JAR_NAME"
    else
      printf 'exec java -jar "%s" nogui\n' "$JAR_NAME"
    fi
  } > run.sh
  chmod +x run.sh
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
  resolve_jar
  assess_java
  print_summary
  if ! confirm; then
    cancel
  fi

  mkdir -p "$SERVER_DIR" || die "Could not create folder '$SERVER_DIR'."
  cd "$SERVER_DIR" || die "Could not enter '$SERVER_DIR'."

  if [[ "$JAVA_MODE" == "local" ]]; then
    download_local_jdk "$JDK_FEATURE"
  fi

  section "Downloading server"
  log "File: $JAR_NAME"
  curl -fL --retry 3 --progress-bar -o "$JAR_NAME" "$JAR_URL" || die "Download failed."
  [[ -s "$JAR_NAME" ]] || die "The downloaded file is empty."

  if [[ "$LOADER" == "forge" || "$LOADER" == "neoforge" ]]; then
    section "Installing server ($LOADER)"
    "$JAVA_BIN" -jar "$JAR_NAME" --installServer || die "Server installation failed."
    printf 'eula=true\n' > eula.txt
    wrap_forge_run_script
    [[ -f run.sh ]] && chmod +x run.sh
  else
    write_run_script
    printf 'eula=true\n' > eula.txt
  fi

  printf '\n%s✔ Server ready%s in %s%s%s\n' "$C_BOLD$C_GREEN" "$C_RESET" "$C_BOLD" "$SERVER_DIR" "$C_RESET"
  printf '  Start: %scd "%s" && ./run.sh%s\n' "$C_DIM" "$SERVER_DIR" "$C_RESET"
}

main "$@"
