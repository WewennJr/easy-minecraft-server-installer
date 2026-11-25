#!/usr/bin/env bash
set -euo pipefail

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
warn() { printf '%sAttention :%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%sErreur :%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
ok()   { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET"; }

section() {
  printf '\n%s▸ %s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"
}

print_banner() {
  printf '\n%s%s  ━━━  Création d'\''un serveur Minecraft  ━━━  %s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' est requis mais introuvable."
}

need_cmd curl
need_cmd python3

TMP_DIR=$(mktemp -d) || die "Impossible de créer un dossier temporaire."
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
    printf '\n  Tapez un préfixe puis Tab (ex: 1.21, 26)\n'
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
    die "Entrée interrompue."
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

show_versions() {
  local v key rest last="" line=""
  for v in "${VERSIONS[@]}"; do
    if [[ "$v" == 1.* ]]; then
      rest=${v#1.}
      key="1.${rest%%.*}.x"
    else
      key="${v%%.*}.x"
    fi
    if [[ "$key" != "$last" ]]; then
      if [[ -n "$last" ]]; then
        printf '  %s%-8s%s %s\n' "$C_DIM" "$last" "$C_RESET" "$line"
      fi
      last="$key"
      line="$v"
    else
      line+="  $v"
    fi
  done
  if [[ -n "$last" ]]; then
    printf '  %s%-8s%s %s\n' "$C_DIM" "$last" "$C_RESET" "$line"
  fi
}

ask_name() {
  local name
  while :; do
    printf 'Nom du serveur %s(nom du dossier)%s : ' "$C_DIM" "$C_RESET"
    IFS= read -r name || die "Entrée interrompue."
    case "$name" in
      ''|.|..) warn "Nom invalide."; continue ;;
    esac
    if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
      warn "Utilisez uniquement lettres, chiffres, '.', '_' et '-'."
      continue
    fi
    if [[ -e "./$name" ]]; then
      warn "Le dossier './$name' existe déjà."
      continue
    fi
    NAME="$name"
    SERVER_DIR="$PWD/$NAME"
    return
  done
}

ask_version() {
  section "Version du jeu"
  show_versions
  local v
  while :; do
    read_complete "Version ${C_DIM}[${VERSIONS[0]}]${C_RESET} : " "${VERSIONS[@]}"
    v=$REPLY
    [[ -z "$v" ]] && v=${VERSIONS[0]}
    if contains_version "$v"; then
      VERSION="$v"
      break
    fi
    warn "'$v' n'est pas une release valide de la liste."
  done
  ok "Version sélectionnée : $VERSION"
}

ask_loader() {
  section "Mod loader"
  printf '  %s1%s vanilla   %sserveur officiel%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
  printf '  %s2%s fabric    %smods légers%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
  printf '  %s3%s forge     %smods classiques%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
  printf '  %s4%s neoforge  %sfork moderne de Forge%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
  local v
  while :; do
    read_complete "Mod loader ${C_DIM}[vanilla]${C_RESET} : " vanilla fabric forge neoforge
    v=$REPLY
    [[ -z "$v" ]] && v="vanilla"
    case "$v" in
      1|vanilla) LOADER="vanilla"; break ;;
      2|fabric) LOADER="fabric"; break ;;
      3|forge) LOADER="forge"; break ;;
      4|neoforge) LOADER="neoforge"; break ;;
      *) warn "Choix invalide (1-4 ou vanilla/fabric/forge/neoforge)." ;;
    esac
  done
  ok "Mod loader sélectionné : $LOADER"
}

fetch_mc_meta() {
  local manifest="$TMP_DIR/manifest.json"
  local meta_url
  curl -fsSL --retry 3 "$MANIFEST_URL" -o "$manifest" || die "Téléchargement du manifest Mojang impossible."
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
  [[ -n "$meta_url" ]] || die "Version $VERSION introuvable dans le manifest Mojang."
  MC_META="$TMP_DIR/mc-$VERSION.json"
  curl -fsSL --retry 3 "$meta_url" -o "$MC_META" || die "Téléchargement des métadonnées de $VERSION impossible."
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
) || die "URL du serveur vanilla introuvable pour $VERSION."
  JAR_NAME="server.jar"
  LOADER_DETAIL="Vanilla"
}

resolve_fabric() {
  local loader_json="$TMP_DIR/fabric-loader.json"
  local installer_json="$TMP_DIR/fabric-installer.json"
  local loader installer
  curl -fsSL --retry 3 "${FABRIC_LOADER_URL}/${VERSION}" -o "$loader_json" 2>/dev/null \
    || die "Fabric ne supporte pas Minecraft $VERSION."
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
) || die "Aucun loader Fabric disponible pour Minecraft $VERSION."
  curl -fsSL --retry 3 "$FABRIC_INSTALLER_URL" -o "$installer_json" || die "Récupération de l'installateur Fabric impossible."
  installer=$(python3 - "$installer_json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
stable = [entry for entry in data if entry.get("stable")]
print((stable or data)[0]["version"])
PY
) || die "Version de l'installateur Fabric introuvable."
  JAR_URL="${FABRIC_LOADER_URL}/${VERSION}/${loader}/${installer}/server/jar"
  JAR_NAME="fabric-server-mc.${VERSION}-loader.${loader}-launcher.${installer}.jar"
  LOADER_DETAIL="Fabric loader ${loader} (installer ${installer})"
}

