#!/usr/bin/env bash
# Extrait la frame 1 de chaque GIF dans animated-back/ → back/ (PNG, convention D-16).
# Génère tools/missing-back-sprites.txt pour les sprites Gen 6→9 absents.
#
# Usage : bash extract-back-sprites.sh
# Prérequis : animated-back/ peuplé (download-sprites.sh), ImageMagick installé.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ANIM_BACK_DIR="$ROOT_DIR/sprites/animated-back"
BACK_DIR="$ROOT_DIR/sprites/back"
INDEX_FILE="$SCRIPT_DIR/pokemon-index.json"
MISSING_FILE="$SCRIPT_DIR/missing-back-sprites.txt"

log()  { echo "[INFO]  $*"; }
ok()   { echo "[OK]    $*"; }
warn() { echo "[WARN]  $*"; }
err()  { echo "[ERROR] $*"; exit 1; }

EXTRACTED=0
ERRORS=0

command -v convert &>/dev/null \
    || err "ImageMagick requis : sudo apt install imagemagick"
[ -d "$ANIM_BACK_DIR" ] \
    || err "Dossier absent : $ANIM_BACK_DIR — lancez download-sprites.sh d'abord"
[ -f "$INDEX_FILE" ] && [ "$(jq 'length' "$INDEX_FILE" 2>/dev/null)" -gt 0 ] \
    || err "pokemon-index.json absent — lancez build-index.sh d'abord"

mkdir -p "$BACK_DIR"

# ── 1. Extraction frame 0 de chaque *_animated-back.gif ─────────────────────

log "Extraction frame 1 depuis $(find "$ANIM_BACK_DIR" -maxdepth 1 -name '*_animated-back.gif' | wc -l) GIF..."

while IFS= read -r -d '' gif; do
    basename=$(basename "$gif")
    # 00025_pikachu_animated-back.gif → 00025_pikachu_back.png
    new_name="${basename/_animated-back.gif/_back.png}"
    dest="$BACK_DIR/$new_name"

    if convert "${gif}[0]" "$dest" 2>/dev/null; then
        EXTRACTED=$((EXTRACTED + 1))
    else
        warn "Échec extraction : $basename"
        ERRORS=$((ERRORS + 1))
    fi
done < <(find "$ANIM_BACK_DIR" -maxdepth 1 -name "*_animated-back.gif" -print0)

ok "Extraits : $EXTRACTED sprites PNG → $BACK_DIR"

# ── 2. Liste des back sprites manquants pour Gen 6→9 (dexid 650→1025) ───────
# Gen 5 se termine à 649 (Genesect). Gen 6→9 = 650→1025.

log "Recherche des back sprites manquants (Gen 6→9 : dexid 650→1025)..."

: > "$MISSING_FILE"
MISSING=0

for i in $(seq 650 1025); do
    padded=$(printf '%05d' "$i")
    if ! find "$BACK_DIR" -maxdepth 1 -name "${padded}_*_back.png" | grep -q .; then
        identifier=$(jq -r ".\"$i\" // empty" "$INDEX_FILE")
        if [ -n "$identifier" ]; then
            echo "${padded}_${identifier}" >> "$MISSING_FILE"
            MISSING=$((MISSING + 1))
        fi
    fi
done

ok "Manquants Gen 6→9 : $MISSING → $MISSING_FILE"

# ── Rapport final ─────────────────────────────────────────────────────────────

echo ""
echo "=== Rapport back sprites ====================================="
printf "%-35s %d fichiers\n" "back/ total"        "$(find "$BACK_DIR" -maxdepth 1 -name '*_back.png' | wc -l)"
printf "%-35s %d\n"          "Extraits (Gen 1→5)" "$EXTRACTED"
[ "$ERRORS" -gt 0 ] && \
printf "%-35s %d\n"          "Échecs extraction"  "$ERRORS"
printf "%-35s %d\n"          "Manquants Gen 6→9"  "$MISSING"
echo "=============================================================="
echo "Sprites Gen 6→9 à sourcer manuellement (Smogon / Eevee Expo)"
echo "Liste : $MISSING_FILE"
