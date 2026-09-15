# Kohi — Fonctionnalités actuelles et écart PRD

**Date** : 15 septembre 2026 · **PRD de référence** : [kohi-prd-v1.md](kohi-prd-v1.md) (brouillon 0.2, 9 septembre 2026)

Kohi est une archive personnelle de cartes de café, sur iPhone, devenue un **atelier** : le même objet-carte ouvre une pratique (brasser avec *son* matériel, garder ce qui a marché). L’app est **light only**, 100 % locale par défaut. Le cloud (Sign in with Apple + Supabase) est optionnel : sans configuration, scan, OCR, recettes de référence, kit (Profil) et archive restent sur l’appareil.

Ce document décrit **ce qui est dans le binaire aujourd’hui**, puis l’écart avec le PRD v1. Le vocabulaire visuel est dans [design-system.md](design-system.md).

---

## 0. En une page

L’app a quitté le stade « archive seule ». Les deux onglets, le Profil (kit + onboarding), les recettes en trois vues, le brew avant / pendant / après, la dictée, Roaster, « On the bag », le retrait de la caféine, les App Intents et la couche IA expérimentale (flags + `AIEvent`) sont en place.

Ce qui manque encore pour coller au **Must / Should 1.0** du PRD, c’est surtout de la **capture** (scan IA du sachet / ticket / étiquette d’eau, Ask contextualisé sur une carte) et quelques **finitions** (rosace du timer, recette A4, base de connaissances seedée, Share Extension, widget). Deux lots **1.1 / 1.2** sont déjà là en avance : conversion de mouture + calibration perso, et Insights.

---

## 1. Navigation

Deux mots en `catalogueLabel` à côté du wordmark — **Coffees** · **Recipes** — filet hairline, pas de `TabBar` système. Les onglets n’apparaissent que lorsqu’il y a au moins une carte.

| Surface | Comportement |
| --- | --- |
| **Coffees** | Grille d’objets. Le bouton scan n’existe que ici. |
| **Recipes** | Trois onglets de niveau 2 : Mine · Suggested · From the pros. Ask à droite. Bouton `cup.and.saucer` : café → recette → brew (minuteur). Une recette se sauvegarde toujours depuis un brew. |
| **Profil** | Icône `person.crop.circle` toujours visible. Kit, eau, défauts, onboarding, import (placeholder), IA expérimentale, compte. |
| **Account** | Rangée dans Profil, seulement si `Supabase.plist` est présent. `List` système, hors grammaire catalogue. |

Raccourcis système (App Intents, exposés à Siri / Shortcuts) :

- **Log a brew** — ouvre le brew sheet du café le plus récent (ou d’un café nommé).
- **Start a brew** — même chose, méthode déjà choisie, timer guidé prêt.

Pas de widget, pas de Control Center, pas de Share Extension.

---

## 2. Coffees — l’archive

Un seul écran d’accueil : des cartes posées sur du papier, un wordmark « Kohi », un bouton scan.

| Fonction | Comportement |
| --- | --- |
| Grille | Cartes triées par date d’ajout (la plus récente en haut). Pas de labels, pas de badges : l’image et son ombre *sont* la tuile. |
| Densité | Pincer pour passer de 1 à 4 colonnes. |
| Recherche | Barre une fois l’archive assez grande (≥ 20 cartes) et qu’on a scrollé. Filtre texte (nom, torréfacteur, pays, région, variété, process, tasting notes, lieu) **plus chips** méthode / saveur (ids roue) / lieu. La grille hors recherche reste triée par date d’ajout. |
| Ouverture | Tap → fiche détail. Transition zoom (iOS 26+). |
| Atterrissage | Une carte tout juste scannée arrive en haut de la grille avec une animation de pose. |
| Vide | « Nothing collected yet » + invitation à scanner. |
| Face | **Flyer** 4:5 dès qu’il est prêt, sinon le scan aplati. |

---

## 3. Scanner une carte

Le bouton viewfinder ouvre un plein écran caméra (fond sombre). C’est le seul flux d’ajout de café.

### Capture

