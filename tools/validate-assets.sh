#!/usr/bin/env bash
# Vérifie la convention D-16, les fichiers manquants et l'intégrité des assets.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
INDEX_FILE="$SCRIPT_DIR/pokemon-index.json"

TOTAL_POKEMON=1025
ERRORS=0
WARNINGS=0

MISSING_FRONT_FILE="$SCRIPT_DIR/missing-front.txt"
MISSING_BACK_FILE="$SCRIPT_DIR/missing-back.txt"
NAMING_ERRORS_FILE="$SCRIPT_DIR/naming-errors.txt"
MISSING_FRONT_COUNT=0
MISSING_BACK_COUNT=0
NAMING_ERRORS_COUNT=0

ok()   { echo "[OK]    $*"; }
warn() { echo "[WARN]  $*"; WARNINGS=$((WARNINGS + 1)); }
err()  { echo "[ERROR] $*"; ERRORS=$((ERRORS + 1)); }

# Regex D-16 pour sprites
RE_SPRITE='^[0-9]{5}_[a-z0-9-]+_[a-z-]+\.(png|gif)$'
# Regex D-16 pour cris (pas de view)
RE_CRY='^[0-9]{5}_[a-z0-9-]+\.ogg$'

check_naming() {
    local dir="$1"
    local regex="$2"
    local label="$3"

    [ -d "$dir" ] || { err "$label : dossier manquant"; return; }

    local bad=0
    while IFS= read -r -d '' f; do
        local bn
        bn=$(basename "$f")
        [ "$bn" = ".gitkeep" ] && continue
        if ! echo "$bn" | grep -qP "$regex"; then
            warn "Nom non-conforme D-16 : $f"
            bad=$((bad + 1))
        fi
    done < <(find "$dir" -maxdepth 1 -type f -print0)

    if [ "$bad" -gt 0 ]; then
        err "$label : $bad fichier(s) avec nommage non-conforme D-16"
    else
        ok "$label : nommage D-16 OK"
    fi
}

check_count() {
    local dir="$1"
    local min="$2"
    local label="$3"

    [ -d "$dir" ] || { err "$label : dossier manquant"; return; }

    local count
    count=$(find "$dir" -maxdepth 1 -type f -not -name '.gitkeep' | wc -l)

    if [ "$count" -eq 0 ]; then
        err "$label : VIDE — lancez les scripts de téléchargement"
    elif [ "$count" -lt "$min" ]; then
        warn "$label : $count fichiers (attendu ≥ $min)"
    else
        ok "$label : $count fichiers"
    fi
}

check_corrupt() {
    local dir="$1"
    local ext="$2"
    local label="$3"
    local min_bytes="${4:-1024}"

    [ -d "$dir" ] || return

    local corrupt=0
    while IFS= read -r -d '' f; do
        [ "$(basename "$f")" = ".gitkeep" ] && continue
        local size
        size=$(stat -c%s "$f" 2>/dev/null || echo 0)
        if [ "$size" -lt "$min_bytes" ]; then
            warn "Fichier suspect (< ${min_bytes}o) : $(basename "$f") (${size}o)"
            corrupt=$((corrupt + 1))
        fi
    done < <(find "$dir" -maxdepth 1 -name "*.$ext" -print0)

    [ "$corrupt" -gt 0 ] && err "$label : $corrupt fichier(s) potentiellement corrompus (seuil ${min_bytes}o)"
}

check_missing_dexids() {
    local dir="$1"
    local label="$2"
    local max_dexid="${3:-$TOTAL_POKEMON}"

    [ -d "$dir" ] || return
    [ ! -f "$INDEX_FILE" ] && { warn "pokemon-index.json absent — vérification des IDs ignorée"; return; }

    local missing=0
    local sample=()

    for i in $(seq 1 $max_dexid); do
        local padded
        padded=$(printf '%05d' "$i")
        if ! find "$dir" -maxdepth 1 -name "${padded}_*" | grep -q .; then
            missing=$((missing + 1))
            [ "${#sample[@]}" -lt 5 ] && sample+=("#$i")
        fi
    done

    if [ "$missing" -gt 0 ]; then
        warn "$label : $missing dexid(s) manquants (ex: ${sample[*]})"
    else
        ok "$label : tous les dexids 1→${max_dexid} présents"
    fi
}

