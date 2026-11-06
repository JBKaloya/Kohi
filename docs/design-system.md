# Kohi — Design system & fondation UI

Kohi est une archive de cartes de café. L’interface ne se comporte pas comme une app de productivité : elle se comporte comme un **catalogue de musée**. Les cartes sont des objets posés sur du papier. Le chrome est rare. Le vocabulaire visuel est petit, et tout ce qui décrit la sensation (couleur, type, ressorts, ombres, haptiques) vit dans quelques fichiers plutôt que dans les vues.

Ce document décrit le système tel qu’il est implémenté. Les valeurs font foi dans le code ; ici, elles sont le contrat.

---

## 1. Principes

1. **Objet, pas image.** Une carte a une ombre, un poids, un atterrissage. Elle n’a pas de cadre, pas de label, pas de badge. Dans la grille, l’objet et son ombre *sont* la tuile.
2. **Papier chaud, jamais blanc pur.** Toute l’archive vit sur `Palette.paper`. Le scan est la seule surface sombre : la caméra porte l’écran.
3. **Grammaire de catalogue.** Labels uppercase, tracked, monospacés, encre atténuée. Valeurs en SF Regular. Titres en Angusta. Filets hairline entre les rangées. Pas de cartes-conteneurs autour du texte.
4. **Un seul bouton sur la grille.** Tout le reste se rejoint en ouvrant une carte. Le scan flottant est l’unique affordance d’ajout.
5. **Retunable depuis un fichier.** Couleur → `Palette`. Type → `Typography`. Mouvement et ombres → `Motion`. Haptiques → `Haptic`. Si un nombre décrit comment quelque chose bouge, il n’appartient pas à la vue.
6. **Light only.** `KohiApp` force `.preferredColorScheme(.light)`. Il n’y a pas de thème sombre pour l’archive.
7. **Vocabulaire petit.** Moins de tokens, chacun avec un rôle. Un haptic nommé veut toujours la même chose. Un ressort n’est pas inventé localement.

---

## 2. Où ça vit

| Rôle | Fichier |
| --- | --- |
| Couleur | `Kohi/Design/Palette.swift` |
| Type | `Kohi/Design/Typography.swift` |
| Enregistrement Angusta | `Kohi/Design/AppFonts.swift` |
| Champs (états, hint, erreur) | `Kohi/Design/FormField.swift` (`FieldChrome`, `TextRow`, `NumberRow`) |
| Skeleton OCR | `Kohi/Design/ShimmerBar.swift` |
| Ressorts, ombres, press, overlay, radar, champs | `Kohi/Motion/Motion.swift` (`Motion.Radar`, `Motion.Field`) |
| Haptiques nommés | `Kohi/Motion/Haptics.swift` |
| Inclinaison relative du téléphone | `Kohi/Motion/DeviceTilt.swift` |
| Densité de grille | `Kohi/Grid/GridDensity.swift` |
| Chips / flow | `Kohi/Edit/TagField.swift` |
| Rails | `Kohi/Design/AxisRail.swift`, `Kohi/Design/GrindRail.swift`, `Kohi/Design/RoastRail.swift` |
| Dates relatives | `Kohi/Design/CatalogueDate.swift` |
| Style de press | `PressStyle` dans `Motion.swift` |
| Police bundle | `Kohi/Resources/AngustaTest-DemiBold.otf` + `UIAppFonts` dans `Info.plist` |

Les vues consomment ces tokens. Elles ne redéfinissent pas de couleurs d’archive, de fonts de catalogue, ni de springs.

**Exception assumée :** `AccountSheet` est une `List` système (sync, Sign in with Apple). Elle n’applique pas la grammaire catalogue. Ne pas l’utiliser comme modèle pour une nouvelle surface d’archive.

---

## 3. Couleur

Toutes les couleurs d’archive viennent de `Palette`. Rien n’est « presque paper » ailleurs.

| Token | RGB | Hex approx. | Rôle |
| --- | --- | --- | --- |
| `paper` | 0.980, 0.973, 0.957 | `#FAF8F4` | Fond de la grille, du détail, des sheets d’édition |
| `paperShade` | 0.965, 0.957, 0.937 | `#F6F4EF` | Papier un peu plus profond : placeholders d’image, highlight du shimmer |
| `ink` | 0.102, 0.094, 0.082 | `#1A1815` | Texte primaire, chips sélectionnés, tint global, dots de rating pleins |
| `inkMuted` | 0.541, 0.514, 0.471 | `#8A8378` | Labels, valeurs secondaires, chrome discret |
| `hairline` | 0.886, 0.867, 0.827 | `#E2DDD3` | Filets de catalogue, contours de chips, empty-state |
| `cardShadow` | 0.30, 0.26, 0.20 @ 22 % | — | Ombre portée des cartes sur le papier |
| `scanBackdrop` | 0.055, 0.051, 0.047 | `#0E0D0C` | Fond du flux caméra / review |
| `primary` | 130/255, 78/255, 52/255 | `#824E34` | Identité du café A sur un radar de comparaison ; champ requis manquant |
| `secondary` | 61/255, 92/255, 86/255 | `#3D5C56` | Identité du café B sur un radar de comparaison |

### Usage

