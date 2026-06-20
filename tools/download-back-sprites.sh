#!/usr/bin/env bash
# Complète sprites/back/ et sprites/back-shiny/ depuis plusieurs sources :
#   Étape 0 : gen5ani-back-shiny/ GIF → frame 0 → back-shiny/ Gen 1→5 (tmp, nettoyé)
#   Étape 1 : PokeAPI/sprites clone sparse → back/ + back-shiny/ Gen 6→9
#   Étape 2 : Showdown gen6-back/ fallback → back/ Gen 6→9 encore manquants
#
# Usage : bash download-back-sprites.sh
# Prérequis : missing-back-sprites.txt (extract-back-sprites.sh), pokemon-index.json, git, wget, jq, imagemagick
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
INDEX_FILE="$SCRIPT_DIR/pokemon-index.json"
MISSING_FILE="$SCRIPT_DIR/missing-back-sprites.txt"
TMP_DIR="$SCRIPT_DIR/tmp"
POKEAPI_DIR="$TMP_DIR/pokeapi-sprites"
BACK_DIR="$ROOT_DIR/sprites/back"
BACK_SHINY_DIR="$ROOT_DIR/sprites/back-shiny"
BASE_URL="https://play.pokemonshowdown.com/sprites"

log()  { echo "[INFO]  $*"; }
ok()   { echo "[OK]    $*"; }
warn() { echo "[WARN]  $*"; }
err()  { echo "[ERROR] $*"; exit 1; }

SHINY_GEN15=0
COPIED_BACK=0
COPIED_SHINY=0
SHOWDOWN_FOUND=0

for dep in git wget jq convert; do
    command -v "$dep" &>/dev/null \
        || err "$dep requis${dep/convert/ : sudo apt install imagemagick}"
done

[ -f "$MISSING_FILE" ] || err "missing-back-sprites.txt absent — lancez extract-back-sprites.sh d'abord"
[ -f "$INDEX_FILE" ] && [ "$(jq 'length' "$INDEX_FILE" 2>/dev/null)" -gt 0 ] \
    || err "pokemon-index.json absent — lancez build-index.sh d'abord"

mkdir -p "$BACK_DIR" "$BACK_SHINY_DIR" "$TMP_DIR"
trap 'rm -rf "$POKEAPI_DIR"' EXIT

# ── Index inversé : identifier → dexid ───────────────────────────────────────
declare -A INVERSE_INDEX
while IFS='=' read -r identifier dexid; do
    INVERSE_INDEX["$identifier"]="$dexid"
done < <(jq -r 'to_entries[] | "\(.value)=\(.key)"' "$INDEX_FILE")

# Index sans-tirets : identifier_sans_tirets → identifier
# Gère les noms Showdown qui suppriment tous les tirets (ex: nidoranf→nidoran-f, hooh→ho-oh)
declare -A NOHYPHEN_INDEX
# Index forme par défaut : nom_de_base → identifier
# Gère les noms Showdown qui omettent le suffixe de forme (ex: deoxys→deoxys-normal)
declare -A BASEFORM_INDEX
for _ident in "${!INVERSE_INDEX[@]}"; do
    _nh="${_ident//-/}"
    [ "$_nh" != "$_ident" ] && NOHYPHEN_INDEX["$_nh"]="$_ident"
    _cand="$_ident"
    while [[ "$_cand" == *-* ]]; do
        _cand="${_cand%-*}"
        if [ ! "${INVERSE_INDEX[$_cand]+_}" ] && \
           [ ! "${NOHYPHEN_INDEX[$_cand]+_}" ] && \
           [ ! "${BASEFORM_INDEX[$_cand]+_}" ]; then
            BASEFORM_INDEX["$_cand"]="$_ident"
        fi
    done
done
unset _ident _nh _cand

