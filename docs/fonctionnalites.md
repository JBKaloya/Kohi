# Kohi — Fonctionnalités actuelles et écart PRD

**Date** : 17 septembre 2026 · **PRD de référence** : [kohi-prd-v1.md](kohi-prd-v1.md) (brouillon 0.2, 9 septembre 2026)

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
| **Profil** | Icône `person.crop.circle` toujours visible. Kit, filtres, eau, défauts, onboarding, import (placeholder), IA expérimentale, compte. |
| **Account** | Rangée dans Profil, seulement si `Supabase.plist` est présent. `List` système, hors grammaire catalogue. |

Raccourcis système (App Intents, exposés à Siri / Shortcuts) :

- **Log a brew** — ouvre le parcours brew du café le plus récent (ou d’un café nommé).
- **Start a brew** — même chose, méthode déjà choisie, timer guidé prêt.

Pas de widget, pas de Control Center, pas de Share Extension.

---

## 2. Coffees — l’archive

Un seul écran d’accueil : des cartes posées sur du papier, un wordmark « Kohi », un bouton scan.

| Fonction | Comportement |
| --- | --- |
| Grille | Cartes triées par date d’ajout (la plus récente en haut). Pas de labels, pas de badges : l’image et son ombre *sont* la tuile. |
| Densité | Deux colonnes à chaque lancement. Pincer pour passer de 1 à 4 colonnes ; le choix tient pour la session, pas au-delà. |
| Recherche | Barre une fois l’archive assez grande (≥ 20 cartes) et qu’on a scrollé. Filtre texte (nom, torréfacteur, pays, région, variété, process, tasting notes, lieu) **plus chips** méthode / saveur (ids roue) / lieu. La grille hors recherche reste triée par date d’ajout. |
| Ouverture | Tap → fiche détail. Transition zoom (iOS 26+). |
| Atterrissage | Une carte tout juste scannée arrive en haut de la grille avec une animation de pose. |
| Vide | « Nothing collected yet » + invitation à scanner. |
| Face | Le scan aplati. |

---

## 3. Scanner une carte

Le bouton viewfinder ouvre un plein écran caméra (fond sombre). C’est le seul flux d’ajout de café.

### Près d’un café : une tasse ou un sachet ?

Quand le signal est fort, le scan demande d’abord *What are you scanning?* : **A cup at <café>** (une dégustation) ou **A bag for my collection** (le flux ci-dessous). Il faut :

- une localisation **déjà autorisée** (la home ne demande jamais la permission) ;
- un fix de moins de 5 minutes, précis à 65 m ;
- un café à proximité : un lieu de tes dégustations à 75 m, un lieu de la base à 75 m, ou un café Apple Maps à 40 m, dans cet ordre.

Sinon, le scan part droit vers le sachet, comme avant. Deux réponses *A bag* de suite au même endroit (≈ 100 m) font taire la question ; une réponse *A cup* la rétablit. Ces endroits restent sur le téléphone (`scan.spots`, 20 au plus), jamais synchronisés. *A cup* ouvre la même caméra, puis la dégustation directement à *Which coffee?*, lieu déjà choisi ; à l’enregistrement, la home passe sur *Tastings*.

### Capture

- Caméra arrière, détection de document en live (Vision). Overlay qui suit les coins.
- Coaching d’une seule phrase à la fois : poser la carte, se rapprocher, tenir à plat, éviter le glare, rester immobile.
- **Auto-capture** une fois la carte assez grande, droite, nette et stable (~0,6 s). Déclencheur manuel en plus.
- Import depuis la photothèque (même revue que la capture live).
- Simulateur : pas de caméra. Au-dessus du déclencheur, quatre choix : *Archive* (une carte bundlée), *Bag*, *Café card*, *Menu* (dessinés en code, posés sur la même surface).
- Sur iPhone, le bouton **Demo** est un menu avec les mêmes démos plus *Archive card*.

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

Sous le titre, un rail à deux onglets, **Coffee** et **Brews n**, qui reste épinglé en haut quand on scrolle ; **Ask** à droite du rail. La fiche s’ouvre sur *Coffee*, sauf quand un brew y envoie (raccourci *Log a brew*). Un brew enregistré depuis la fiche bascule sur *Brews* à la fermeture ; un brew abandonné ne change rien. La barre du haut n’a plus que le retour : le bouton *Cards* (scan / carte Kohi) a disparu.