- **Fond d’écran archive :** `Palette.paper.ignoresSafeArea()`.
- **Texte :** `ink` pour le contenu, `inkMuted` pour les métadonnées. Jamais de noir système (`.black` / `.primary`) sur le papier.
- **Tint des `NavigationStack` d’archive :** `.tint(Palette.ink)`.
- **Progress / activité :** `.tint(Palette.inkMuted)` sur papier, `.tint(.white)` sur le scan.
- **Sélection compacte (chip, rating, axe, cercle StepFlow) :** fill `ink`, texte `paper`. Repos : stroke `hairline`, texte `ink`.
- **Sélection linéaire (rangée, rail) :** le choisi porte un filet `ink` et une méta inversée (`CatalogueMark`, même capsule qu’un chip). Le reste reste `hairline` / `inkMuted`. Pas de checkmark. `TabRail` : label `ink` vs `inkMuted`, filet sous l’actif.
- **Scan :** le papier disparaît. Blanc, blanc à ~40–85 % d’opacité, capsules noires translucides. Le bouton primaire « Use » est une capsule blanche, texte `ink`.
- **Comparaison A/B :** `primary` et `secondary` uniquement quand deux séries se superposent — le radar de comparaison, le radar median/best de la fiche, la courbe cible/réel, les colonnes A/B. Une série seule reste encre. Jamais une troisième couleur. Pas sur les boutons, les tabs, ni la sélection. Chaque graphique porte sa légende en `tag`.

Le chrome reste encre et papier. `primary` / `secondary` ne sont pas des accents d’interface : ils identifient deux séries sur un même graphique. **Une seule exception :** `primary` marque un champ requis que Save attend (voir Formulaires → Champs requis). **La couleur vit dans l’objet carte** (fond, relief, sticker), **jamais dans le chrome**. Le chrome reste encre et papier. L’étiquette d’une carte Kohi est du papier : texte encre, filet hairline.

---

## 4. Typographie

Deux familles, un rôle chacune.

**Angusta Test DemiBold** — titres de display et wordmark. Enregistrée au lancement (`AppFonts.register()`), aussi listée dans `UIAppFonts`. PostScript name : `AngustaTest-DemiBold`.

**San Francisco** — tout le reste. Regular pour les valeurs et le corps. Medium monospaced pour les labels de catalogue et les tags.

| Token | Face | Taille | Poids | Design | Usage |
| --- | --- | --- | --- | --- | --- |
| `brand` | Angusta | 28 | DemiBold | — | Wordmark « Kohi » dans la nav de la grille |
| `title` | Angusta | 20 | DemiBold | — | Nom du café en détail |
| `barTitle` | Angusta | 19 | DemiBold | — | Nom du café dans la barre du détail, une fois le rail épinglé |
| `value` | SF | 14 | Regular | Default | Valeurs de champs, empty-state titre, champs de formulaire |
| `body` | SF | 14 | Regular | Default | Note personnelle, notes de brew |
| `subtitle` | SF | 13 | Regular | Default | Sous-titres, empty-state, « Retake », adresses |
| `coaching` | SF | 15 | Medium | Default | Overlay scan, bouton « Use » |
| `number` | SF | 34 | Regular | Default | Cible / chrono du brew guidé |
| `question` | SF | 22 | Regular | Default | Question d’un `StepFlow` |
| `tag` | SF | 11 | Medium | Monospaced | Chips, lignes de brew, compteurs, unités |
| `label` | SF | 10 | Medium | Monospaced | Labels de catalogue (via `catalogueLabel()`) |

Tracking des labels uppercase : `Typography.labelTracking` = **0.9**.

### Modificateur `catalogueLabel()`

Le traitement canonique d’un label de catalogue :

```
font(Typography.label)
tracking(0.9)
textCase(.uppercase)
foregroundStyle(Palette.inkMuted)
```

Sur une rangée étroite (`CatalogueRow`, `FormField`, `CatalogueBackButton`), on ajoute `lineLimit(1)` pour que `RECIPES` ou `COFFEE DOSE` ne cassent pas. Le tombstone de `CardDetailView` applique `catalogueLabel()` puis `.textCase(nil)` : même face et tracking, mais casse naturelle pour le nom / origine / altitude.

C’est le style des en-têtes de section (Notes, Brews, Method…), des labels de rangée (Roaster, Dose…), des actions destructives (« Remove from archive », « Discard this scan »), et du tombstone en tête de fiche.

Largeur fixe des labels de rangée :

| Surface | Largeur |
| --- | --- |
| `CatalogueRow` (paramètres de recette) | **120 pt** (`CatalogueRow.labelColumn`) |
| `CaptionBlock` (détail) | 78 pt |
| Formulaires (`CardEditSheet`, `BrewScopeView`, `BrewKitView`, `AfterBrewSheet`) | 74 pt |
| Colonne date / « Card » dans `BrewList` | 52 pt |

---

## 5. Mouvement

Tous les springs et tous les nombres de mouvement vivent dans `Motion`. Les vues appellent `withAnimation(Motion.snappy)` ; elles ne construisent pas de `Animation.spring(...)`.

### Springs

| Token | Response | Damping | Rôle |
| --- | --- | --- | --- |
| `quick` | 0.22 | 1.00 | Press, toggles de chips, swap d’image. Critique, sans overshoot |
| `snappy` | 0.35 | 0.82 | Densité, contenu de sheet, coaching |
| `gentle` | 0.55 | 0.90 | Grandes surfaces : empty state, scroll vers une carte qui atterrit |
| `land` | 0.70 | 0.62 | **Réservé** à l’atterrissage d’une carte dans la grille. Overshoot volontaire |
| `tracking` | 0.28 | 0.86 | Doigt en vol (`interactiveSpring`) |