- Caméra arrière, détection de document en live (Vision). Overlay qui suit les coins.
- Coaching d’une seule phrase à la fois : poser la carte, se rapprocher, tenir à plat, éviter le glare, rester immobile.
- **Auto-capture** une fois la carte assez grande, droite, nette et stable (~0,6 s). Déclencheur manuel en plus.
- Import depuis la photothèque (même revue que la capture live).
- Simulateur : pas de caméra, le déclencheur renvoie un échantillon bundlé.

Si l’accès caméra est refusé, on peut toujours importer une photo.

### Revue

- Recadrage : les quatre coins sont déplaçables.
- **Whiten** : look document (fond plus blanc, texte plus lisible). Désactivable. Première fois : « Whiter paper, sharper text ».
- **Use** / **Retake**.

### Ingest (fichier)

Pour chaque carte : `original.heic`, `flat.heic`, `mask.png` (si le masque couvre vraiment la carte), miniatures pour la grille. Une pièce jointe n’écrit qu’un `attach-<uuid>.heic`.

---

## 4. Lire la carte (OCR → fiche)

Après **Use**, une feuille **New card** s’ouvre. Les champs se remplissent en arrière-plan ; ce qu’on tape n’est jamais écrasé.

### Lecture locale (toujours)

1. OCR documentaire (Vision), langues **EN / FR / JA / ZH**. Retry à 90° / 270° si trop peu de lignes.
2. Parse heuristique des paires label/valeur (origine, process, notes).
3. **On the bag** : `BagFieldParser` lit roast level, Agtron, date de torréfaction, harvest, score, prix, poids, lot, décaf.
4. Recette imprimée (dose, eau, temps, température, grind, méthode) si au moins deux quantités sont reconnues.
5. QR, Micro QR, Data Matrix, EAN, Code 128. URL http(s) → Open Graph + JSON-LD Product pour les champs encore vides. Les profils sociaux ne sont pas scrapés.
6. Pays et process connus mappés vers l’anglais via des tables. Texte libre CJK : Translation on-device vers l’anglais ; l’original est conservé (`originalFields` + langue source).

Si presque rien n’est lu : « This does not look like a card » ou « Nothing recognised on this scan ».

### Second avis (si Supabase est configuré)

Quand la lecture locale est faible — peu de champs, écriture manuscrite, japonais / chinois — l’image part vers l’edge function `card-vision`. Le modèle ne **remplit que les champs vides**. Bouton manuel **Read again with AI** sur la fiche d’édition.

`FieldExtract.label` (sachet / ticket / étiquette d’eau) existe côté client et serveur, mais **n’est pas branché** sur le scan d’une pièce jointe : une page / bag / receipt ne passe que par l’OCR local.

---

## 5. Fiche d’une carte (détail)

Objet centré sur le papier, ombre, **inclinaison et reflet** selon le gyroscope. En dessous, la notice de catalogue. Une carte sans nom se titre par producteur / ferme / station, puis origine, puis torréfacteur ; la variété ne titre que s’il n’y a rien d’autre. Deux cartes au même titre reçoivent un suffixe `·` (torréfacteur, date de torréfaction, lot, date de scan).

- **Tombstone** : nom (désambiguïsé), origine, altitude.
- **Flyer / Scan** : chips pour basculer (si le poster est prêt). Tap sur l’objet aussi.
- **Notes** : chips horizontaux des tasting notes.
- **On the wheel** : chips outline des ids SCA 2016 reconnus dans ces notes (flag `flavorWheel`).
- **Caption** : torréfacteur, producteur, farm / wash station s’ils sont remplis, région, pays, altitude, variété, process, species **seulement si ce n’est pas arabica**, harvest, lot, roast (+ Agtron + méthode de décaf), **Roasted on** (+ jours), score, prix (`14 € · 250 g · 56 €/kg`), lieu, **Link** (URL produit, `arrow.up.right`), code label. Pas de « Brewed » ni de date d’ajout.
- **Lieu** : tap → Apple Maps ou Google Maps.
- **Show original** : texte d’origine après traduction (suffixe 日本語 / 中文).
- **Suggested recipe** : rangée *Card / From the pros / Adapted / Yours* + **For your grinder** (mouture dans tes clics, ou « Add your grinder… ») + **Use**. La recette imprimée reste au-dessus, tag *Card*.
- **Brews** : ligne 1 = nom de recette (ou méthode) + rating ; ligne 2 = `dose · ratio · temp`. Long press : **Brew again** / **Compare**. Un brew qui a enregistré une *Suggested correction* la montre en `tag`.
- **Profile** (flag `cardProfile`) : radar médian (≥ 2 brews comparables) + meilleur en `inkMuted`, saveurs trouvées avec `✓` si déclarées, `n brews · avg · best`.
- **Pages & documents** : pièces jointes.
- **Note to self**.
- Actions : **Edit**, **Regenerate poster**, **Remove from archive**. Pas de bouton **Ask** sur la carte.

