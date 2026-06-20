#!/usr/bin/env bash
# Génère tools/pokemon-index.json : mapping dexid → identifier pour espèces + formes.
#   IDs 1→1025    : espèces de base (Gen 1→9)
#   IDs 10001→10N : formes alternatives (Alola, Galar, Mega, etc.)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INDEX_FILE="$SCRIPT_DIR/pokemon-index.json"

log() { echo "[INFO]  $*"; }
ok()  { echo "[OK]    $*"; }
err() { echo "[ERROR] $*"; exit 1; }

for dep in curl jq; do
    command -v "$dep" &>/dev/null || err "$dep requis : sudo apt install $dep"
done

log "Appel PokeAPI — espèces de base (limit=1025)..."
response_base=$(curl -sf "https://pokeapi.co/api/v2/pokemon?limit=1025") \
    || err "Échec appel PokeAPI (base) — vérifiez votre connexion"

log "Appel PokeAPI — formes alternatives (limit=2000&offset=1025)..."
response_forms=$(curl -sf "https://pokeapi.co/api/v2/pokemon?limit=2000&offset=1025") \
    || err "Échec appel PokeAPI (formes) — vérifiez votre connexion"

log "Génération du mapping dexid→identifier (espèces + formes)..."
jq -n \
    --argjson base  "$response_base" \
    --argjson forms "$response_forms" '
    ($base.results + $forms.results)
    | map({
        key:   (.url | split("/") | map(select(. != "")) | last),
        value: .name
      })
    | from_entries
' > "$INDEX_FILE"

total=$(jq 'length' "$INDEX_FILE")
base_count=$(jq '[keys[] | select(tonumber <= 1025)] | length' "$INDEX_FILE")
forms_count=$(jq '[keys[] | select(tonumber >= 10001)] | length' "$INDEX_FILE")

ok "$total entrées dans $INDEX_FILE"
ok "  espèces de base : $base_count"
ok "  formes altern.  : $forms_count"