Stagger : `Motion.stagger(index, step: 0.035, cap: 0.28)` — délai d’apparition d’une série, plafonné pour que les listes longues ne traînent pas.

### Radar (`Motion.Radar`)

Heptagone de goût. `radiusFraction` 0.38, `labelOffset` 14, `stroke` 1, `fillOpacity` 0.08, `vertex` 4, `rings` 2/4/6/8/10. Aucune magie dans la vue.

### Press

`PressStyle` scale le label via `configuration.isPressed` (le visuel ne vole jamais le tap). Animation `quick`.

| Surface | Scale |
| --- | --- |
| Scan button (grille) | `Chrome.buttonPressScale` = 0.92 |
| Shutter | `Chrome.shutterPressScale` = 0.88 |
| Tuile de carte | `Tile.pressScale` = 0.965 |

### Atterrissage d’une tuile (`Motion.Tile`)

Une nouvelle carte arrive *au-dessus* du papier, puis se pose. Toutes les valeurs « air » interpolent vers « rest » sur un progress 0→1.

| | En l’air | Au repos |
| --- | --- | --- |
| Scale (extra) | +0.22 | 0 |
| Lift | 34 pt au-dessus | 0 |
| Opacity | 0.2 | 1 |
| Shadow opacity (fraction de `cardShadow`) | 0.55 | 1.0 |
| Shadow radius (fraction de la largeur) | 0.16 | 0.045 |
| Shadow drop (fraction de la largeur) | 0.10 | 0.022 |

Le haptic `landing` part à **190 ms** (`touchdown`), au premier contact, pas à la fin du spring. La fenêtre « newly landed » dure 1100 ms.

### Carte-objet en détail (`Motion.Object` + `Parallax`)

La fiche centre l’objet à **68 %** de la largeur écran. Double ombre : un contact serré (noir 10 %, radius 0.6 % de largeur) et l’ombre papier (`cardShadow`, radius 6 %, drop 3 %).

L’inclinaison est **relative** : le premier sample de `DeviceTilt` devient l’origine, pour que l’effet parte du repos que l’on soit assis ou allongé. Frame `xArbitraryZVertical` (pas de dérive vers le nord magnétique). Clamp à ±0.5 rad, lissage 0.12.

À pleine inclinaison : 5° de rotation 3D, perspective 0.5, translation 10 pt, ombre qui recule de 6 pt (c’est ce qui *soulève* la carte). Un sheen blanc (`plusLighter`, opacity 0.16, bande 55 % de largeur) glisse en travers.

Pinch 1–5× (`zoomRange`) **dans** la silhouette : tilt et sheen s’arrêtent, l’objet ne quitte pas sa place. Double-tap à `zoomTap` (2.5×), toujours masqué par la plaque.

### Overlay de scan (`Motion.Overlay`)

Le contour se resserre pendant le lock. Chaque propriété est une paire open → locked, interpolée par `progress` :

| | Searching | Locked |
| --- | --- | --- |
| Fill opacity | 0.06 | 0.16 |
| Stroke opacity | 0.55 | 1.0 |
| Stroke width | 1.5 | 3.0 |
| Tick length | 16 | 28 |
| Tick width | 2.5 | 4.0 |

### Grille (`Motion.Grid`)

Le pinch est amorti (damping 0.55) et clampé à 0.72…1.5 avant de snapper une densité. Seuil de geste : `minimumScaleDelta` 0.08. Au franchissement du bucket de thumbnail (1024 ↔ 512), préchauffer 40 cartes.

### Chrome

Empty state : fade + rise de 14 pt, delayed de 0.12 s sur `gentle`, pour ne pas courir après la grille.

### Champs (`Motion.Field`)

| Token | Valeur | Rôle |
| --- | --- | --- |
| `optionalRuleOpacity` | 0.55 | Filet d’une rangée facultative vide |
| `hintRise` | 4 pt | L’indice arrive d’en dessous, `snappy` |
| `keyboardClearance` | 0 pt | Hook only — iOS already lifts the focused field |
| `focusShadePad` | 6 × 3 pt | `paperShade` derrière la valeur, comme `GuessHighlight` |
| `focusShadeRadius` | 5 | Coin du shade |
| `residueHold` | 320 ms | Un dérivé barré (ratio, µm) avant de disparaître |

Le filet interpolé `hairline` → `ink` au focus est `quick`. Pas d’anneau. Pas de nudge des rangées voisines.

---

## 6. Haptiques

Vocabulaire fermé. Chaque cas *veut dire la même chose* partout. Warmup au launch (`Haptics.prepare()`) pour que le premier tap de session arrive à l’heure. Les vues utilisent `.haptic(_:trigger:)`.

| Nom | Feedback | Moment |
| --- | --- | --- |
| `detectionLock` | impact light | Le tracker a verrouillé une carte |
| `capture` | impact medium | Le shutter a tiré |
| `saved` | success | Une carte / un brew est écrit (pas sur un *nouveau* scan : l’atterrissage suffit) |
| `landing` | impact soft | La carte touche le papier |
| `deleted` | warning | Une carte quitte l’archive, ou un save impossible (champ requis manquant, nom trop court) |
| `densityChange` | selection | Le pinch a snappé un nouveau nombre de colonnes |
| `tap` | impact medium | Chip, rating, axe, More, start/stop timer dans le parcours brew |
| `tick` | impact light | Chaque seconde du timer de brew |
| `stepAdvance` | impact light | Next d’une étape guidée |