# Vérifie que chaque dexid 1→TOTAL_POKEMON a un fichier {dexid5}_*_{view}.png.
# Écrit les dexids manquants dans $out. Met à jour $result_var (printf -v).
check_missing_view() {
    local dir="$1"
    local view="$2"
    local out="$3"
    local result_var="$4"

    if [ ! -d "$dir" ]; then
        err "sprites/$view : dossier manquant"
        printf -v "$result_var" 0
        return
    fi
    if [ ! -f "$INDEX_FILE" ]; then
        warn "pokemon-index.json absent — vérif. dexids $view ignorée"
        printf -v "$result_var" 0
        return
    fi

    : > "$out"
    local missing=0
    for i in $(seq 1 $TOTAL_POKEMON); do
        local padded identifier
        padded=$(printf '%05d' "$i")
        if ! find "$dir" -maxdepth 1 -name "${padded}_*_${view}.png" | grep -q .; then
            identifier=$(jq -r ".\"$i\" // empty" "$INDEX_FILE")
            [ -n "$identifier" ] \
                && echo "${padded}_${identifier}" >> "$out" \
                || echo "$padded" >> "$out"
            missing=$((missing + 1))
        fi
    done

    if [ "$missing" -gt 0 ]; then
        warn "sprites/$view : $missing dexid(s) sans ${view}.png → $(basename "$out")"
    else
        ok "sprites/$view : tous les dexids 1→$TOTAL_POKEMON présents"
    fi
    printf -v "$result_var" '%d' "$missing"
}

# Vérifie que tous les fichiers sprites/cries respectent la regex D-16 stricte
# (vues autorisées : front|back|front-shiny|back-shiny|animated|animated-back|icon|portrait).
# Écrit les chemins non conformes dans $out. Met à jour $result_var.
check_naming_strict() {
    local out="$1"
    local result_var="$2"
    local RE_STRICT='^[0-9]{5}_[a-z0-9-]+_(front|back|front-shiny|back-shiny|animated|animated-back|icon|icon-shiny|footprint|portrait)\.(png|gif)$'
    local RE_OGG='^[0-9]{5}_[a-z0-9-]+\.ogg$'

    : > "$out"
    local errors=0

    for dir in \
        "$ROOT_DIR/sprites/front" \
        "$ROOT_DIR/sprites/front-shiny" \
        "$ROOT_DIR/sprites/back" \
        "$ROOT_DIR/sprites/back-shiny" \
        "$ROOT_DIR/sprites/animated" \
        "$ROOT_DIR/sprites/animated-back" \
        "$ROOT_DIR/sprites/icons" \
        "$ROOT_DIR/sprites/icons-shiny" \
        "$ROOT_DIR/sprites/footprints" \
        "$ROOT_DIR/sprites/characters/portraits"; do
        [ -d "$dir" ] || continue
        while IFS= read -r -d '' f; do
            local bn
            bn=$(basename "$f")
            if ! echo "$bn" | grep -qP "$RE_STRICT"; then
                echo "$f" >> "$out"
                errors=$((errors + 1))
            fi
        done < <(find "$dir" -maxdepth 1 -type f \( -name "*.png" -o -name "*.gif" \) -print0)
    done

    if [ -d "$ROOT_DIR/audio/cries" ]; then
        while IFS= read -r -d '' f; do
            local bn
            bn=$(basename "$f")
            if ! echo "$bn" | grep -qP "$RE_OGG"; then
                echo "$f" >> "$out"
                errors=$((errors + 1))
            fi
        done < <(find "$ROOT_DIR/audio/cries" -maxdepth 1 -name "*.ogg" -print0)
    fi

    if [ "$errors" -gt 0 ]; then
        err "Nommage strict D-16 : $errors fichier(s) non conformes → $(basename "$out")"
    else
        ok "Nommage strict D-16 : tous les fichiers conformes"
    fi
    printf -v "$result_var" '%d' "$errors"
}

echo ""
echo "=== Validation PokemonSDK-DataPack (convention D-16) ========"
echo "Racine  : $ROOT_DIR"
echo "Pokémon : 1→$TOTAL_POKEMON"
echo "=============================================================="

echo ""
echo "--- Nommage D-16 ------------------------------------------"
check_naming "$ROOT_DIR/sprites/front"         "$RE_SPRITE" "front"
check_naming "$ROOT_DIR/sprites/front-shiny"   "$RE_SPRITE" "front-shiny"
check_naming "$ROOT_DIR/sprites/back"          "$RE_SPRITE" "back"
check_naming "$ROOT_DIR/sprites/back-shiny"    "$RE_SPRITE" "back-shiny"
check_naming "$ROOT_DIR/sprites/animated"      "$RE_SPRITE" "animated"
check_naming "$ROOT_DIR/sprites/animated-back" "$RE_SPRITE" "animated-back"
check_naming "$ROOT_DIR/sprites/icons"         "$RE_SPRITE" "icons"
check_naming "$ROOT_DIR/sprites/icons-shiny"  "$RE_SPRITE" "icons-shiny"
check_naming "$ROOT_DIR/sprites/footprints"   "$RE_SPRITE" "footprints"
check_naming "$ROOT_DIR/audio/cries"           "$RE_CRY"    "cries"

