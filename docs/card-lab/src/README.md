# Card Lab — sources

Le prototype `../kohi-card-lab.html` est assemblé depuis ce dossier. C'est la référence des algorithmes du brief #9 (`../../kohi-dev-brief-9.md`).

| Fichier | Contenu |
|---|---|
| `lab/data.js` | Couleurs d'arôme, terres par origine, réglages process et torréfaction, collection d'exemple |
| `lab/engine.js` | Graine (FNV-1a + mulberry32), OKLab, champ de blobs, grain, traitements du symbole |
| `lab/stickers.js` | Formes, primitives de scène, recettes par pays, sceaux de process |
| `lab/ui.js`, `lab/page.html` | La page (mosaïque, atelier, planche) |

## Commandes

- **Reconstruire le prototype** : `python3 assemble.py` → `../kohi-card-lab.html`
- **Réexporter les JSON** (palette, terroir, recettes, vecteurs de parité) : `node export.js`
- **Rerendre les stickers** après une modification de `lab/stickers.js` :
  1. une fois : `npm i playwright @fontsource-variable/archivo@5.2.5 @fontsource/dm-serif-display@5.2.5 @fontsource/ibm-plex-mono@5.2.5` puis `npx playwright install chromium`
  2. `node render-stickers.js` puis `python3 build-xcassets.py` (Pillow) → `../OriginStickers.xcassets`
  3. monter la version du catalogue dans `CardStandard` : l'app régénère les tuiles.

Les marques de `../fixtures/marks/` viennent de `backstages/planche.png` (trèfle Klover, ange Huabal, carte Gallardo, bouteille Blue Bottle) ; elles servent au prototype et aux tests de vectorisation.