Ne pas ajouter un impact « pour le plaisir ». Si le moment n’est pas dans cette liste, soit il n’a pas de haptic, soit on étend l’enum avec un nom qui décrit le *pourquoi*.

---

## 7. Surfaces

### Archive (papier)

Grille, détail, edit, brew, place search, attachment detail, **Profil**, onboarding.

- Fond `paper`, scroll indicators cachés.
- Nav inline, titre souvent vide ou catalogue. Toolbar de la grille : wordmark Angusta, fond de barre **caché**.
- Sheets : padding horizontal **26**, top **14**, bottom **60**. Groupes espacés de **28–30**.
- Détail : padding horizontal **28**, bottom **72**. Bloc objet : padding vertical **52**.
- Grille : padding top **16**, bottom **190** (place pour le bouton circulaire — scan sur Coffees, `cup.and.saucer` sur Recipes).

### Profil

Feuille papier, grammaire catalogue. Pas de titre Angusta ; le premier label est **YOUR KIT**. L’icône `person.crop.circle` est toujours visible. Compte / sync restent une `List` système ouverte depuis une rangée, seulement si `Supabase.plist` est là.

### Scan (obscur)

Caméra, overlay, review. Fond `scanBackdrop`. Le chrome est blanc / translucide pour laisser l’image porter l’écran.

- Coaching : SF Medium 15, blanc, capsule noire à 34 % d’opacité. Transition opacity + offset 6 pt, spring `snappy`.
- Shutter : disque blanc 68 pt, anneau blanc 40 % décalé de 6 pt.
- Review « Use » : capsule pleine largeur, padding H 46 / V 15, fond blanc, texte `coaching` + `ink`.
- Toggle **Whiten** : capsule — selected = fond blanc + `ink` ; idle = blanc 16 % + blanc 85 %. Première fois : « Whiter paper, sharper text ».
- Quad : blend `plusLighter`. Handles 13 pt (18 en drag), hit target plus large, loupe circulaire épinglée au coin opposé au doigt.

### Compte

`List` UIKit/SwiftUI standard. Hors système. Ne pas y porter `catalogueLabel` ni `Palette.paper` à moins de redessiner toute la feuille.

### Composants de parcours (lot 4 / brew v2)

| Composant | Fichier | Rôle |
| --- | --- | --- |
| `BrewFlowHost` | `Kohi/Recipes/BrewFlowHost.swift` | Seul présentateur du parcours brew (Scope, Kit, Dial, Pour, After). Fermer garde un brouillon. |
| `StepFlow` | `Kohi/Design/StepFlow.swift` | Chrome d'une question : segments 24×1, question 22 pt, Skip, Next 52 pt. Six ticks depuis le FAB, cinq depuis une carte. Un `secondaryTitle` se pose entre Skip et Next (*Save now*, *Rescan*). |
| `TastingFlow` | `Kohi/Tastings/TastingFlow.swift` | Nouvelle dégustation, une question par écran : *Where are you?*, *What's in the cup?*, *Which coffee?*, *How was it made?*, *How was it?*, *Anything to remember?* Six ticks, cinq quand le lieu est connu. *Save now* sur les deux étapes bonus dès que nom et lieu sont là. Fermer avec du contenu demande *Discard this tasting?*. L'édition reste sur `TastingComposeSheet(editing:)`. |
| `ScanIntentSheet` | `Kohi/Grid/ScanIntentSheet.swift` | *What are you scanning?* Sheet papier courte, deux rangées de 52 pt qui nomment l'objet (*A cup at …* / *A bag for my collection*). Glisser vers le bas n'ouvre rien. |
| `CatalogPicker` | `Kohi/Design/CatalogPicker.swift` | Catalogue unique dripper / moulin / papier. FROM YOUR KIT (une ligne par objet possédé), ALL par sous-famille, Add manually. |
| `PourCurve` | `Kohi/Design/PourCurve.swift` | Masse cumulée contre le temps réel (`at`), pas la cible. Grille 50 g. |
| `StepBuilderSheet` | `Kohi/Recipes/StepBuilderSheet.swift` | Recette express : nom, totaux, gabarits, blocs. |
| `InsightBlock` | `Kohi/Design/InsightBlock.swift` | Toute sortie déduite ou modèle : titre, phrase, **provenance obligatoire**. |
| `FieldGroup` | `Kohi/Design/FieldGroup.swift` | Groupes d'édition seulement (jamais en lecture). Filet, pas de fond. |
| `DictationField` | `Kohi/Design/DictationField.swift` | Mic + Dictate sur tout texte libre. Toujours visible ; un tap dit pourquoi si le moteur n'est pas prêt. |
| `VoiceNoteControl` | `Kohi/Design/VoiceNoteControl.swift` | **Narrate** : enregistrement fichier d'un brew, « Recording — tap to stop » + chrono. |
| `GrindPreview` | `Kohi/Design/GrindSample.swift` | Sachet de mouture, bandes G1 en µm, trait 1 mm. |
| `KitRecallRow` | `Kohi/Design/KitRecallRow.swift` | Ligne `with V60 02 · Comandante C40` + CHANGE sur Today's settings. |
| `FilterStockRow` | `Kohi/Setup/KitRow.swift` (`FilterKitRow`) | Papier possédé, même grammaire qu'un `KitRow`. |
| `touchTarget(44)` | `Typography.swift` | Plancher tactile invisible, ne change pas le dessin. |

