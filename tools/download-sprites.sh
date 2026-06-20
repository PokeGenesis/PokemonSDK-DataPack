#!/usr/bin/env bash
# Télécharge les sprites depuis Pokémon Showdown et les renomme selon D-16.
# Convention D-16 : {dexid5}_{identifier}_{view}.extension
#
# Usage : bash download-sprites.sh [catégorie...]
# Catégories : front  front-shiny  animated  animated-back  back  icons
# Sans argument → toutes les catégories.
# Exemple : bash download-sprites.sh front front-shiny animated animated-back back
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
INDEX_FILE="$SCRIPT_DIR/pokemon-index.json"
TMP_DIR="$SCRIPT_DIR/tmp"
BASE_URL="https://play.pokemonshowdown.com/sprites"

log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*"; }
ok()   { echo "[OK]    $*"; }
err()  { echo "[ERROR] $*"; exit 1; }

RENAMED=0
ERRORS=0

for dep in wget jq; do
    command -v "$dep" &>/dev/null || err "$dep requis : sudo apt install $dep"
done

if [ ! -f "$INDEX_FILE" ] || [ "$(jq 'length' "$INDEX_FILE")" -eq 0 ]; then
    log "pokemon-index.json absent ou vide — lancement de build-index.sh..."
    bash "$SCRIPT_DIR/build-index.sh" || err "Échec de build-index.sh"
fi

# Index direct  : dexid (string) → identifier
# Index inversé : identifier → dexid (string)
declare -A INVERSE_INDEX
while IFS='=' read -r identifier dexid; do
    INVERSE_INDEX["$identifier"]="$dexid"
done < <(jq -r 'to_entries[] | "\(.value)=\(.key)"' "$INDEX_FILE")

log "Index chargé : ${#INVERSE_INDEX[@]} identifiers"
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


# Retourne via stdout "{dexid}|{identifier}|{form}" ou exit 1 si non trouvé.
# Gère deux conventions de nommage Showdown :
#   - numérique  : "25.png", "25-cap.png"     (gen5icons)
#   - texte      : "pikachu.png", "pikachu-original.png", "ho-oh.png"  (home, gen5ani…)
find_pokemon() {
    local name="$1"

    # --- Cas numérique (gen5icons) ---
    if [[ "$name" =~ ^([0-9]+)(-(.+))?$ ]]; then
        local dexid="${BASH_REMATCH[1]}"
        local form="${BASH_REMATCH[3]:-}"
        local identifier
        identifier=$(jq -r ".\"$dexid\" // empty" "$INDEX_FILE")
        if [ -n "$identifier" ]; then
            echo "$dexid|$identifier|$form"
            return 0
        fi
        return 1
    fi

    # --- Cas texte (home, gen5ani, gen6-back…) ---
    # Essai du nom complet en premier (ex: "ho-oh", "mr-mime", "type-null")
    if [ "${INVERSE_INDEX[$name]+_}" ]; then
        echo "${INVERSE_INDEX[$name]}|$name|"
        return 0
    fi

    # Suppression progressive du dernier segment pour isoler la forme
    # ex: "charizard-mega-x" → essai "charizard-mega" → essai "charizard" ✓ form="mega-x"
    # ex: "pikachu-original"  → essai "pikachu" ✓ form="original"
    # ex: "mr-mime-galar"     → essai "mr-mime" ✓ form="galar"
    local candidate="$name"
    while [[ "$candidate" == *-* ]]; do
        candidate="${candidate%-*}"
        if [ "${INVERSE_INDEX[$candidate]+_}" ]; then
            local form="${name:${#candidate}+1}"
            echo "${INVERSE_INDEX[$candidate]}|$candidate|$form"
            return 0
        fi
    done

    # 3. Nom sans tirets (Showdown supprime tous les tirets de certains identifiers)
    #    ex: "nidoranf"→"nidoran-f", "mrmime"→"mr-mime", "hooh"→"ho-oh", "greattusk"→"great-tusk"
    if [ "${NOHYPHEN_INDEX[$name]+_}" ]; then
        local canonical="${NOHYPHEN_INDEX[$name]}"
        echo "${INVERSE_INDEX[$canonical]}|$canonical|"
        return 0
    fi

    # 4. Forme par défaut (Showdown omet le suffixe de forme pour la variante principale)
    #    ex: "deoxys"→"deoxys-normal", "wormadam"→"wormadam-plant", "basculin"→"basculin-red-striped"
    if [ "${BASEFORM_INDEX[$name]+_}" ]; then
        local canonical="${BASEFORM_INDEX[$name]}"
        echo "${INVERSE_INDEX[$canonical]}|$canonical|"
        return 0
    fi

    return 1
}

# Assets spéciaux Showdown qui ne sont pas des Pokémon jouables → ignorer silencieusement.
is_special_file() {
    case "$1" in
        -*)           return 0 ;;   # -1, etc.
        egg|egg-*)    return 0 ;;
        substitute)   return 0 ;;
        unknown)      return 0 ;;
        0)            return 0 ;;
        *)            return 1 ;;
    esac
}