**Coffee** : notes, roue, caption, originaux, recettes, invitation au kit, pages, note to self, actions. **Brews** : profil, journal (ou « No brews yet. » + *Brew this coffee*), *Tasted at*.

- **Tombstone** : nom (désambiguïsé), origine, altitude.
- **Notes** : chips horizontaux des tasting notes.
- **On the wheel** : chips outline des ids SCA 2016 reconnus dans ces notes. Toujours monté.
- **Caption** : torréfacteur, producteur, farm / wash station s’ils sont remplis, région, pays, altitude, variété, process, species **seulement si ce n’est pas arabica**, harvest, lot, roast (+ Agtron + méthode de décaf), **Roasted on** (+ jours), score, prix (`14 € · 250 g · 56 €/kg`), lieu, **Link** (URL produit, `arrow.up.right`), code label. Pas de « Brewed » ni de date d’ajout.
- **Lieu** : tap → Apple Maps ou Google Maps.
- **Show original** : texte d’origine après traduction (suffixe 日本語 / 中文).
- **Suggested recipe** : ligne 1 = nom + dose · ratio · temp ; ligne 2 = **For your grinder** (clics) ou **For your grinder: set a range**. **Use** à droite. La recette imprimée reste au-dessus, tag *Card*.
- **Brews** : ligne 1 = nom de recette (ou méthode) + rating ; ligne 2 = `dose · ratio · temp`. Long press : **Brew again** / **Compare**. Un brew qui a enregistré une *Suggested correction* la montre en `tag`.
- **Profile** (flag `cardProfile`) : radar médian (≥ 2 brews comparables) + meilleur en `inkMuted`, saveurs trouvées avec `✓` si déclarées, `n brews · avg · best`.
- **Pages & documents** : pièces jointes.
- **Note to self**.
- Actions : **Edit**, **Remove from archive**. *Ask* vit dans le rail, pas dans les actions.

### Dégustations (onglet Tastings)

Une nouvelle dégustation est un parcours d’une question par écran (`TastingFlow`) : *Where are you?* → *What's in the cup?* → *Which coffee?* → *How was it made?* → *How was it?* → *Anything to remember?* Cinq étapes quand le lieu est déjà connu.

- *What's in the cup?* : **Scan the card** (carte de café, menu ou sachet : le tri se fait à la lecture), **From my Coffee Collection** (grisé si la collection est vide), **Type it in**.
- Le scan d’une carte remplit les champs vides ; un menu demande lequel ; ce qui est deviné s’affiche en *Read, to confirm*. *Rescan* reste à portée.
- *How was it made?* et *How was it?* ont **Skip** et **Save now** (dès que nom et lieu sont là).
- Fermer avec du contenu demande *Discard this tasting?*
- Modifier une dégustation garde le formulaire d’un écran (`TastingComposeSheet`).

---

## 6. Éditer une carte

Même feuille pour une nouvelle carte et une édition. Champs libres partout ; vocabulaire réduit là où les cartes se répètent.

| Champ | Notes |
| --- | --- |
| Coffee, Country, Region, Producer, Altitude, Variety, Process | Texte. Process : quick picks Washed, Natural, Honey, Anaerobic, Carbonic Maceration, Wet Hulled. |
| **Roaster** | Texte + suggestions depuis l’index local. Choisir lie `roasterId`. « Add roaster » → nom, ville, pays, site, Instagram. Dédoublonnage nom normalisé + pays (« Already in the index… »). Hors ligne : texte libre. |
| Place | Recherche MapKit (POI + adresse), biaisée par la localisation si autorisée. |
| Tasting notes | Chips éditables. La roue n’est plus ici : le détail la montre déjà. |
| **On the bag** (toujours visible) | Roast (rail 6 crans, Super light → Dark, Agtron pré-rempli si vide), Agtron, **Roasted on**, Date (si pas de torréfaction), Price + devise, Bag. |
| Lot | Lot, Harvest, Cupping, Farm, Station, Link (URL produit), Decaf + méthode. |
| Recipe on card | Recette reconnue, dismissible. |
| **Bought at** (section visible) | Place + type. |
| Note to self | Texte libre. **Dictate** (`DictationField`) dicte dans ce champ. |
| **The rest of the bag** (en fin de formulaire) | Miniatures + **Scan the back label** / **Scan the roaster's recipe**. |
| Date | Date du café (distincte de l’ajout et de *Roasted on*). |