---

## 6. Éditer une carte

Même feuille pour une nouvelle carte et une édition. Champs libres partout ; vocabulaire réduit là où les cartes se répètent.

| Champ | Notes |
| --- | --- |
| Coffee, Country, Region, Producer, Altitude, Variety, Process | Texte. Process : quick picks Washed, Natural, Honey, Anaerobic, Carbonic Maceration, Wet Hulled. |
| **Roaster** | Texte + suggestions depuis l’index local. Choisir lie `roasterId`. « Add roaster » → nom, ville, pays, site, Instagram. Dédoublonnage nom normalisé + pays (« Already in the index… »). Hors ligne : texte libre. |
| Place | Recherche MapKit (POI + adresse), biaisée par la localisation si autorisée. |
| Tasting notes | Chips éditables. *Match to wheel* : chips outline des ids reconnus (non sélectionnés pour toi). |
| **On the bag** (toujours visible) | Roast (5 chips), Agtron, **Roasted on**, Date (si pas de torréfaction), Price + devise, Bag, Lot, Harvest, Cupping, Farm, Station, Link (URL produit), Decaf + méthode. |
| Brew method | Espresso, V60, Filter, AeroPress, Moka, French Press, Cold Brew. |
| Recipe on card | Recette reconnue, dismissible. |
| Pages & documents | Ajouter / typer des pièces. |
| **Bought at** (section visible) | Place + type. |
| Note to self | Texte libre. **Dictate** (`DictationField`) dicte dans ce champ. |
| Date | Date du café (distincte de l’ajout et de *Roasted on*). |
| On the shelf (nouvelle carte) | **Scan** sur la grille, ou **AI flyer** généré après save. |

Squelettes shimmer pendant l’OCR. Discard d’un nouveau scan (fichiers effacés) ou retrait de l’archive.

**Pas dans le formulaire** : `species` (arabica / robusta — affiché au détail seulement s’il n’est pas arabica).

---

## 7. Roasters

Entité liée, cache local `roasters.json`, sync vers une table **partagée**.

- Champs : `id · name · city · country · website · instagram · createdBy · updatedAt`.
- Suggestions sous le champ Roaster. Texte libre toujours autoritaire pour l’affichage.
- Ajout manuel + dédoublonnage avant création.

Pas de `lat/lng`, pas d’aliases, pas de `verified`, pas d’adresse MapKit dans le mini-formulaire, pas d’agent d’enrichissement, pas de vue torréfacteur (tap sur le nom → ses cartes) — c’est 1.1 dans le PRD.

---

## 8. Profil — kit, eau, onboarding

Feuille catalogue depuis l’icône en haut à droite. Rien n’est obligatoire. Le Setup ne vit plus dans Recipes.

### Onboarding

Après le **premier scan** (1 100 ms après l’atterrissage), une feuille : « Bring what you have », puis trois questions sautables (méthode, broyeur, eau). Un flag `hasSeenSetupFlow` empêche toute relance automatique. Relance depuis Profil › Set up again. Import et photo du kit sont des rangées « soon ».

### Équipements

Un item = `kind · brand · model · notes · isDefaultFor[methods]` + champs par type.

| Kind | Champs |
| --- | --- |
| Grinder | Autocomplétion sur la base bundlée (187 modèles) ou custom, burrs, réglage (clicks / stepless / dial), plages par méthode quand elles sont vérifiées. |
| Brewer | Autocomplétion sur `brewers.json` (80 drippers : famille + bypass). Type, liste de filtres. |
| Espresso machine | Autocomplétion (Sage, Gaggia, Silvia, Flair, Robot). Panier (g), pression. |
| Kettle | Autocomplétion (Stagg EKG, Buono, Brewista). Col de cygne, contrôle de température. |
| Scale | Autocomplétion (Acaia, Timemore, Hario). Résolution, timer intégré. |
| Accessory | Notes. |

