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

NAME=""
VERSION=""
LOADER=""
JAR_NAME=""
JAR_URL=""
LOADER_DETAIL=""
JAVA_REQUIRED=""
JAVA_MAJOR=""
MC_META=""

log()  { printf '%s\n' "$*"; }
warn() { printf 'Attention : %s\n' "$*" >&2; }
die()  { printf 'Erreur : %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' est requis mais introuvable."
}

need_cmd curl
need_cmd python3

TMP_DIR=$(mktemp -d) || die "Impossible de créer un dossier temporaire."
trap 'rm -rf "$TMP_DIR"' EXIT

contains_version() {
  local v
  for v in "${VERSIONS[@]}"; do
    [[ "$v" == "$1" ]] && return 0
  done
  return 1
}

ask_name() {
  local name
  while :; do
    printf 'Nom du serveur (nom du dossier) : '
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
    return
  done
}

ask_version() {
  local v
  log ""
  log "Versions disponibles (snapshots exclus) :"
  printf '  %s\n' "${VERSIONS[*]}"
  while :; do
    printf 'Version du jeu : '
    IFS= read -r v || die "Entrée interrompue."
    if contains_version "$v"; then
      VERSION="$v"
      return
    fi
    warn "'$v' n'est pas une release valide de la liste."
  done
}

ask_loader() {
  local v
  log ""
  log "Mod loaders disponibles :"
  log "  1) vanilla"
  log "  2) fabric"
  log "  3) forge"
  log "  4) neoforge"
  while :; do
    printf 'Mod loader : '
    IFS= read -r v || die "Entrée interrompue."
    case "$v" in
      1|vanilla) LOADER="vanilla"; return ;;
      2|fabric) LOADER="fabric"; return ;;
      3|forge) LOADER="forge"; return ;;
      4|neoforge) LOADER="neoforge"; return ;;
      *) warn "Choix invalide (1-4 ou vanilla/fabric/forge/neoforge)." ;;
    esac
  done
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

check_java() {
  if ! command -v java >/dev/null 2>&1; then
    JAVA_MAJOR=""
    warn "Java est introuvable. Il sera nécessaire pour installer ou lancer le serveur."
    return
  fi
  local raw
  raw=$(java -version 2>&1 | head -n1)
  raw=${raw#*\"}
  raw=${raw%%\"*}
  case "$raw" in
    1.*) JAVA_MAJOR=${raw#1.}; JAVA_MAJOR=${JAVA_MAJOR%%.*} ;;
    *) JAVA_MAJOR=${raw%%.*} ;;
  esac
  if [[ -n "$JAVA_REQUIRED" && "$JAVA_MAJOR" =~ ^[0-9]+$ && "$JAVA_MAJOR" -lt "$JAVA_REQUIRED" ]]; then
    warn "Java $JAVA_MAJOR détecté, mais Minecraft $VERSION demande Java $JAVA_REQUIRED (ou plus)."
    warn "L'installation ou le démarrage du serveur peut échouer."
  fi
}

print_summary() {
  log ""
  log "================ Résumé ================"
  log "Nom          : $NAME"
  log "Dossier      : $PWD/$NAME"
  log "Version      : $VERSION"
  log "Mod loader   : $LOADER"
  log "Détail       : $LOADER_DETAIL"
  log "Fichier jar  : $JAR_NAME"
  log "Source       : $JAR_URL"
  if [[ -n "$JAVA_REQUIRED" ]]; then
    log "Java requis  : $JAVA_REQUIRED+ (détecté : ${JAVA_MAJOR:-absent})"
  fi
  log "========================================"
}

confirm() {
  local answer
  printf 'Créer ce serveur ? [o/N] '
  IFS= read -r answer || die "Entrée interrompue."
  case "$answer" in
    o|O|oui|Oui|y|Y|yes|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

main() {
  log "=== Création d'un serveur Minecraft ==="
  ask_name
  ask_version
  ask_loader
  resolve_jar
  check_java
  print_summary
  if ! confirm; then
    log "Annulé."
    exit 0
  fi
  mkdir -p "./$NAME" || die "Impossible de créer le dossier './$NAME'."
  cd "./$NAME" || die "Impossible d'entrer dans './$NAME'."
  log ""
  log "Téléchargement de $JAR_NAME ..."
  curl -fL --retry 3 --progress-bar -o "$JAR_NAME" "$JAR_URL" || die "Téléchargement échoué."
  [[ -s "$JAR_NAME" ]] || die "Le fichier téléchargé est vide."
  if [[ "$LOADER" == "forge" || "$LOADER" == "neoforge" ]]; then
    log "Installation du serveur ($LOADER) ..."
    java -jar "$JAR_NAME" --installServer || die "L'installation du serveur a échoué."
    printf 'eula=true\n' > eula.txt
    [[ -f run.sh ]] && chmod +x run.sh
  else
    {
      printf '#!/usr/bin/env bash\n'
      printf 'cd "$(dirname "$0")"\n'
      printf 'exec java -jar "%s" nogui\n' "$JAR_NAME"
    } > run.sh
    chmod +x run.sh
    printf 'eula=true\n' > eula.txt
  fi
  log ""
  log "Serveur créé dans : $PWD"
  log "Lancement          : cd \"$PWD\" && ./run.sh"
}

main "$@"