resolve_forge() {
  local promos="$TMP_DIR/forge-promos.json"
  local fv
  curl -fsSL --retry 3 "$FORGE_PROMOS_URL" -o "$promos" || die "Récupération des versions Forge impossible."
  fv=$(python3 - "$promos" "$VERSION" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    promos = json.load(handle).get("promos", {})
mc = sys.argv[2]
print(promos.get(mc + "-recommended") or promos.get(mc + "-latest") or "")
PY
) || fv=""
  [[ -n "$fv" ]] || die "Forge n'a pas de build pour Minecraft $VERSION."
  JAR_URL="https://maven.minecraftforge.net/net/minecraftforge/forge/${VERSION}-${fv}/forge-${VERSION}-${fv}-installer.jar"
  JAR_NAME="forge-${VERSION}-${fv}-installer.jar"
  LOADER_DETAIL="Forge ${fv}"
}

resolve_neoforge() {
  local artifact xml fv
  if [[ "$VERSION" == "1.20.1" ]]; then
    artifact="forge"
    xml="$TMP_DIR/neoforge-forge.xml"
    curl -fsSL --retry 3 "${NEOFORGE_MAVEN}/forge/maven-metadata.xml" -o "$xml" || die "Récupération des versions NeoForge impossible."
  else
    artifact="neoforge"
    xml="$TMP_DIR/neoforge.xml"
    curl -fsSL --retry 3 "${NEOFORGE_MAVEN}/neoforge/maven-metadata.xml" -o "$xml" || die "Récupération des versions NeoForge impossible."
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
  [[ -n "$fv" ]] || die "NeoForge n'a pas de build stable pour Minecraft $VERSION (minimum 1.20.1, certaines versions ne sont pas supportées)."
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
    JAVA_DETAIL="Java ${SYS_JAVA_MAJOR} (système)"
    ok "Java ${SYS_JAVA_MAJOR} détecté (requis : ${JAVA_REQUIRED}+)."
    if (( JAVA_REQUIRED <= 8 && SYS_JAVA_MAJOR > 8 )); then
      warn "Cette ancienne version peut malgré tout nécessiter Java ${JAVA_REQUIRED} ; Java ${SYS_JAVA_MAJOR} peut poser problème."
    fi
    return
  fi

  if (( have == 1 )); then
    warn "Java ${SYS_JAVA_MAJOR} détecté, mais Minecraft ${VERSION} demande Java ${JAVA_REQUIRED}+."
  else
    warn "Java est introuvable sur ce système."
  fi

  if ! JDK_FEATURE=$(next_jdk_feature "$JAVA_REQUIRED"); then
    if [[ "$LOADER" == "forge" || "$LOADER" == "neoforge" ]]; then
      die "Aucun JDK local connu pour Java ${JAVA_REQUIRED}+. Installe-le manuellement."
    fi
    JAVA_MODE="none"
    JAVA_DETAIL="absent (serveur non lançable sans Java)"
    warn "Aucun JDK local connu pour Java ${JAVA_REQUIRED}+."
    return
  fi

  local answer
  printf 'Télécharger un JDK Temurin %s local dans le dossier du serveur ? %s[o/N]%s ' \
    "$JDK_FEATURE" "$C_DIM" "$C_RESET"
  IFS= read -r answer || die "Entrée interrompue."
  case "$answer" in
    o|O|oui|Oui|y|Y|yes|Yes)
      JAVA_MODE="local"
      JAVA_DETAIL="Temurin ${JDK_FEATURE} (local, à télécharger)"
      ;;
    *)
      if (( have == 1 )); then
        JAVA_DETAIL="Java ${SYS_JAVA_MAJOR} (système, trop ancien)"
        warn "On continue avec Java ${SYS_JAVA_MAJOR} ; l'installation ou le démarrage peut échouer."
      else
        if [[ "$LOADER" == "forge" || "$LOADER" == "neoforge" ]]; then
          die "Java est requis pour installer Forge/NeoForge."
        fi
        JAVA_MODE="none"
        JAVA_DETAIL="absent (serveur non lançable sans Java)"
        warn "Le serveur sera créé, mais il ne pourra pas démarrer sans Java."
      fi
      ;;
  esac
}