Pas d’identification par photo.

### Eau

Profil = nom, source (*tap / filtered / bottled / recipe*), Ca / Mg / Na / HCO₃, **ppm**, additif + dose, notes. GH et KH calculés. Bandes cibles SCA (`TargetBand`) : TDS 75–250 ppm, GH, alcalinité — position, pas un verdict.

- Une eau seedée : **Montcalm** (étiquette).
- Source **Recipe** : Base (Distilled · RO · Tap · Filtered) → `MineralProduct` (12 produits : TWW vérifiés, Lotus / Apax / Aquacode / PCW / AKVO Minerals *composition not on file yet*).
- Source **Filtered** : `FiltrationSystem` (AKVO, Peak Water, BWT, Brita…).
- Pas de scan d’étiquette, pas de code-barres / Open Food Facts (1.1).

### Défauts et mouture

- Défauts par méthode (grinder / brewer / machine) : le brew sheet part de là.
- **Convert a setting** : conversion proportionnelle entre deux broyeurs, avec « ≈ » et la base de la conversion affichée.
- **Calibration perso** (« mon 22 clics ≈ 700 µm ») — prévue 1.1, déjà là.

### Features (lot 2)

Interrupteurs locaux (`LotFlags`) dans Profil › **Features** : `taste7`, `flavorWheel`, `brewCompare`, `cardProfile`, `flavorOrigin`. **On par défaut**, sauf `flavorOrigin`. Ils cachent l’UI ; l’archive migre toujours. Override `KOHI_*` en DEBUG.

---

## 9. Recipes

Trois onglets de niveau 2 (Mine · Suggested · **From the pros**), feuille **Filters** verticale, Ask en tête. **New recipe** sous Mine.

### Suggested

Rangées **coffee-first** : le nom du café (désambiguïsé si deux cartes se lisent pareil), la recette proposée à la taille filtrée (1 cup / 2 cups / batch), la provenance à droite. Une carte = une rangée. Tap → la carte, scrollée à *Suggested recipe*. Pas de bouton Use dans la liste : la fiche recette et le bouton `cup.and.saucer` ouvrent le brew.

La température d’une suggestion ne bouge que si la carte dit le niveau de torréfaction. **Moka** et **cold brew** sont exemptés : leur eau n’est pas un choix. La recette de base est classée (ratio dans la bande de la méthode, puis évidence), `mine` devant les références.

### Brasser

Le bouton `cup.and.saucer` ouvre l’onglet Recipes. Le parcours recette est **trois écrans** : fiche recette → brew guidé (un bloc, cible interpolée, tap = Next) → After (rating, taste, correction, comment, Suggested correction, Save).

### From the pros

Recettes embarquées hors ligne, attribuées. Filtre par dripper, cup, roast, grinder d’auteur, profile. Attribution = le nom. Pas de niveau de preuve à l’écran. **For your grinder** sur la fiche. **Total brew time** sous les étapes. **Brew this** : 5 cafés récents + Another coffee….

### Mine

**New recipe** + recettes sauvées depuis un brew. Insights en pied, avec ligne de provenance.

### Mine

Recettes sauvegardées depuis un brew. Insights en pied. Filtre source : From a brew · Saved from reference · Adapted.

### Ask (expérimental)

Bouton **ASK** en tête de Recipes, et « Ask about this coffee » sous Brews sur la carte, seulement si le flag **Answer questions** est on. Une question, une réponse, sources nommées. **Pas encore de contexte carte / setup / derniers brews.**

---

## 10. Brew — avant, pendant, après

Pensé pour le *deuxième* café : Save suffit si rien n’a changé. Pré-rempli depuis la recette, le dernier brew (éventuellement déjà ajusté par une Suggested correction), et les défauts du Setup.

### Avant