La méthode de brew n’est plus un champ d’édition : elle appartient au brew. `CoffeeCard.brewMethod` reste, alimenté par l’OCR, pour le filtre de la grille et le pré-remplissage.

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

Après le **premier scan** (1 100 ms après l’atterrissage), une feuille : « Bring what you have », puis trois questions sautables (méthode + **Which paper?**, broyeur, eau). Un flag `hasSeenSetupFlow` empêche toute relance automatique. Relance depuis Profil › Set up again. Import et photo du kit sont des rangées « soon ».

### Équipements

Un item = `kind · brand · model · notes · isDefaultFor[methods]` + champs par type.

| Kind | Champs |
| --- | --- |
| Grinder | Autocomplétion sur la base bundlée (187 modèles) ou custom, burrs, réglage (clicks / stepless / dial), plages par méthode quand elles sont vérifiées. |
| Brewer | Autocomplétion sur `brewers.json` (80 drippers : famille + bypass). Type, taille, formes de papier acceptées. Les filtres ne s’éditent plus ici. |
| Espresso machine | Autocomplétion (Sage, Gaggia, Silvia, Flair, Robot). Panier (g), pression. |
| Kettle | Autocomplétion (Stagg EKG, Buono, Brewista). Col de cygne, contrôle de température. |
| Scale | Autocomplétion (Acaia, Timemore, Hario). Résolution, timer intégré. |
| Accessory | Notes. |

Pas d’identification par photo.

### Filtres

Papier possédé, premier objet de kit à part entière (`FilterStock`, seed `filters.json`, 45 références). Rangées sous Your kit. Le premier papier d’un dripper devient son défaut. Compatible = forme × taille, avec dérogation `fits` (Sibarist L dans une Chemex).

### Eau

Profil = nom, source (*tap / filtered / bottled / recipe*), Ca / Mg / Na / HCO₃, **ppm**, additif + dose, notes. GH et KH calculés. Bandes cibles SCA (`TargetBand`) : TDS 75–250 ppm, GH, alcalinité — position, pas un verdict.

- Une eau seedée : **Montcalm** (étiquette).
- Source **Recipe** : Base (Distilled · RO · Tap · Filtered) → `MineralProduct` (12 produits : TWW vérifiés, Lotus / Apax / Aquacode / PCW / AKVO Minerals *composition not on file yet*).
- Source **Filtered** : `FiltrationSystem` (AKVO, Peak Water, BWT, Brita…).
- Pas de scan d’étiquette, pas de code-barres / Open Food Facts (1.1).

### Défauts et mouture

- Défauts par méthode (grinder / brewer / machine) : le parcours brew part de là.
- **Convert a setting** : conversion proportionnelle entre deux broyeurs, avec « ≈ » et la base de la conversion affichée.
- **Calibration perso** (« mon 22 clics ≈ 700 µm ») — prévue 1.1, déjà là.

### Features (lot 2)

Interrupteurs locaux (`LotFlags`) dans Profil › **Features** : `brewCompare`, `cardProfile`, `flavorOrigin`, `keepVoiceNote`. **On par défaut**, sauf `flavorOrigin` et `keepVoiceNote`. Taste et la roue ne sont plus optionnels. Ils cachent l’UI ; l’archive migre toujours. Override `KOHI_*` en DEBUG. Une note de brew est transcrite puis supprimée, sauf si **Keep brew recordings** est on.

---

## 9. Recipes

Trois onglets de niveau 2 (Mine · Suggested · **From the pros**), feuille **Filters** verticale, Ask en tête. **New recipe** sous Mine.

### Suggested