download_local_jdk() {
  local feature=$1
  need_cmd tar
  local system arch api_url json meta link checksum filename size archive actual
  system=$(uname -s)
  [[ "$system" == "Linux" ]] || die "Le téléchargement automatique du JDK n'est supporté que sous Linux."
  case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) die "Architecture non supportée pour le téléchargement du JDK : $(uname -m)." ;;
  esac

  section "Téléchargement de Java ${feature}"
  api_url="${ADOPTIUM_ASSETS_URL}/${feature}/hotspot?architecture=${arch}&image_type=jdk&os=linux&vendor=eclipse"
  json="$TMP_DIR/adoptium-${feature}.json"
  curl -fsSL --retry 3 "$api_url" -o "$json" || die "API Adoptium inaccessible."
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
  [[ -n "$meta" ]] || die "Aucun JDK Temurin ${feature} disponible pour cette plateforme."
  IFS=$'\t' read -r link checksum filename size <<<"$meta"
  [[ -n "$link" && -n "$checksum" ]] || die "Métadonnées JDK incomplètes."

  archive="$SERVER_DIR/.jdk.tar.gz"
  log "Téléchargement de ${filename} ($(( size / 1048576 )) Mo)..."
  curl -fL --retry 3 --progress-bar -o "$archive" "$link" || die "Téléchargement du JDK échoué."

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
    die "Checksum SHA-256 invalide pour le JDK téléchargé."
  fi
  ok "Checksum SHA-256 vérifié."

  LOCAL_JAVA_HOME="$SERVER_DIR/.jdk"
  rm -rf "$LOCAL_JAVA_HOME"
  mkdir -p "$LOCAL_JAVA_HOME"
  tar -xzf "$archive" -C "$LOCAL_JAVA_HOME" --strip-components=1 || die "Extraction du JDK impossible."
  rm -f "$archive"
  [[ -x "$LOCAL_JAVA_HOME/bin/java" ]] || die "JDK extrait invalide."
  JAVA_BIN="$LOCAL_JAVA_HOME/bin/java"
  export JAVA_HOME="$LOCAL_JAVA_HOME"
  export PATH="$LOCAL_JAVA_HOME/bin:$PATH"
  ok "JDK ${feature} installé dans ${C_DIM}.jdk${C_RESET}"
}

print_summary() {
  printf '\n%s┌─ Résumé ─────────────────────────────────┐%s\n' "$C_CYAN" "$C_RESET"
  printf '  %s%-12s%s : %s%s%s\n' "$C_DIM" "Nom" "$C_RESET" "$C_BOLD" "$NAME" "$C_RESET"
  printf '  %s%-12s%s : %s\n' "$C_DIM" "Dossier" "$C_RESET" "$SERVER_DIR"
  printf '  %s%-12s%s : %s\n' "$C_DIM" "Version" "$C_RESET" "$VERSION"
  printf '  %s%-12s%s : %s\n' "$C_DIM" "Mod loader" "$C_RESET" "$LOADER"
  printf '  %s%-12s%s : %s\n' "$C_DIM" "Détail" "$C_RESET" "$LOADER_DETAIL"
  printf '  %s%-12s%s : %s\n' "$C_DIM" "Fichier jar" "$C_RESET" "$JAR_NAME"
  printf '  %s%-12s%s : %s\n' "$C_DIM" "Source" "$C_RESET" "$JAR_URL"
  printf '  %s%-12s%s : %s\n' "$C_DIM" "Java" "$C_RESET" "$JAVA_DETAIL"
  printf '%s└──────────────────────────────────────────┘%s\n' "$C_CYAN" "$C_RESET"
}

confirm() {
  local answer
  printf 'Créer ce serveur ? %s[o/N]%s ' "$C_DIM" "$C_RESET"
  IFS= read -r answer || die "Entrée interrompue."
  case "$answer" in
    o|O|oui|Oui|y|Y|yes|Yes) return 0 ;;
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
    log "Annulé."
    exit 0
  fi

  mkdir -p "$SERVER_DIR" || die "Impossible de créer le dossier '$SERVER_DIR'."
  cd "$SERVER_DIR" || die "Impossible d'entrer dans '$SERVER_DIR'."

  if [[ "$JAVA_MODE" == "local" ]]; then
    download_local_jdk "$JDK_FEATURE"
  fi

  section "Téléchargement du serveur"
  log "Fichier : $JAR_NAME"
  curl -fL --retry 3 --progress-bar -o "$JAR_NAME" "$JAR_URL" || die "Téléchargement échoué."
  [[ -s "$JAR_NAME" ]] || die "Le fichier téléchargé est vide."

  if [[ "$LOADER" == "forge" || "$LOADER" == "neoforge" ]]; then
    section "Installation du serveur ($LOADER)"
    "$JAVA_BIN" -jar "$JAR_NAME" --installServer || die "L'installation du serveur a échoué."
    printf 'eula=true\n' > eula.txt
    wrap_forge_run_script
    [[ -f run.sh ]] && chmod +x run.sh
  else
    write_run_script
    printf 'eula=true\n' > eula.txt
  fi

  printf '\n%s✔ Serveur prêt%s dans %s%s%s\n' "$C_BOLD$C_GREEN" "$C_RESET" "$C_BOLD" "$SERVER_DIR" "$C_RESET"
  printf '  Lancement : %scd "%s" && ./run.sh%s\n' "$C_DIM" "$SERVER_DIR" "$C_RESET"
}

main "$@"