# Retourne "{dexid}|{identifier}|{form}" ou exit 1.
find_pokemon() {
    local name="$1"

    if [ "${INVERSE_INDEX[$name]+_}" ]; then
        echo "${INVERSE_INDEX[$name]}|$name|"
        return 0
    fi

    local candidate="$name"
    while [[ "$candidate" == *-* ]]; do
        candidate="${candidate%-*}"
        if [ "${INVERSE_INDEX[$candidate]+_}" ]; then
            echo "${INVERSE_INDEX[$candidate]}|$candidate|${name:${#candidate}+1}"
            return 0
        fi
    done

    # 3. Nom sans tirets (Showdown supprime tous les tirets de certains identifiers)
    #    ex: "nidoranf"→"nidoran-f", "mrmime"→"mr-mime", "hooh"→"ho-oh"
    if [ "${NOHYPHEN_INDEX[$name]+_}" ]; then
        local canonical="${NOHYPHEN_INDEX[$name]}"
        echo "${INVERSE_INDEX[$canonical]}|$canonical|"
        return 0
    fi

    # 4. Forme par défaut (Showdown omet le suffixe de forme pour la variante principale)
    #    ex: "deoxys"→"deoxys-normal", "wormadam"→"wormadam-plant"
    if [ "${BASEFORM_INDEX[$name]+_}" ]; then
        local canonical="${BASEFORM_INDEX[$name]}"
        echo "${INVERSE_INDEX[$canonical]}|$canonical|"
        return 0
    fi

    return 1
}

is_special_file() {
    case "$1" in
        -*)           return 0 ;;
        egg|egg-*)    return 0 ;;
        substitute)   return 0 ;;
        unknown)      return 0 ;;
        0)            return 0 ;;
        *)            return 1 ;;
    esac
}

# ── 0. Gen 1→5 back-shiny : frame 0 depuis gen5ani-back-shiny/ ───────────────
log "Téléchargement gen5ani-back-shiny/ (GIF animés shiny Gen 1→5)..."

tmp_shiny="$TMP_DIR/gen5ani-back-shiny"
mkdir -p "$tmp_shiny"

wget \
    --recursive --no-parent --no-directories \
    --accept "*.gif" \
    --directory-prefix="$tmp_shiny" \
    --quiet \
    "$BASE_URL/gen5ani-back-shiny/" 2>&1 || warn "wget gen5ani-back-shiny : certaines erreurs ignorées"

GIF_COUNT=$(find "$tmp_shiny" -maxdepth 1 -name "*.gif" | wc -l)
log "Extraction frame 0 depuis $GIF_COUNT GIF..."

SHINY_ERRORS=0
while IFS= read -r -d '' gif; do
    basename=$(basename "$gif")
    name="${basename%.*}"

    is_special_file "$name" && continue

    local_result=""
    local_result=$(find_pokemon "$name") || {
        warn "Introuvable dans index : $basename"
        continue
    }

    IFS='|' read -r dexid identifier form <<< "$local_result"
    padded=$(printf '%05d' "$dexid")

    if [ -n "$form" ]; then
        dest="$BACK_SHINY_DIR/${padded}_${identifier}-${form}_back-shiny.png"
    else
        dest="$BACK_SHINY_DIR/${padded}_${identifier}_back-shiny.png"
    fi

    if convert "${gif}[0]" "$dest" 2>/dev/null; then
        SHINY_GEN15=$((SHINY_GEN15 + 1))
    else
        warn "Échec extraction : $basename"
        SHINY_ERRORS=$((SHINY_ERRORS + 1))
    fi
done < <(find "$tmp_shiny" -maxdepth 1 -name "*.gif" -print0)

rm -rf "$tmp_shiny"
ok "Gen 1→5 back-shiny : $SHINY_GEN15 sprites extraits${SHINY_ERRORS:+ ($SHINY_ERRORS échecs)}"

# ── Lire missing-back-sprites.txt pour Gen 6→9 ───────────────────────────────
mapfile -t MISSING_ENTRIES < "$MISSING_FILE"
log "${#MISSING_ENTRIES[@]} back sprites Gen 6→9 manquants à traiter"

# ── 1. Clone sparse PokeAPI/sprites ──────────────────────────────────────────
log "Clonage PokeAPI/sprites (sparse + blobless)..."
git clone \
    --depth=1 \
    --filter=blob:none \
    --sparse \
    https://github.com/PokeAPI/sprites.git \
    "$POKEAPI_DIR" 2>&1 | grep -v '^$' || true

pushd "$POKEAPI_DIR" > /dev/null
git sparse-checkout set sprites/pokemon/back 2>&1 | grep -v '^$' || true
popd > /dev/null
ok "Clonage terminé"

# ── 2. Copier depuis PokeAPI/sprites ─────────────────────────────────────────
log "Extraction depuis PokeAPI/sprites..."

STILL_MISSING=()

