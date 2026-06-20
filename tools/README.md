# Tools — Scripts de téléchargement et validation

Ces scripts téléchargent les assets depuis leurs sources publiques, les renomment
selon la convention D-16, et vérifient l'intégrité du DataPack.

## Prérequis

| Outil | Usage | Installation |
| ----- | ----- | ------------ |
| `curl` | Appels PokeAPI (build-index) | `sudo apt install curl` |
| `jq` | Parsing JSON | `sudo apt install jq` |
| `wget` | Téléchargement sprites Showdown | `sudo apt install wget` |
| `git` | Clone PokeAPI/cries et PokeAPI/sprites | `sudo apt install git` |
| `imagemagick` | Extraction frame GIF (back sprites Gen 1→5) | `sudo apt install imagemagick` |

## Convention de nommage D-16

Tous les assets sont renommés automatiquement selon :

```text
{dexid5}_{identifier}_{view}.extension
```

- `dexid5` : ID Pokédex 5 chiffres, zéros préfixés (`00025`)
- `identifier` : nom PokeAPI minuscules tirets (`pikachu`, `raichu-alola`)
- `view` : `front`, `back`, `front-shiny`, `back-shiny`, `animated`, `animated-back`, `icon`, `portrait`
- Cris : pas de view → `00025_pikachu.ogg`

## Scripts

### build-index.sh

Interroge PokeAPI et génère `tools/pokemon-index.json` — mapping `dexid→identifier`
utilisé par tous les autres scripts.

```bash
bash build-index.sh
```

**Requiert :** `curl`, `jq`  
**Produit :** `tools/pokemon-index.json`

---

### download-sprites.sh

Télécharge tous les sprites depuis Pokémon Showdown et les renomme selon D-16.
Lance `build-index.sh` automatiquement si `pokemon-index.json` est absent.

```bash
bash download-sprites.sh
```

**Mapping source → destination :**

| URL Showdown | Dossier dest | Renommage |
| ------------ | ------------ | --------- |
| `home/` | `sprites/front/` | `pikachu.png` → `00025_pikachu_front.png` |
| `home-shiny/` | `sprites/front-shiny/` | `pikachu.png` → `00025_pikachu_front-shiny.png` |
| `gen5ani/` | `sprites/animated/` | `pikachu.gif` → `00025_pikachu_animated.gif` |
| `gen5ani-back/` | `sprites/animated-back/` | `pikachu.gif` → `00025_pikachu_animated-back.gif` |
| `gen5icons/` | `sprites/icons/` | `25.png` → `00025_pikachu_icon.png` |

> **Note :** `sprites/back/` Gen 1→5 est généré par `extract-back-sprites.sh` (frame 0 des GIF).  
> Gen 6→9 est complété par `download-back-sprites.sh`.

**Requiert :** `wget`, `jq`  
**Durée estimée :** 10–30 min selon connexion

---

### download-cries.sh

Clone [PokeAPI/cries](https://github.com/PokeAPI/cries), renomme les `.ogg` selon D-16
et nettoie le clone après copie.

```bash
bash download-cries.sh
```

**Renommage :** `25.ogg` → `00025_pikachu.ogg`  
**Destination :** `audio/cries/`  
**Requiert :** `git`, `jq`

---

### extract-back-sprites.sh

Extrait la frame 0 de chaque GIF dans `sprites/animated-back/` → `sprites/back/` (PNG, D-16).
Génère `tools/missing-back-sprites.txt` listant les dexids 650→1025 sans back sprite.

```bash
bash extract-back-sprites.sh
```

**Requiert :** `imagemagick`, `jq`, `sprites/animated-back/` peuplé  
**Produit :** `sprites/back/` (Gen 1→5), `tools/missing-back-sprites.txt`

---

### download-back-sprites.sh

Complète `sprites/back/` et `sprites/back-shiny/` en trois étapes :

1. **Gen 1→5 back-shiny** : télécharge `gen5ani-back-shiny/` GIF en tmp, extrait frame 0, renomme D-16 → `sprites/back-shiny/` (tmp nettoyé)
2. **Gen 6→9 back + back-shiny** : clone sparse `PokeAPI/sprites` → `back/{dexid}.png` et `back/shiny/{dexid}.png`
3. **Fallback Showdown gen6-back/** pour les back encore manquants après PokeAPI

Écrase `missing-back-sprites.txt` avec les éventuels sprites toujours introuvables.

```bash
bash download-back-sprites.sh
```

**Requiert :** `git`, `wget`, `jq`, `imagemagick`, `missing-back-sprites.txt`  
**Durée estimée :** 10–20 min (gen5ani-back-shiny DL + clone sparse PokeAPI ~50 MB)

---

### validate-assets.sh

Vérifie convention D-16, complétude des 1025 Pokémon et intégrité des fichiers.

```bash
bash validate-assets.sh
```

**Vérifications :**

- Nommage D-16 (regex `^[0-9]{5}_[a-z0-9-]+_[a-z-]+\.(png|gif)$`)
- Complétude des dexids 1→1025 par catégorie
- Fichiers potentiellement corrompus (PNG/OGG < 1KB)

**Codes de sortie :** `0` = OK, `>0` = erreurs détectées

## Ordre recommandé

```bash
cd tools/
bash build-index.sh             # ~5s
bash download-sprites.sh        # ~10-30 min (inclut extract-back-sprites.sh auto)
bash download-back-sprites.sh   # ~5-15 min  (complète back/ Gen 6→9)
bash download-cries.sh          # ~2-5 min
bash validate-assets.sh         # ~30s
```

## Notes

- Les scripts sont idempotents (relancer ne duplique pas les fichiers).
- `tools/tmp/` est dans `.gitignore` — jamais commité.
- `data/PokemonSDK.db` est générée par `pokeforge` — voir la doc PokemonSDK.