- **Dictate** — dictée on-device (`SpeechAnalyzer` iOS 26, repli `SFSpeechRecognizer`). Grammaire locale d’abord. Si la couverture est faible et que **Understand dictation** est on → edge `field-extract`. Surlignage `paperShade` 1,1 s, tap = undo. `DictationField` enveloppe tout texte libre.
- **Method** — chips.
- **Recipe** — picker : Card · Suggested · Last brew · Mine · From the pros. `checkmark` sur la choisie.
- **With** — kit par défaut de la méthode.
- **Water** — profil par défaut.
- **Parameters** — **Coffee dose**, **Water weight** (filtre) ou **Beverage** (espresso), ratio, temps.
- **Grind** — chip broyeur + valeur. **For your grinder** convertit avec « ≈ ».
- **Temperature** — rangée principale.

En tête d’un brew existant : **Brew again** · **Compare**.

### Pendant

Sans étapes : chrono. Avec étapes (parcours recette) : **GuidedBrewView** — un seul bloc, `Typography.number`, cible interpolée, tap = Next, Stop en bas. Avance automatique après 3 s si `autoAdvance`. **Total brew time** à la fin.

### Après

- **Rating 1–5** (cibles 44 pt).
- **Taste** (flag `taste7`) : 7 axes.
- **Correction** : − · +.
- **Comment** dicté.
- **Suggested correction** : lecture + trois mouvements classés (ensemble admissible G7 + steps + dripper). Hors ligne : une règle. Flag on par défaut.
- **How useful was this?** : échelle à quatre niveaux + texte, sous chaque sortie modèle.
- **Compare with…** (flag `brewCompare`) : tous les brews comparables, chip Any coffee.
- Date. Suppression.

La caféine (calcul, override, ligne) **n’existe plus**.

`captureSource` est enregistré **par brew** (`typed` / `dictated` / `scanned` / `prefilled`), pas par champ.

---

## 11. Pièces jointes

Autre face, sachet, ticket, fiche recette, ou document.

| Rôle | Usage | OCR fusionné |
| --- | --- | --- |
| **Page** | Autre face / page. | Oui (local) |
| **Bag** | Photo du sachet. | Oui (local) |
| **Receipt** | Ticket de caisse. | Oui (local) |
| **Recipe** | Carte recette. | Non |
| **Document** | Le reste. | Non |

- Scan via le même flux caméra + revue. Rôle par défaut : Page ; en édition, tap cycle le rôle.
- Miniatures horizontales (badge P / B / T / R / D). Fiche plein écran + suppression.
- Pas d’extraction IA spécifique sachet / ticket ; pas de pré-remplissage d’un profil d’eau depuis une étiquette.

---

## 12. Posters (flyers IA)

Variante **4:5**, « tampon sur parchemin », pour la grille. Le scan reste l’archive.

- Option à la création (**AI flyer** / **Scan**).
- Génération asynchrone (`pending` → `ready` / `failed`) via `card-poster`.
- Régénération depuis le détail.
- Backfill depuis Compte (coût indicatif). Restore depuis le cloud si un poster existe déjà.

Sans Supabase, la grille montre le scan.

---

## 13. IA expérimentale

Principes tenus : ne remplit que le vide ; règles d’abord ; badge / fallback ; clés côté serveur ; mesuré.

| Fonction | Où | État |
| --- | --- | --- |
| `card-vision` | Lecture carte | Livré (pas derrière le master switch). |
| `card-poster` | Flyer | Livré (idem). |
| `field-extract` (phrase → brew) | Dictée | Livré, si la grammaire locale est trop mince. |
| `field-extract` (image → sachet / ticket / eau) | Client + edge | **Code présent, UI absente.** Voir le registre. |
| `recipe-adapt` | Fiche recette, sous les règles | Livré, flag on, variante unverified + « pourquoi ». |
| `ask` | Onglet Recipes + fiche café | Livré comme feuille, **sans contexte**, base `knowledge` vide. |
| Identification d’équipement par photo | Setup | Absent. |
| Foundation Models on-device | Extraction structurée | Absent (repli serveur uniquement). |
| Agents (enrichissement roaster, qualité, curateur, Coach) | Serveur | Absents. |

Profil : master **Experimental AI** (off par défaut) + interrupteurs par feature. Kill switch serveur `ai_flags`. Chaque appel écrit un `AIEvent` (feature, modèle, tokens, latence, accepté ou non). Profil affiche un résumé « Kept ».