**Règle d'affordance.** Une affordance ne disparaît jamais sur une condition calculée. Elle s'affiche avec sa raison. Which recipe? et With what ont trois familles : **Pour Over / Immersion / Espresso**. La rangée Filter reste visible : « No paper for a French press ». La rangée Accessories n'apparaît que si des accessoires sont déclarés. Le papier ne se choisit plus sur Today's settings. `DictationField` (Comment, nom de recette) suit la même règle ; Which recipe? n'a pas de Dictate.

**Règle d'arithmétique.** Un chiffre de recette n'est redimensionné qu'à un seul endroit : [`RecipeScaling`](../Kohi/Process/RecipeScaling.swift). Aucune vue ne recalcule une masse. Trois invariants y vivent — le **rinçage n'est jamais mis à l'échelle** (son eau appartient au papier, pas à la recette), le **facteur est borné** à `0.2...5` (au-delà c'est une frappe en cours, pas une intention), et on **compare l'espresso par la boisson sortie, le reste par l'eau entrée**. Les actions d'étape proposées viennent de `DefaultSequence.actions(for:)`, jamais d'une table locale à un écran : c'est ce qui garantit qu'un espresso ne propose pas de Bloom.

---

## 8. Layout & rythme

### Grille

`GridDensity` : 1 à 4 colonnes. Le pinch *agrandit* les cartes (moins de colonnes).

| Densité | Colonnes | Gutter | Padding H |
| --- | --- | --- | --- |
| `.one` | 1 | 56 | 44 |
| `.two` | 2 | 34 | 30 |
| `.three` | 3 | 24 | 22 |
| `.four` | 4 | 17 | 16 |

Le whitespace reste généreux même à 4 colonnes — c’est ce qui fait lire la grille comme un tapis, pas comme un feed. Densité au lancement : **2** (`GridDensity.launch`), à chaque lancement. Le pinch tient pour la session, rien n'est mémorisé.

Search : n’apparaît qu’à partir de **20 cartes**, et seulement après un scroll > 200 pt (ou si une query est déjà là).

Transition grille → détail : zoom matched (`navigationTransition(.zoom)` iOS 26+, `matchedTransitionSource` sur la tuile).

### Détail — ordre de lecture

1. Tombstone (catalogue, casse naturelle)
2. Objet centré
3. Titre Angusta
4. Rail `TabRail` **Coffee** / **Brews n**, épinglé sous la barre en scrollant, padding 28, fond papier. *Ask* en trailing (si le flag est on). Changer d'onglet une fois le rail épinglé remonte au rail. Épinglé, le nom du café apparaît au centre de la barre du haut (`barTitle`, fondu + 6 pt), sur la ligne du retour **COFFEES**.

**Coffee** (ouverture par défaut, et avec `startsAtSuggested`) :

1. Notes (chips outline, scroll horizontal)
2. On the wheel (ids reconnus)
3. `CaptionBlock` (filets)
4. Originaux CJK repliés
5. **Suggested recipe** / recettes
6. Invitation au kit (si vide)
7. Pages & documents
8. Note to self
9. Actions en `catalogueLabel` (Edit, Remove)

**Brews** (ouverture quand un brew vous y envoie ; sélectionné à la fermeture d'un brew enregistré, pas d'un brew abandonné) :

1. `CardProfile` (≥ 2 brews comparables)
2. Journal (`BrewsSection`) ou « No brews yet. » + *Brew this coffee*
3. *Tasted at* (dégustations en café)

Aucun bloc de brew dans Coffee, aucune action de carte dans Brews. La barre du haut n'a que le retour **COFFEES** : plus de bouton *Cards*.

### Formulaires

Rangée canonique :

```
[label 74 pt]  [champ Typography.value]
──────── hairline 1 pt ────────
```

Espacement interne label/valeur : **16**. Stack verticale label→filet : **7**. Groupes : titre `catalogueLabel` + contenu, spacing **14**.

Cinq visages, zéro chrome nouveau. `FieldPresence` est `useful` ou `optional` — pas d’astérisque. Les rares champs requis sont décrits plus bas.

| État | Label | Placeholder / valeur | Filet |
| --- | --- | --- | --- |
| Vide facultatif | `hairline` | placeholder `hairline` | `hairline` 55 % |
| Vide utile | `inkMuted` | placeholder `hairline` | `hairline` |
| Plein | `inkMuted` | valeur `ink` | `hairline` |
| Focus | `inkMuted` | `paperShade` sous la valeur | `ink` |
| Invalide / manquant | `primary` | bulle `paperShade` collée, texte `primary` | `primary` |

L’indice (`Typography.tag`) n’existe qu’au focus, une ligne, et dit *pourquoi* le champ existe. Il disparaît au blur. Une erreur (nom trop court, champ requis vide) prend sa place : couleur café `primary`, jamais de rouge, pas de rangée extra.