rename_and_copy() {
    local src="$1"
    local view="$2"
    local dest_dir="$3"

    local basename ext name
    basename=$(basename "$src")
    ext="${basename##*.}"
    name="${basename%.*}"

    is_special_file "$name" && return

    local result
    if ! result=$(find_pokemon "$name"); then
        warn "Pokémon introuvable dans l'index, ignoré : $basename"
        ERRORS=$((ERRORS + 1))
        return
    fi

    local dexid identifier form padded new_name
    IFS='|' read -r dexid identifier form <<< "$result"
    padded=$(printf '%05d' "$dexid")

    if [ -n "$form" ]; then
        new_name="${padded}_${identifier}-${form}_${view}.${ext}"
    else
        new_name="${padded}_${identifier}_${view}.${ext}"
    fi

    cp "$src" "$dest_dir/$new_name"
    RENAMED=$((RENAMED + 1))
}

download_category() {
    local url="$1"
    local view="$2"
    local dest_dir="$3"
    local accept="$4"
    local label="$5"

    local tmp_cat="$TMP_DIR/$view"
    mkdir -p "$tmp_cat" "$dest_dir"

    log "Téléchargement $label..."
    wget \
        --recursive \
        --no-parent \
        --no-directories \
        --accept "$accept" \
        --directory-prefix="$tmp_cat" \
        --quiet \
        --show-progress \
        "$url" 2>&1 || warn "wget a rencontré des erreurs pour $label"

    local count=0
    while IFS= read -r -d '' f; do
        rename_and_copy "$f" "$view" "$dest_dir"
        count=$((count + 1))
    done < <(find "$tmp_cat" -maxdepth 1 -type f -print0)

    ok "$label : $count fichiers traités → $dest_dir"
    rm -rf "$tmp_cat"
}

mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

# Catégories à traiter
declare -A RUN_CATS
if [ $# -eq 0 ]; then
    RUN_CATS=([front]=1 [front-shiny]=1 [animated]=1 [animated-back]=1 [back]=1 [icons]=1)
else
    for arg in "$@"; do RUN_CATS["$arg"]=1; done
fi

[ "${RUN_CATS[front]+_}" ]         && download_category "$BASE_URL/home/"         "front"         "$ROOT_DIR/sprites/front"         "*.png" "HOME front PNG"
[ "${RUN_CATS[front-shiny]+_}" ]   && download_category "$BASE_URL/home-shiny/"   "front-shiny"   "$ROOT_DIR/sprites/front-shiny"   "*.png" "HOME shiny PNG"
[ "${RUN_CATS[animated]+_}" ]      && download_category "$BASE_URL/gen5ani/"      "animated"      "$ROOT_DIR/sprites/animated"      "*.gif" "Gen5 animés front GIF"
[ "${RUN_CATS[animated-back]+_}" ] && {
    download_category "$BASE_URL/gen5ani-back/" "animated-back" "$ROOT_DIR/sprites/animated-back" "*.gif" "Gen5 animés back GIF"
    log "Extraction des back sprites Gen 1→5 depuis les GIF animés..."
    bash "$SCRIPT_DIR/extract-back-sprites.sh"
}
[ "${RUN_CATS[back]+_}" ]          && log "back géré via extract-back-sprites.sh (appelé après animated-back)"
[ "${RUN_CATS[icons]+_}" ]         && download_category "$BASE_URL/gen5icons/"    "icon"          "$ROOT_DIR/sprites/icons"         "*.png" "Icônes boîte PC PNG"

echo ""
echo "=== Rapport ================================================="
[ "${RUN_CATS[front]+_}" ]         && printf "%-20s %s\n" "front"         "$(find "$ROOT_DIR/sprites/front"         -maxdepth 1 -type f | wc -l) fichiers"
[ "${RUN_CATS[front-shiny]+_}" ]   && printf "%-20s %s\n" "front-shiny"   "$(find "$ROOT_DIR/sprites/front-shiny"   -maxdepth 1 -type f | wc -l) fichiers"
[ "${RUN_CATS[animated]+_}" ]      && printf "%-20s %s\n" "animated"      "$(find "$ROOT_DIR/sprites/animated"      -maxdepth 1 -type f | wc -l) fichiers"
[ "${RUN_CATS[animated-back]+_}" ] && printf "%-20s %s\n" "animated-back" "$(find "$ROOT_DIR/sprites/animated-back" -maxdepth 1 -type f | wc -l) fichiers"
[ "${RUN_CATS[animated-back]+_}" ] && printf "%-20s %s\n" "back (extraits GIF)" "$(find "$ROOT_DIR/sprites/back" -maxdepth 1 -name '*_back.png' | wc -l) fichiers"
[ "${RUN_CATS[icons]+_}" ]         && printf "%-20s %s\n" "icons"         "$(find "$ROOT_DIR/sprites/icons"         -maxdepth 1 -type f | wc -l) fichiers"
echo "-------------------------------------------------------------"
echo "Renommés : $RENAMED  |  Ignorés/Erreurs : $ERRORS"
echo "============================================================="
[ "$ERRORS" -eq 0 ] \
    && echo "Succès. Lancez validate-assets.sh pour vérifier." \
    || echo "Certains fichiers ignorés. Voir les WARN ci-dessus."