Sans Supabase : voix on-device, OCR Vision, règles, recettes de référence et kit (Profil) fonctionnent. Vision lourde, posters, Ask, adapt et extract serveur manquent.

---

## 14. Compte et sync

Rangée dans Profil, visible seulement si `Supabase.plist` est présent. Ouvre la `List` système existante.

- **Sign in with Apple**.
- Sync bidirectionnelle :
  - perso (RLS) : cartes + images, équipements, eaux, recettes *Mine*, calibrations ;
  - partagée : torréfacteurs.
- Outbox locale : dirty / tombstones, push débouncé (~2 s), pull au lancement et au sync manuel.
- **Sync Now** / **Force Full Backup**.
- Sign out.

Hors ligne, les JSON locaux restent la source de vérité. Le sync reprend au retour réseau / au prochain passage en arrière-plan.

---

## 15. Données, hors-ligne, premier lancement

| Fichier | Contenu |
| --- | --- |
| `cards.json` | Archive. Décodage tolérant. |
| `roasters.json` | Index torréfacteurs. |
| `setup` (équipements, eaux, calibrations) | Kit perso. |
| `recipes.json` (store) | Recettes *Mine*. |
| Bundle `Reference/` | 15 recettes, 7 broyeurs, 1 eau, 4 additifs, **roue SCA 2016** ([`flavor-wheel.json`](../Kohi/Resources/Reference/flavor-wheel.json)). |
| `Cards/<uuid>/` | Images. Miniatures 512 / 1024, purge des orphelins. |

Sauvegarde coalescée ; flush quand l’app quitte le premier plan. Premier lancement (DEBUG surtout) : archive d’échantillons bundlés. Pas de compte requis pour collecter.

---

## 16. Code présent, surface absente

Décision datée, pas un oubli. Un champ n’entre dans le modèle que s’il a une saisie **et** une lecture.

| Code | Pourquoi ça dort | Lot qui le réveille |
| --- | --- | --- |
| `FieldExtract.label` + `Label.asFields()` / `asWaterProfile()` | Scan IA sachet / ticket / eau, hors lot 2 | Capture IA (brief §13) |
| `waterIn` | Colonne sans UI = import iBrew futur | Import iBrew |
| `color` et `fr` de `flavor-wheel.json` | Libellés écran en `en` jusqu’à localisation ; couleurs jamais pour le chrome | Localisation / export print |
| `docs/coffeechart.json` (SCAA 1995) | Historique. Remplacé par `flavor-wheel.json` (SCA 2016) ; la classe d’origine est portée par `origin` | — |

---

## 17. Ce que l’app n’est pas (volontairement)

Aligné sur les **non-objectifs** du PRD : pas de thème sombre, pas d’iPad / Mac comme cible, pas de partage social, pas de stats globales (cafés par mois, heatmap), pas de balance Bluetooth, pas de torréfaction maison.

Le chrome de Compte reste une `List` système.

---

# Écart avec le PRD v1

Statuts : **livré** · **partiel** · **absent** · **en avance** (prévu plus tard, déjà là) · **hors 1.0**.

## Must 1.0

| Item | PRD | App |
| --- | --- | --- |
| Onglets Coffees / Recipes | 1.0 | **Livré** |
| Entité Roaster (suggestions + ajout + dédoublonnage) | 1.0 | **Partiel** — pas de lat/lng, aliases, `verified`, MapKit, agent |
| Roast level | 1.0 | **Livré** |
| Roasted on | 1.0 | **Livré** |
| Setup broyeur + eau + défauts par méthode | 1.0 | **Livré** (187 broyeurs, 80 drippers, 12 minéraux) |
| Recettes de référence (attribuées, For your grinder) | 1.0 | **Livré** — onglet From the pros |
| Brew Recipe / With / Water | 1.0 | **Livré** |
| Taste 7 axes 0–10 + diagnostic + Suggested correction | 1.0 | **Livré** (trois mouvements, flags on) |
| Dictée du brew on-device | 1.0 | **Livré** (`DictationField` sur le texte libre) |
| `AIEvent` + flags | 1.0 | **Livré** |
| Retrait caféine | 1.0 | **Livré** |
| `species` hors formulaire, décaf exposé | 1.0 | **Livré** — species au caption si non-arabica |

## Should 1.0