for entry in "${MISSING_ENTRIES[@]}"; do
    [ -z "$entry" ] && continue

    dexid5="${entry%%_*}"
    identifier="${entry#*_}"
    dexid=$((10#$dexid5))

    src_back="$POKEAPI_DIR/sprites/pokemon/back/${dexid}.png"
    src_shiny="$POKEAPI_DIR/sprites/pokemon/back/shiny/${dexid}.png"

    back_found=false
    if [ -f "$src_back" ]; then
        cp "$src_back" "$BACK_DIR/${dexid5}_${identifier}_back.png"
        COPIED_BACK=$((COPIED_BACK + 1))
        back_found=true
    fi

    if [ -f "$src_shiny" ]; then
        cp "$src_shiny" "$BACK_SHINY_DIR/${dexid5}_${identifier}_back-shiny.png"
        COPIED_SHINY=$((COPIED_SHINY + 1))
    fi

    $back_found || STILL_MISSING+=("$entry")
done

ok "PokeAPI/sprites : $COPIED_BACK back | $COPIED_SHINY back-shiny"

# ── 3. Fallback Showdown gen6-back pour sprites encore manquants ──────────────
if [ "${#STILL_MISSING[@]}" -gt 0 ]; then
    log "Fallback Showdown gen6-back (${#STILL_MISSING[@]} sprites)..."

    tmp_sd="$TMP_DIR/gen6-back"
    mkdir -p "$tmp_sd"

    wget \
        --recursive --no-parent --no-directories \
        --accept "*.png" \
        --directory-prefix="$tmp_sd" \
        --quiet \
        "$BASE_URL/gen6-back/" 2>&1 || warn "wget gen6-back : certaines erreurs ignorées"

    FINAL_MISSING=()
    for entry in "${STILL_MISSING[@]}"; do
        dexid5="${entry%%_*}"
        identifier="${entry#*_}"

        found=false
        candidate="$identifier"
        while true; do
            if [ -f "$tmp_sd/${candidate}.png" ]; then
                cp "$tmp_sd/${candidate}.png" "$BACK_DIR/${dexid5}_${identifier}_back.png"
                SHOWDOWN_FOUND=$((SHOWDOWN_FOUND + 1))
                found=true
                break
            fi
            [[ "$candidate" == *-* ]] || break
            candidate="${candidate%-*}"
        done

        $found || FINAL_MISSING+=("$entry")
    done

    rm -rf "$tmp_sd"
    ok "Showdown gen6-back : $SHOWDOWN_FOUND sprites récupérés"
    STILL_MISSING=("${FINAL_MISSING[@]}")
fi

# ── 4. Mettre à jour missing-back-sprites.txt ─────────────────────────────────
if [ "${#STILL_MISSING[@]}" -gt 0 ]; then
    printf '%s\n' "${STILL_MISSING[@]}" > "$MISSING_FILE"
    warn "${#STILL_MISSING[@]} sprites encore manquants → $MISSING_FILE"
else
    : > "$MISSING_FILE"
    ok "Tous les back sprites Gen 6→9 couverts !"
fi

# ── Rapport ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Rapport back sprites ==========================================="
printf "%-42s %d\n" "Extraits gen5ani-back-shiny (Gen 1→5)"  "$SHINY_GEN15"
printf "%-42s %d\n" "Copiés PokeAPI/sprites (back Gen 6→9)"  "$COPIED_BACK"
printf "%-42s %d\n" "Copiés PokeAPI/sprites (back-shiny)"    "$COPIED_SHINY"
printf "%-42s %d\n" "Récupérés Showdown gen6-back"           "$SHOWDOWN_FOUND"
printf "%-42s %d\n" "Encore manquants (back)"                "${#STILL_MISSING[@]}"
echo "-------------------------------------------------------------------"
printf "%-42s %d fichiers\n" "sprites/back/ total"       "$(find "$BACK_DIR"       -maxdepth 1 -name '*_back.png'       | wc -l)"
printf "%-42s %d fichiers\n" "sprites/back-shiny/ total" "$(find "$BACK_SHINY_DIR" -maxdepth 1 -name '*_back-shiny.png' | wc -l)"
echo "==================================================================="
[ "${#STILL_MISSING[@]}" -eq 0 ] \
    && echo "Succès complet. Lancez validate-assets.sh." \
    || echo "Sprites manquants listés dans $MISSING_FILE"