L’unité d’un `NumberRow` est `hairline` tant que le champ est vide, `inkMuted` une fois remplie.

`FlowLayout` : spacing chips **7**, row spacing **8**.

#### Champs requis

Les pages sont denses : un bouton qui manque ou qui est grisé ne dit pas ce qu’il attend.

- **Save n’est jamais caché ni grisé** à cause d’un champ requis. `.disabled` reste réservé à une action en cours (`isAsking`, `isSyncing`) ou déjà faite.
- **Un tap sur Save trop tôt** n’écrit rien. Les champs qui manquent passent en `primary` (label, filet, bulle d’erreur courte), haptic `deleted`, et la page remonte au premier d’entre eux. Le marquage disparaît dès que le champ est rempli.
- Hors `FormField`, un label se marque avec `catalogueLabel(missing:)`.
- **Une suggestion sûre est déjà choisie.** Le lieu le plus proche d’une dégustation arrive présélectionné, affiché comme un fait avec « Change » à côté. Ce qui n’est qu’une hypothèse (pas de position) reste une question à taper.

Edit d’une carte : épine toujours visible (Coffee, Roaster, Place, Process). Origin et On the bag se plient tant qu’ils sont vides, et s’ouvrent si le scan a trouvé quelque chose.

### Tuile

Ratio **4:5** (`CardTileLayout.aspectRatio`) sur la grille. Le détail utilise le ratio réel du scan (défaut 0.75).

Deux faces. **Kohi cards** (défaut) est un paysage : terre de l’origine en bas, notes au milieu, ciel de l’altitude en haut, grain d’impression ; le symbole du sachet en relief ; une étiquette papier (torréfacteur, titre, lieu) ; le sticker de l’origine collé sur le coin de l’étiquette. Même café, même carte : tout se déduit des champs et de l’identifiant. **Scans** reste l’objet nu, à un tap.

Mise en page en part de la largeur de la carte (`KohiCard`) : *Label* (défaut, étiquette `#FBF8F2` en bas) ou *Full bleed* (texte posé sur le champ, encre ou papier selon le fond), au choix dans le Profil. Le symbole prend l’un de quatre traitements (Emboss, Ink, Halftone, Pattern, ou Auto) ; en fiche, le relief suit l’inclinaison. Toute version de rendu passe par `CardStandard.version` : l’archive est redessinée une fois, en tâche de fond.

---

## 9. Composants

### `CardTile`

Objet nu. `CardImageView` + ombre interpolée. `PressStyle` 0.965. Pas de coin forcé : le bitmap porte sa propre silhouette.

### `CardObject`

La même image, traitée comme une chose : tilt, sheen, double ombre. Le sheen est maské par l’image (pas de halo hors carte). Stoppe le motion quand la scène n’est plus active, et dès qu’un pinch commence. Pinch 1–5× et double-tap zooment **dans** la silhouette (`mask` de la plaque au repos) — pas d’objet flottant, le scroll de la fiche reste.

### `CatalogueBackButton`

Chevron 10 pt + label catalogue, 44 pt de cible, `fixedSize` horizontal. À poser en `safeAreaInset` (comme **COFFEES** / **RECIPES**), pas en `ToolbarItem(placement: .cancellationAction)` — iOS 26 glasserait le contrôle en pastille et casserait le mot.

### `CardImageView`

Choisit le plus petit bucket de thumbnail qui couvre la largeur demandée. Interpolation `.high`. Placeholder `paperShade`. Animation `quick` sur l’arrivée de l’image.

### `FormField` / `TextRow` / `NumberRow`

La rangée de formulaire. `FieldChrome` décide le ton ; la vue n’invente pas de couleur. `TextRow` et `NumberRow` portent le `FocusState`, l’indice et l’erreur. `DerivedValue` barre le chiffre précédent (ratio, µm) quand il est écrasé. `completenessPulse` pose `GuessHighlight` sur les rangées manquantes d’un brew, pas sur le bloc More.

### `CaptionBlock`

« Tombstone » : labels `catalogueLabel`, valeurs `value` + `ink`, filet `hairline` 1 pt entre les rangées, padding V **11**. Pas de container. Place tappable → chevron `arrow.up.right` 9 pt semibold, `inkMuted`.

### `CatalogueChoice` / `CatalogueMark`

Une seule voix de sélection. Compact = inversion (`TagChip`). Linéaire = filet `ink` + `CatalogueMark` (capsule ink / paper) sur la méta de rangée (provenance, kind). `RecipeRowView.isSelected`, `KitRow.isSelected`, listes de café / brew à choisir. Pas de `checkmark`.

### `BrewList`

Même grammaire, plus dense (padding V **10**, `Typography.tag`). **Suggested** (et la recette imprimée *Card*) au-dessus du log, pas dedans. Les brews : première ligne = `CatalogueDate` (`just now` / `yesterday` / `3 days` / date) + dots ; deuxième = nom ou méthode · dose · ratio · temp. CTA « Log a brew ». Long press : Brew again / Compare with….

### `CatalogueDate`

Quand un brew, une recette *Mine* ou un sync a eu lieu. Jour même → `just now`. Veille → `yesterday`. 2–5 jours → `3 days`. Au-delà → date (`11 Sep`, avec l’année si ce n’est pas cette année). Pas pour la fraîcheur de torréfaction (`Roasted on` garde la date + `23 d`).

### `AxisRail`

