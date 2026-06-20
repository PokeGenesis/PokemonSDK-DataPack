# PokemonSDK-DataPack

Pack de données officiel pour [PokemonSDK](https://github.com/PokeGenesis/PokemonSDK).
Fan-game non commercial uniquement — voir LICENSE.md et DISCLAIMER.md.

## Contenu

- Sprites front + back + shiny Gen 1→9 (résolutions sources natives)
- Sprites animés Gen 5 front + back (GIF)
- Icônes boîte PC 32×32 (+ shiny, Gen 1→9)
- Empreintes (footprints) Gen 1→5 — voir [note](#footprints)
- Cris Pokémon Gen 1→9 (.ogg)
- Base SQLite 1025 Pokémon (générée via tools/)

## Spécifications techniques

### Résolution cible v2.0

Les sprites v1.0 sont livrés dans leurs **résolutions sources natives** (Showdown, PokeAPI, PSDK).
Le pipeline v2.0 (Real-ESRGAN upscale + Stable Diffusion redraw + ImageSharp resize) produira :

| Catégorie | Résolution cible | Dossier |
| --------- | ---------------- | ------- |
| `front` / `back` / `front-shiny` / `back-shiny` | **96×96 px** | `sprites/front/`, `sprites/back/`, … |
| `icons` / `icons-shiny` | **32×32 px** | `sprites/icons/`, `sprites/icons-shiny/` |
| `footprints` | **64×64 px** | `sprites/footprints/` |
| `portraits` | **128×128 px** | `sprites/characters/portraits/` |

### Rendu in-game

PokemonSDK tourne en résolution interne 480×270 upscalée ×4 via shader xBR → **1920×1080**.
Les sprites front/back 96×96 sont affichés **384×384 px** en jeu (×4 xBR sans perte).

## Convention de nommage D-16

Tous les assets respectent la convention D-16 :

```text
{dexid5}_{identifier}_{view}.extension
```

| Composant | Format | Exemple |
| --------- | ------ | ------- |
| `dexid5` | ID Pokédex National, 5 chiffres, zéros préfixés | `00025` |
| `identifier` | Nom PokeAPI, minuscules, tirets | `pikachu` |
| `view` | Type d'asset | `front`, `back`, `front-shiny`, etc. |

### Exemples

```text
00025_pikachu_front.png
00025_pikachu_back-shiny.png
00025_pikachu_animated.gif
00025_pikachu.ogg              ← cris : pas de view
```

### Formes régionales et variants

Le suffixe de forme s'insère dans l'identifier, avant le view :

```text
00026_raichu-alola_front.png
00006_charizard-mega-x_front.png
00800_necrozma-dusk-mane_back.png
```

## Footprints

Gen 1→5 : **649 footprints complets** (`sprites/footprints/`, format D-16 `_footprint.png`).

Gen 6→9 : **non disponibles** — feature retirée par Nintendo à partir de Pokémon X/Y (2013).
Les Pokédex Gen 6+ n'affichent plus les empreintes ; aucune source officielle ou fan-made n'en fournit pour les dexids 650→1025.

## Versions sprites

| Source | Générations | Type |
| ------ | ----------- | ---- |
| Showdown HOME PNG | Gen 1→9 | Front + shiny |
| Showdown Gen 5 animé | Gen 1→5 | Front + back animés GIF |
| Showdown gen5ani-back-shiny | Gen 1→5 | Back-shiny GIF → PNG |
| PokeAPI/sprites | Gen 6→9 | Back + back-shiny |
| PSDK GameDataPacks (SV) | Gen 1→9 | Icons + icons-shiny |
| PSDK GameDataPacks (B2W2) | Gen 1→5 | Footprints |
| Showdown trainers | — | Sprites dresseurs |

## Installation rapide

```bash
git clone https://github.com/PokeGenesis/PokemonSDK-DataPack
pokeforge datapack --use ./PokemonSDK-DataPack
```

## Générer les assets depuis les sources

```bash
cd tools/
bash build-index.sh             # génère pokemon-index.json depuis PokeAPI (~5s)
bash download-sprites.sh        # télécharge + renomme selon D-16 (~10-30 min)
bash download-back-sprites.sh   # complète back/ Gen 6→9 (~5-15 min)
bash download-cries.sh          # cris .ogg (~2-5 min)
bash validate-assets.sh         # vérifie convention + intégrité (~30s)
```
