#!/usr/bin/env bash
# Clone PokeAPI/cries et renomme les OGG selon D-16.
# Convention D-16 : {dexid5}_{identifier}.ogg  (pas de view pour les cris)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
INDEX_FILE="$SCRIPT_DIR/pokemon-index.json"
TMP_DIR="$SCRIPT_DIR/tmp/cries-repo"
DEST="$ROOT_DIR/audio/cries"
CRIES_REPO="https://github.com/PokeAPI/cries"

log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*"; }
ok()   { echo "[OK]    $*"; }
err()  { echo "[ERROR] $*"; exit 1; }

RENAMED=0
ERRORS=0

for dep in git jq; do
    command -v "$dep" &>/dev/null || err "$dep requis : sudo apt install $dep"
done

if [ ! -f "$INDEX_FILE" ] || [ "$(jq 'length' "$INDEX_FILE")" -eq 0 ]; then
    log "pokemon-index.json absent ou vide — lancement de build-index.sh..."
    bash "$SCRIPT_DIR/build-index.sh" || err "Échec de build-index.sh"
fi

lookup_identifier() {
    jq -r ".\"$1\" // empty" "$INDEX_FILE"
}

mkdir -p "$DEST"
rm -rf "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

log "Clonage de $CRIES_REPO..."
git clone --depth=1 "$CRIES_REPO" "$TMP_DIR"

OGG_SOURCE="$TMP_DIR/cries/pokemon/latest"
[ -d "$OGG_SOURCE" ] || err "Dossier source introuvable : $OGG_SOURCE — structure du repo changée ?"

log "Renommage et copie selon D-16..."
while IFS= read -r -d '' src; do
    basename=$(basename "$src")
    name="${basename%.*}"   # ex: "25"

    # Extrait dexid (numérique pur — PokeAPI/cries utilise l'id numérique)
    if [[ "$name" =~ ^([0-9]+)$ ]]; then
        dexid="${BASH_REMATCH[1]}"
    else
        warn "Nom OGG non numérique, ignoré : $basename"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    identifier=$(lookup_identifier "$dexid")
    if [ -z "$identifier" ]; then
        warn "dexid $dexid absent de l'index, ignoré : $basename"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    padded=$(printf '%05d' "$dexid")
    new_name="${padded}_${identifier}.ogg"

    cp "$src" "$DEST/$new_name"
    RENAMED=$((RENAMED + 1))
done < <(find "$OGG_SOURCE" -maxdepth 1 -name "*.ogg" -print0)

echo ""
echo "=== Rapport ================================================="
ok "Cris renommés  : $RENAMED → $DEST"
[ "$ERRORS" -gt 0 ] && warn "Fichiers ignorés : $ERRORS"
echo "============================================================="
[ "$ERRORS" -eq 0 ] && echo "Succès. Lancez validate-assets.sh pour vérifier." \
                     || echo "Certains cris n'ont pas pu être renommés. Voir les WARN ci-dessus."