Rail hairline 1 pt, 11 ticks, dot 8 pt, rangée 34 pt, slop ±10. Tap la valeur courante → `nil`. Accessibilité : `accessibilityAdjustableAction` 0–10.

### `GrindRail`

Sept crans toujours (`extra-fine` → `extra-coarse`), Fine à gauche / Coarse à droite. Pas de `Slider` système. Quand le broyeur a une plage, une colonne `Typography.number` + unité à droite est liée dans les deux sens : un cran interpolé dans la plage, un nombre tapé déplace le point. Les deux écrivent `position` et `value`, jamais `raw`. Caption sous le rail : le grade (`medium-fine`). `GrindPreview` à gauche, bandes G1 en µm, trait 1 mm.

Le CTA d’un `StepFlow` / Kit / Dial / After se replie tant qu’un champ a le clavier — le bouton ne monte pas au milieu de la fiche.

### `RoastRail`

Six crans, Super light à gauche / Dark à droite. Dégradé parchment → espresso sous le filet. Caption à droite : le libellé sans tiret. Un cran pré-remplit Agtron (95 / 85 / 75 / 65 / 55 / 45) seulement si le champ est vide ou encore à la médiane du cran précédent.

### `TasteRadar`

Heptagone `Canvas` / `Path`. Rayon, fill, épaisseurs dans `Motion.Radar`. Axe non noté : pas de sommet. Fill et dots suivent la couleur de série. Lecture seule : `ink`. Comparaison : A = `primary`, B = `secondary`. Animation `Motion.quick`. Un seul élément a11y.

### `FlavorPicker`

Recherche, Quick, All replié (9 familles). Encre / hairline / papier, jamais les `color` du JSON.

### `BrewCompareSheet`

Picker B + chips Best / Previous / Any coffee same method. Radar A `primary` / B `secondary`, légende A · B, colonnes teintées. Rangées A · B · Δ. Phrase + tag `practice`.

### CTA bas de page

Capsule 52 pt, fill `ink`, texte `paper`. Si l’action n’est pas encore possible, **le bouton disparaît** — pas de fill `hairline` fantôme. `RecipeDetailSheet` : Brew n’existe que lorsqu’un café est choisi.

### `CardProfile`

Radar médian + meilleur brew. « Found in your brews » + `✓`. `tag` : n brews · avg · best.

### `TagChip`

Capsule. Idle : stroke `hairline`, texte `ink`. Selected : fill `ink`, texte `paper`. Padding H 11 / V 7. Remove : `xmark` 8 pt. Animation `quick`. Variante outline seule (notes en détail) : padding H 10 / V 6, pas de fill.

### `TagField`

`FlowLayout` de chips + `TextField` `value`, autocapitalization `.words`.

### `CircleButton`

Affordance circulaire en bas de catalogue. `viewfinder` 22 regular sur Coffees, `cup.and.saucer` 22 regular sur Recipes, `ink`, hit 62×62. Glass : `glassEffect(.regular, in: .circle)` iOS 26, sinon `ultraThinMaterial` + ombre noire 12 % (radius 8, y 4). Hit slop : inset −20. `ScanButton` est un habillage de `CircleButton`. Labels a11y : « Scan a card » / « Start a brew ».

### `ShimmerBar`

Placeholder OCR. Capsule 4 pt, `hairline` 55 %, largeur fixe si donnée (`width:`), sinon tirée une fois entre 60 et 120, hauteur 14. Highlight `paperShade` qui traverse en 1.2 s, `easeInOut` repeat. Une barre par champ encore vide.

### `AttachmentStrip`

Thumbs H **80**, radius 4 continuous. Badge rôle : cercle `ink` 60 %, mono 8 bold. Caption : capsule noire 50 %, mono 8. Add : stroke `hairline`, plus light 14, `inkMuted`.

### `EmptyStateView`

Rectangle 132×176, radius 3, stroke `hairline` 1.2. Trois capsules de filet en haut (64 / 44 / 54). Titre `value` + `ink`, sous-titre `subtitle` + `inkMuted`. Spacing 26 / 7.

### Rating (brew)

Lecture : dots 5 pt. Édition : cercles 22 pt, fill `ink` ou stroke `hairline`. Toggle off si on retape la même note.

### Axes de correction (brew → More)

Trois pas − / · / + . 28×28, radius 6. Selected : fill `ink`, glyphe `paper`. Idle : stroke `hairline`. Mono 14 medium.

### Actions destructives

Toujours `catalogueLabel()` + `.buttonStyle(.plain)`. Pas de bouton rouge, pas de fill. Le haptic `deleted` (warning) porte le poids. Confirmation système uniquement pour les intents externes (ouvrir Maps).

---

## 10. Iconographie

SF Symbols, light à semibold, petits.

| Symbole | Taille / poids | Où |
| --- | --- | --- |
| `viewfinder` | 22 regular | Scan button (Coffees) |
| `cup.and.saucer` | 22 regular | Start a brew (Recipes) |
| `person.crop.circle` / `.fill` | système | Profil (toujours) |
| `plus` | 10 semibold / 14 light | Log a brew / add page |
| `xmark` | 8–10 semibold | Retirer un chip / une recette |
| `chevron.down` / `.right` | 8 semibold | Disclose original / More |
| `arrow.up.right` | 9 semibold | Place / Link → Safari |
| `timer` / `stop.circle.fill` | 16 / 18 | Brew timer |
| `drop` / `drop.fill` | 13 medium | Whiten |
| `sparkles` | 10 semibold | Ask / Suggested correction / variant |
| `checkmark` | 10 semibold | Rangée sélectionnée |
| `mic` | 10 semibold | Dictate |
| `chevron.left` | 10 semibold | Retour COFFEES / RECIPES |
| `exclamationmark.circle` | 11 | Scan illisible |
| `arrow.down.doc` / `camera` | 10 semibold | Placeholders d’import (inactifs) |