echo ""
echo "--- Complétude (dexids 1→$TOTAL_POKEMON) -------------------"
check_count "$ROOT_DIR/sprites/front"         $TOTAL_POKEMON "front"
check_count "$ROOT_DIR/sprites/front-shiny"   $TOTAL_POKEMON "front-shiny"
check_count "$ROOT_DIR/sprites/back"          $TOTAL_POKEMON "back"
check_count "$ROOT_DIR/sprites/animated"      650            "animated (Gen 1→5)"
check_count "$ROOT_DIR/sprites/animated-back" 650            "animated-back (Gen 1→5)"
check_count "$ROOT_DIR/sprites/icons"         1106           "icons (toutes gens)"
check_count "$ROOT_DIR/sprites/icons-shiny"  $TOTAL_POKEMON "icons-shiny"
check_count "$ROOT_DIR/sprites/footprints"   649            "footprints (Gen 1→5)"
check_count "$ROOT_DIR/audio/cries"           $TOTAL_POKEMON "cries"

echo ""
echo "--- IDs manquants -----------------------------------------"
check_missing_dexids "$ROOT_DIR/sprites/front"       "front"
check_missing_dexids "$ROOT_DIR/sprites/front-shiny" "front-shiny"
check_missing_dexids "$ROOT_DIR/sprites/icons"       "icons"
check_missing_dexids "$ROOT_DIR/sprites/icons-shiny" "icons-shiny"
check_missing_dexids "$ROOT_DIR/sprites/footprints"  "footprints (Gen 1→5)" 649
check_missing_dexids "$ROOT_DIR/audio/cries"         "cries"

echo ""
echo "--- Dexids manquants (front / back) --------------------------------"
check_missing_view "$ROOT_DIR/sprites/front" "front" "$MISSING_FRONT_FILE" MISSING_FRONT_COUNT
check_missing_view "$ROOT_DIR/sprites/back"  "back"  "$MISSING_BACK_FILE"  MISSING_BACK_COUNT

echo ""
echo "--- Nommage strict D-16 (vues autorisées) --------------------------"
check_naming_strict "$NAMING_ERRORS_FILE" NAMING_ERRORS_COUNT

echo ""
echo "--- Intégrité (seuils : front=200o, back/icons=67o, portraits=500o) -"
check_corrupt "$ROOT_DIR/sprites/front"         "png" "front"         200
check_corrupt "$ROOT_DIR/sprites/front-shiny"   "png" "front-shiny"   200
check_corrupt "$ROOT_DIR/sprites/back"          "png" "back"          67
check_corrupt "$ROOT_DIR/sprites/back-shiny"    "png" "back-shiny"    67
check_corrupt "$ROOT_DIR/sprites/icons"         "png" "icons"         67
check_corrupt "$ROOT_DIR/sprites/icons-shiny"  "png" "icons-shiny"   67
check_corrupt "$ROOT_DIR/sprites/footprints"   "png" "footprints"    50
check_corrupt "$ROOT_DIR/sprites/characters/portraits" "png" "portraits" 500
check_corrupt "$ROOT_DIR/audio/cries"           "ogg" "cries"         1024

echo ""
echo "=== Rapport final =========================================="
printf "%-35s %d\n" "Dexids manquants (front)"  "$MISSING_FRONT_COUNT"
printf "%-35s %d\n" "Dexids manquants (back)"   "$MISSING_BACK_COUNT"
printf "%-35s %d\n" "Erreurs de nommage strict" "$NAMING_ERRORS_COUNT"
[ "$MISSING_FRONT_COUNT" -gt 0 ] && echo "  → $MISSING_FRONT_FILE"
[ "$MISSING_BACK_COUNT"  -gt 0 ] && echo "  → $MISSING_BACK_FILE"
[ "$NAMING_ERRORS_COUNT" -gt 0 ] && echo "  → $NAMING_ERRORS_FILE"
echo "-----------------------------------------------------------"
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    ok "DataPack valide. Convention D-16 respectée."
elif [ "$ERRORS" -eq 0 ]; then
    echo "[WARN]  $WARNINGS avertissement(s). DataPack utilisable mais incomplet."
else
    echo "[ERROR] $ERRORS erreur(s), $WARNINGS avertissement(s). DataPack invalide."
    echo "        Lancez build-index.sh → download-sprites.sh → download-cries.sh"
fi
echo "============================================================"
exit $ERRORS