| Item | PRD | App |
| --- | --- | --- |
| Prix, lot, cupping score | 1.0 | **Livré** |
| Timer guidé par étapes + rosace | 1.0 | **Partiel** — GuidedBrewView, **pas de rosace** |
| Compare | 1.0 | **Livré** (Brew again / Compare en tête) |
| Scan sachet / ticket / étiquette d’eau (IA) | 1.0 | **Partiel** — rôles Bag / Receipt + OCR local ; extract IA non branché ; eau non scannée |
| Recette adaptée (modèle, sous les règles) | 1.0 | **Livré** |
| Ask contextualisé (carte, setup, 3 brews) + base curée | 1.0 | **Partiel** — base seedée (PRD F + recettes + G3/G4/G7) ; hors-base = tag `general` |
| App Intents | 1.0 | **Partiel** — deux intents, pas de widget, micro pas auto-activé |

## Could 1.0

| Item | PRD | App |
| --- | --- | --- |
| TargetBand eau | 1.0 | **Livré** |
| Agtron | 1.0 | **Livré** — OCR + affichage + rangée dans *On the bag* |
| Harvest | 1.0 | **Livré** |
| Identification d’équipement par photo | 1.0 | **Absent** |
| Share Extension (URL produit → brouillon) | 1.0 | **Absent** |

## 1.1 / 1.2 / v2

| Item | PRD | App |
| --- | --- | --- |
| Correspondance broyeurs + calibration perso | 1.1 | **En avance** — convertisseur + calibration |
| Code-barres eau / Open Food Facts | 1.1 | **Absent** |
| Vue torréfacteur | 1.1 | **Absent** |
| Biais de goût dans les suggestions | 1.1 | **Absent** |
| Arbitrage on-device / serveur d’après `AIEvent` | 1.1 | **Absent** (les events sont collectés) |
| Insights | 1.2 | **En avance** |
| Agent Coach | 1.2 | **Absent** |
| Save as recipe enrichi | 1.2 | **Partiel** — le bouton existe, pas l’enrichissement 1.2 |
| Communauté, benchmark pro, balance BT | v2 | **Hors 1.0**, absent |

## Autres écarts notables

| Sujet | PRD | App |
| --- | --- | --- |
| Copy « Bought at » | 6.1 | Le champ s’appelle encore **Place** + **Place type** |
| Ask sur une carte *ou* un brew | 6.6 | Ask seulement depuis Recipes |
| Dictée des axes + diagnostic | 9.3 | Grammaire locale : paramètres, rating, saveurs, axes, agitation. Correction −/·/+ manuelle. |
| `captureSource` par champ | 7 | Par brew, volontairement |
| Commandes vocales pendant l’extraction | 6.5 | **Absent** |
| Masse cible saisie par étape | 6.5 | Tap pour confirmer la cible pendant le timer |
| `shareable` sur brew / recette | 11 | **Absent** |
| Seed torréfacteurs (annexe D) | 1.0 | **Absent** — l’index se remplit à l’usage |
| Seed connaissances (annexe F) | avant 1.0 | Table créée, **0 ligne** |
| Gate « aucune ligne à vérifier » (annexe H) | prérequis 1.0 | Recettes encore largement `partial` / `practice` ; A4 non seedée |
| Coffee Brewing Control Chart (fond du diagnostic) | 6.5 | Historique SCAA 1995, remplacé par `flavor-wheel.json` (SCA 2016) |

---

## Lecture

Le cœur « atelier » du Must 1.0 est dans l’app : on peut scanner, rattacher un torréfacteur, déclarer son kit, partir d’une recette de référence traduite en clics, logger un brew en le disant, et obtenir un *next time* d’une seule variable.

Ce qui empêche de dire « 1.0 close » :

1. **Capture incomplète** — le sachet / ticket / eau ne passent pas par le modèle ; Ask n’a ni contexte ni base seedée.
2. **Référence encore mince** — une eau, sept broyeurs, quinze recettes, zéro knowledge, zéro roaster seedé.
3. **Quelques Should visuels / d’entrée** — rosace, widget, Share Extension, Ask sur la carte.

Les Insights et le convertisseur de mouture sont en avance sur la roadmap. Ils ne débloquent pas le reste.