Pas d’illustration custom hors Angusta et les cartes elles-mêmes. Les stickers d’origine sont des assets générés depuis des recettes en code (`OriginStickers.xcassets`, source `docs/card-lab/`). Un pays, un sticker. L’empty state *dessine* une carte en filets, il n’importe pas d’asset. **Les glyphes d’équipement sont dessinés de la même façon** : un `Path` en code (`EquipmentGlyph`, grille 24, trait 1 pt, round cap/join, pas de fill), 28 pt en rangée, 52 pt dans l’onboarding (`StepChoice`). `inkMuted` au repos, `ink` si l’item est un défaut. Jamais dans la grille, sur une carte, ni dans `BrewList`.

---

## 11. Copy

Anglais, sobre, phrase courte. On dit ce qui est vrai.

- Empty : « Nothing collected yet » / « Scan the card that comes with your next coffee »
- Coaching : une seule chose à la fois — « Place a card on a flat surface », « Move closer », « Hold the phone level », « Tilt away from the light », « Hold still »
- Review : « Retake », « Use », « Whiten »
- OCR : « This does not look like a card » / « Nothing recognised on this scan »
- Actions : « Log a brew », « Edit », « Remove from archive », « Discard this scan », « Brew again », « Compare »
- Profil : « Your kit », « Filters », « Water », « Defaults », « Set up again », « Import & export », « Experimental AI », « Features », « Account »
- Onboarding : « Bring what you have », « How do you brew? », « Which paper? », « What do you grind with? », « What water? »
- Recipes : Mine · Suggested · From the pros ; Ask à droite ; bouton `cup.and.saucer` pour aller aux recettes
- Brew : « Coffee dose », « Water weight », « Beverage », « Today's settings », « Change », « Add the paper you use », « Add the water you use », « Log without timer », « Suggested correction », « For your grinder », « For your grinder: set a range », « Dictate », « Narrate », « What you did », « Followed the plan », « Default sequence », « Which coffee? », « With what? », « It's done », « Record a brew note », « Recording — tap to stop », « Total brew time », « Rinse more »
- Provenance : `DERIVED FROM…` / `SOURCE:…` / `GENERAL COFFEE KNOWLEDGE`. Pas de *verified* à l’écran.
- Cartes sans nom : producteur / ferme / station, puis origine, puis torréfacteur ; variété en dernier. Suffixe `·` seulement en cas de collision. `KohiCard` applique la même chaîne que `displayName`.

Les labels de champs sont le vocabulaire du café (Roaster, Producer, Process…), pas des intitulés d’UI (« Coffee name »). Un placeholder est un **exemple vrai** (`Placeholders.swift`), jamais une consigne. Un indice de focus dit pourquoi le champ existe (`FieldCopy`), jamais comment le remplir.

---

## 12. Accessibilité & plateforme

- Color scheme forcé light. Contraste ink / paper volontairement chaud, pas WCAG-max ; ne pas « corriger » vers du noir 100 %.
- `ScanButton` / `CircleButton` ont un `accessibilityLabel`. Les images de cartes sont `Image(decorative:)` — le nom vit dans le catalogue, pas dans l’alt de la tuile.
- iOS 26 : glass sur le bouton circulaire, zoom navigation. Fallbacks : material + push standard.
- Hit targets : shutter / bouton circulaire ~62–68 pt ; chips, ratings et rangées d’action passent par `touchTarget(44)`. Le bouton **Brew** du parcours recette fait 52 pt, et n’est dessiné que s’il est actionnable.

---

## 13. Comment étendre

**Changer la sensation de l’app** — ouvrir `Palette`, `Typography`, ou `Motion`. Ne pas retoucher dix vues.

**Nouvelle couleur** — seulement si un rôle n’existe pas encore. Si c’est « un paper un peu plus gris », c’est déjà `paperShade` ou `hairline`.

**Nouvelle font** — un token dans `Typography`, pas un `.font(.system(size:))` dans une vue. Les tailles one-off actuelles (8–9 pt sur badges / chevrons) sont du chrome microscopique, pas des styles de lecture ; ne pas les promouvoir en tokens à moins qu’elles se répètent.

**Nouvelle animation** — réutiliser `quick` / `snappy` / `gentle`. `land` reste réservé à l’atterrissage. Un spring local est un bug de fondation.

**Nouveau composant d’archive** — partir de la grammaire : label catalogue, valeur SF, filet hairline, fond paper, tint ink. Un champ passe par `FormField` / `FieldChrome`, jamais une rangée privée. Si ça a besoin d’une card UIKit, d’un divider système ou d’un accent color, ce n’est probablement pas une surface Kohi.

**Nouveau haptic** — un cas dans `Haptic` avec un nom d’événement, pas un `sensoryFeedback` anonyme dans la vue.