Rangées **coffee-first** : le nom du café (désambiguïsé si deux cartes se lisent pareil), la recette proposée à la taille filtrée (1 cup / 2 cups / batch), la provenance à droite. Une carte = une rangée. Tap → la carte, scrollée à *Suggested recipe*. Pas de bouton Use dans la liste : la fiche recette et le bouton `cup.and.saucer` ouvrent le brew.

La température d’une suggestion ne bouge que si la carte dit le niveau de torréfaction. **Moka** et **cold brew** sont exemptés : leur eau n’est pas un choix. La recette de base est classée (ratio dans la bande de la méthode, puis évidence), `mine` devant les références.

### Brasser

Le bouton `cup.and.saucer` ouvre un picker de café, puis le **même** parcours brew que la carte. Depuis une fiche recette, **Brew** ouvre ce parcours déjà rempli (Scope → Kit → Dial, puis Brew ou Log without timer).

### From the pros

Recettes embarquées hors ligne, attribuées. Filtre par dripper, cup, roast, grinder d’auteur, profile. Attribution = le nom. Pas de niveau de preuve à l’écran. **For your grinder** sur la fiche. **Total brew time** sous les étapes. **Brew this** : 5 cafés récents + Another coffee….

### Mine

**New recipe** + recettes sauvées depuis un brew. Insights en pied, avec ligne de provenance.

### Mine

Recettes sauvegardées depuis un brew. Insights en pied. Filtre source : From a brew · Saved from reference · Adapted.

### Ask (expérimental)

Bouton **ASK** en tête de Recipes, et « Ask about this coffee » sous Brews sur la carte, seulement si le flag **Answer questions** est on. Une question, une réponse, sources nommées. **Pas encore de contexte carte / setup / derniers brews.**

---

## 10. Brew — six écrans

Un seul host (`BrewFlowHost`) pour la carte, une recette, le FAB cup, un intent, l’édition d’un brew, et **Brew again**. Un seul seed (`BrewPrefill`) et un seul save (`BrewSession.finish`) : grind dans l’unité du moulin, eau, filtre, agitation, `captureSource`, `flowGs`. Fermer garde un brouillon ; au relancement, **Resume / Discard**.

Pensé pour le *deuxième* café : Save suffit si rien n’a changé. Pré-rempli depuis la recette, le dernier brew (éventuellement déjà ajusté par une Suggested correction), et les défauts du Setup. Six ticks depuis le FAB, cinq depuis une carte.

### 1. Which coffee

Depuis le FAB. Liste des cartes. Saute si on part d’une fiche.

### 2. Which recipe? (ex « What you're doing »)

Onglets **Pour Over / Immersion / Espresso** puis Last / Mine / From the pros. La liste est filtrée par famille : V60, Chemex, Kalita → Pour Over ; AeroPress, presse, switch, cold brew → Immersion ; espresso, moka → Espresso. Next toujours actif. **Build an express recipe** ouvre le builder. **Edit recipe** apparaît si la recette sélectionnée est `mine` ou `express`. Pas de Format ni de Parameters ici.

### 3. With what

Onglets **Pour Over / Immersion / Espresso**. La méthode suit le dripper ou la machine. Quatre rangées : Dripper (ou Machine) / Grinder / Filter / **Accessories** (multi-sélection, visible si des accessoires sont déclarés dans Profile). La rangée Filter reste visible : « No paper for a French press ». Les papiers espresso sont des disques. Les accessoires en préparation s’ajoutent à `Brew.equipmentIDs`.

### 4. Today's settings

Ligne **Recipe · nom · Edit** si une recette est attachée. **Paramètres** : dose, eau (ou Out en espresso), ratio calculé en lecture seule. Modifier l’eau redimensionne les masses d’étapes et affiche « Steps rescaled to X g » ; la dose seule ne touche pas la séquence. Le redimensionnement part toujours de `BrewSession.nominalRecipe`, la recette telle que choisie, jamais du dernier résultat — sinon chaque frappe se composerait sur la précédente. **Edit** ouvre `StepBuilderSheet` (accessoires par étape en plus). Recette `mine` / `express` mise à jour en place ; `reference` / `ai` copiée en `express`.

Ligne de rappel `with V60 02 · Comandante C40` + **Change** (machines espresso comprises). **Eau** : profil + température dans le même bloc. **Grind** : rail à part, clics si le moulin a une plage, sinon sept crans + **Set your range**. Pied : **Brew** 52 pt, **Log without timer**.

### 5. Pour

Séquence toujours présente (recette ou séquence dérivée). **GuidedBrewView** — un seul bloc, `Typography.number`, cible interpolée, tap = Next, Stop enregistre l’étape en cours. **Rinse** est un bloc à part (masse indicative selon la forme, **Skip**). Le chrono démarre en quittant ce bloc : le rinçage est hors TBT et hors débit. Tag de débit en direct. **Narrate** sous le bloc (fichier AAC, pas de reco live). Avance automatique après 3 s si `autoAdvance`. **Total brew time** à la fin. Le téléphone ne s’endort pas (`isIdleTimerDisabled`).

### 6. After — It's done

- **Summary** (FieldGroup) : dose et boisson toujours éditables.
- **What you did** + provenance (timer / narration / edited / default not confirmed). Une note vocale se transcrit ici en fond : shimmer, puis le texte (lexique café local, puis une passe d’orthographe `field-extract` si l’IA est on), puis les masses d’étapes. Le timer garde le temps ; la narration écrase la masse.
- **Pour curve** : grille 50 g, une ligne par versement, triée par le temps réel.
- **Rating 1–5** (cibles 44 pt) + pastille de complétude. Save marche avec un rating seul.
- **Taste** : radar + 7 axes. Le brew précédent de ce café est l’underlay.
- **Flavors** : *On the pack* / *In your cup* (roue SCA, toujours montée).
- **Correction** : − · +.
- **Comment** dicté (`DictationField`). Le verbatim de Narrate y est aussi recopié.
- **Suggested correction** : *Save what you did* en tête des leviers quand la séquence n’est pas confirmée.
- **Save as recipe** part des actuals.
- **Compare with…** (flag `brewCompare`).

Les titres de brew : `recipeName`, sinon la famille (Filter / Espresso / Batch), jamais le dripper.

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

## 12. Posters (retirés)

La génération de flyers IA a été retirée. Le scan est la face de la grille. Archive (prompt, stack, coût) : [ai-poster-retired.md](ai-poster-retired.md). La colonne Postgres `coffee_cards.poster` est conservée, plus écrite comme une feature.

---

## 13. IA expérimentale

Principes tenus : ne remplit que le vide ; règles d’abord ; badge / fallback ; clés côté serveur ; mesuré.

| Fonction | Où | État |
| --- | --- | --- |
| `card-vision` | Lecture carte | Livré (pas derrière le master switch). |
| `field-extract` (phrase → brew) | Dictée | Livré, si la grammaire locale est trop mince. |
| `field-extract` (image → sachet / ticket / eau) | Client + edge | **Code présent, UI absente.** Voir le registre. |
| `recipe-adapt` | Fiche recette, sous les règles | Livré, flag on, variante unverified + « pourquoi ». Cache session par recette + café. |
| `ask` | Onglet Recipes + fiche café | Livré comme feuille, **sans contexte**, base `knowledge` vide. Pas de cache (question nouvelle à chaque fois). |
| `suggested-correction` | After | Livré, flag on. Cache session. En DEBUG, bouton Model (pas d’appel auto). |
| Identification d’équipement par photo | Setup | Absent. |
| Foundation Models on-device | Extraction structurée | Absent (repli serveur uniquement). |
| Agents (enrichissement roaster, qualité, curateur, Coach) | Serveur | Absents. |

Profil : master **Experimental AI** (off par défaut) + interrupteurs par feature. Kill switch serveur `ai_flags`. Chaque appel écrit un `AIEvent` (feature, modèle, tokens, latence, accepté ou non). Profil affiche un résumé « Kept ».

Sans Supabase : voix on-device, OCR Vision, règles, recettes de référence et kit (Profil) fonctionnent. Vision lourde, Ask, adapt et extract serveur manquent.

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
| Dictée du brew on-device | 1.0 | **Livré** (`DictationField` sur le texte libre ; note vocale pendant le timer, transcrite ensuite, y compris écran verrouillé) |
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
