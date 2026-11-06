# Kohi — Dev brief #10 : grille à deux, fiche à onglets, dégustation en parcours

**Statut** : prompt pour Cursor, version 10.0 · **Date** : 6 novembre 2026 · **Owner** : JBK (jbk studio)
**Source** : retours JBK du 6 novembre sur l'app (build avec le lot 9), quatre captures : la grille, la fiche du Zoma Colombia Geisha, le menu *Cards*, *Add tasting*.
**À lire avant** : `design-system.md` (§7 *Composants de parcours* et la règle d'affordance, §8 *Grille* et *Détail — ordre de lecture*), `kohi-dev-brief-4.md` (§0, les quatre principes), `Grid/GridDensity.swift`, `Grid/GridScreen.swift`, `Design/TabRail.swift`, `Design/StepFlow.swift`, `Design/TastingBlocks.swift`, `Detail/CardDetailView.swift`, `Detail/TastingList.swift` (`TastingsBlock`), `Detail/CardFaceStage.swift`, `Detail/WhereSheet.swift`, `Tastings/TastingComposeSheet.swift`, `Tastings/PlaceSelectorRow.swift`, `Tastings/MenuPickSheet.swift`, `Process/MenuParser.swift`, `Edit/NearbyPlaces.swift`, `Edit/PlaceLocator.swift`, `App/RootView.swift`.

**Avant de commencer** : l'arbre de travail contient encore le lot 9 non commité (`KohiCard`, `CardComposer`, `CardStandard`, `GridScreen`, `TastingComposeSheet`, snapshots…). Le commiter d'abord, tests verts, pour que ce lot parte d'une base propre et que ses diffs restent lisibles.

**10.0 — choix faits dans ce brief, à confirmer par JBK** :

1. La grille s'ouvre **toujours** à deux colonnes. Le pinch reste libre pendant la session ; il n'est pas mémorisé d'un lancement à l'autre.
2. La fiche a **deux** onglets, *Coffee* et *Brews*. *Suggested* reste dans *Coffee* : c'est ce qu'on fait ensuite. Les dégustations en coffee shop liées au café vont en bas de *Brews*, sous *Tasted at*. *Ask* passe sur le rail, à droite, visible dans les deux onglets.
3. **Créer** une dégustation devient un parcours en étapes ; **modifier** une dégustation garde le formulaire d'un seul écran.
4. Un seul bouton de scan pour la carte du café, le menu ou le sachet : l'app trie.
5. Depuis la home, la question « tasse en coffee shop ou sachet » n'est posée que quand le signal est fort, et elle se tait d'elle-même chez toi.

---

## 0. Cadre

Lot court, quatre changements. Mêmes principes que le lot 4 : **un bloc par étape**, **aplatir**, **dicter plutôt que taper**, et la règle d'affordance du design system : une affordance ne disparaît pas sur une condition calculée, elle s'affiche avec sa raison.

| # | Type | Quoi | Fichiers principaux |
|---|---|---|---|
| 1 | Correction | Grille à deux colonnes par défaut | `GridDensity`, `GridScreen` |
| 2 | Amélioration | Fiche café à onglets *Coffee* / *Brews* ; suppression du bouton *Cards* | `CardDetailView`, `TastingsBlock`, `TabRail` |
| 3 | Amélioration | Nouvelle dégustation en parcours : scan de la carte du café, ou saisie | `TastingFlow` (nouveau), `TastingCapture` (nouveau), `TastingComposeSheet` |
| 4 | Amélioration | Scan depuis la home près d'un café : dégustation ou sachet | `ScanIntent` (nouveau), `ScanIntentSheet` (nouveau), `GridScreen`, `RootView` |

Ce que ce lot ne fait pas : rien sur le rendu des cartes (lot 9), le parcours de brew, la sync. Aucun nouvel appel réseau, aucun nouveau modèle IA.

---

## 1. Grille à deux colonnes par défaut

**Constat** : `GridScreen` démarre à `@State private var density: GridDensity = .three`. À trois colonnes sur iPhone, les cartes du lot 9 (étiquette, sticker, relief) sont trop petites pour se lire, et JBK zoome à chaque lancement.

- `GridDensity` : `static let launch: GridDensity = .two`. `GridScreen` : `@State private var density: GridDensity = .launch`.
- Le pinch reste de 1 à 4 colonnes, inchangé (`stepped(by:)`, haptique `densityChange`). Au retour d'une fiche, la densité courante est gardée (c'est déjà le cas : l'état vit dans `GridScreen`).
- **Pas de mémoire** entre lancements (pas de `@AppStorage`) : chaque ouverture repart à deux.
- Deux colonnes lisent le bucket de thumbnail 1024 (voir `prewarm(for:)`), donc le premier affichage décode du 1024 au lieu du 512. Vérifier que le scroll de la première page reste à 60 i/s sur l'archive d'exemple ; sinon, préchauffer les 12 premières tuiles au lancement.
- `design-system.md` §8 *Grille* : « Densité par défaut : **2** ».

---

## 2. La fiche café : deux onglets, plus de bouton *Cards*

### 2.1 Constat

Sur la fiche, tout est empilé dans un seul scroll (`CardDetailView.body`) : notes, roue, `CaptionBlock`, originaux, puis `brewAndAsk` (*Suggested*, **tout le journal de brews** via `TastingsBlock` → `BrewLog`, *Tasted at*, *Ask*), puis `CardProfile`, pages, note, actions. Avec dix brews, les infos du café et les actions (*Edit*, *Symbol*, *Remove from archive*) sont repoussées sous un mur de lignes.

En haut à droite, *CARDS* ouvre un `confirmationDialog` (« Show the scan for this coffee » / « Show the Kohi card ») qui fait exactement ce que fait un tap sur la carte : `CardFaceStage` (« A tap turns it over ») appelle déjà `looks.setOverride` via `onFlip`. C'est un doublon.

### 2.2 Structure

```
COFFEES (retour)
tombstone
objet (CardFaceStage) — un tap le retourne
titre Angusta
─ COFFEE   BREWS 4 ──────────────── ASK ─   ← TabRail .rail, épinglé sous la barre du haut
contenu de l'onglet
```

- Nouveau `Kohi/Detail/CardDetailTab.swift` : `enum CardDetailTab: String, CaseIterable, Identifiable { case coffee, brews }`. Libellés : `Copy.coffee` (« Coffee ») et `Copy.brews`. *Brews* porte le nombre de brews dès qu'il y en a un (« Brews 4 »).
- **Composant** : `TabRail` avec `underline: .rail`, le même que la home (`CatalogueTabs`), padding horizontal 28 comme le reste de la fiche. Pas de nouveau composant.
- **Épinglé** : le contenu passe dans un `LazyVStack(pinnedViews: [.sectionHeaders])` dont le rail est l'en-tête de section, fond `Palette.paper`, avec le filet hairline du rail dessous. Il s'arrête sous la barre du haut (`safeAreaInset`). Tombstone, objet et titre scrollent normalement au-dessus.
- **Changer d'onglet** : `Motion.snappy` (défaut de `TabRail`). Si on a scrollé sous le rail, on revient au rail (`proxy.scrollTo("detail-rail", anchor: .top)`) pour que l'onglet commence à son début. **Pas de swipe horizontal entre onglets** : `SwipeDeleteRow` utilise déjà le swipe horizontal dans le journal.
- **Ask** quitte le bas de page et passe dans le `trailing` du rail, le slot prévu pour ça dans `TabRail` : `CoffeeCupIcon` 14 pt + « ASK » en `Typography.label`, `Palette.primary`, `touchTarget()`, seulement si `flags.isOn(.ask)`. Libellé VoiceOver : « Ask about this coffee ».

### 2.3 Contenu des onglets

| Onglet *Coffee* (par défaut) | Onglet *Brews* |
|---|---|
| Notes | `CardProfile` (flag `cardProfile`, ≥ 2 brews comparables) |
| *On the wheel* | `BrewLog` : tout le journal, swipe *Delete*, *Undo*, *Brew again*, *For next time*, *Compare* |
| `CaptionBlock` | Notes maison d'avant les brews (`homeNotes`, comme aujourd'hui) |
| Originaux CJK repliés | *Tasted at* : les dégustations en coffee shop liées au café (`TastingList`, score agrégé) |
| `BrewRecipes` : *Suggested* et la recette du sachet (ancre `suggested-recipe` gardée) | Sans brew : « No brews yet. » + *Brew this coffee* (§2.4) |
| *Set up your kit* (si le kit est vide) | |
| Pages & documents | |
| *Note to self* | |
| Actions : *Edit* · *Symbol* · *Remove from archive* | |

`TastingsBlock` se découpe en deux vues, `BrewsSection` (journal + notes maison) et `TastedAtSection`, toutes deux dans l'onglet *Brews*, dans cet ordre. `CardProfile` passe dans *Brews* parce qu'il ne parle que des brews.

### 2.4 Comportements

- **Onglet d'ouverture** : `CardDetailView(card:startsOn: CardDetailTab = .coffee)`. `startsAtSuggested == true` force `.coffee` puis scrolle sur *Suggested*, comme aujourd'hui. Une ouverture depuis un brew (journal de la home, Live Activity, widget, intent « Log a brew ») passe `.brews`.
- **Après un brew lancé depuis la fiche** : si `live.brews.count` a augmenté quand `BrewFlowHost` se ferme, l'onglet passe à *Brews* et la nouvelle ligne arrive en tête (`Motion.quick`). Un brew abandonné ne change pas d'onglet.
- **Onglet vide** : *Brews* reste toujours visible (règle d'affordance). Sans brew : « No brews yet. » en `Typography.subtitle` `inkMuted`, puis *Brew this coffee* en `catalogueLabel()`, qui fait ce que fait *Use* sur *Suggested* (`use(suggestion.recipe)`), et sinon ouvre le parcours sans recette.
- **Pas de mémoire** : chaque ouverture de fiche repart sur *Coffee*, hors cas ci-dessus.

### 2.5 Supprimer *Cards*

- `CardDetailView` : retirer le bouton du `safeAreaInset` (il ne reste que `CatalogueBackButton`), `showFaceMenu` et le `confirmationDialog`.
- `Strings.swift` : supprimer `showTheScan` et `showTheKohiCard`. **Garder** `Copy.cards`, utilisé par le réglage global *Cards* (Kohi / Scans) dans `ProfileSheet`.
- Changer la face d'une carte reste le tap sur l'objet, déjà persistant (`looks.setOverride` via `onFlip`) et déjà annoncé à VoiceOver (« Tap to turn the card over »). Rien à ajouter.

`design-system.md` §8 *Détail — ordre de lecture* : remplacer la liste par la structure de §2.2 et le tableau de §2.3.

---

## 3. Nouvelle dégustation : un parcours

### 3.1 Constat

*Add tasting* (`TastingComposeSheet`) est un seul long écran : *Where?*, *Coffee* avec trois actions en ligne (*From Coffee Collection*, *Scan bag*, *Scan menu*), *Details* replié, *Your tasting* (note, radar sept axes, saveurs), *Note to self*. En coffee shop, debout au comptoir, on a besoin d'une chose à la fois. Et la petite carte que beaucoup de cafés posent à côté de la tasse (producteur, origine, process, notes) n'a pas de bouton à elle : il faut deviner que *Scan bag* la lit.

### 3.2 Le parcours

Nouveau `Kohi/Tastings/TastingFlow.swift` : une sheet plein écran, une `StepFlow` par étape, même chrome que le brew (segments, question 22 pt, *Skip*, *Next* 52 pt). Le modèle reste `TastingDraft`, sans changer ses règles (`missing`, `canSave`, `fill`, `apply`, `link`, `choose`, `autofill`).

| # | Question | Bloc | Requis | Pied |
|---|---|---|---|---|
| 1 | *Where are you?* | Le lieu le plus proche déjà choisi (même logique que `PlaceSelectorRow` : `autofill`, jamais par-dessus un choix), avec *Change* ; *Other place* → `WhereSheet`. Localisation refusée : *Other place* ouvre directement la recherche. | Oui | *Next* |
| 2 | *What's in the cup?* | Trois rangées catalogue, une par ligne : **Scan the card** (sous-titre « Card, menu or bag »), **From my Coffee Collection**, **Type it in**. Un tap avance. Collection vide : la rangée reste, grisée, avec « Your collection is empty ». | Un choix | — |
| 3 | *Which coffee?* | Nom (requis, `DictationField`, suggestions `CoffeeSuggestions` comme aujourd'hui), torréfacteur, pays, process, variété, *On the card* (notes). Valeurs lues déjà remplies ; valeurs incertaines en chips *To confirm* ; offre de lien vers la collection (`CardMatch`). Pendant la lecture : `ShimmerBar` « Reading the card… ». | Nom | *Next* · *Rescan* (si on vient du scan) |
| 4 | *How was it made?* | Chips de méthode (`TastingMethod`), prix (devise locale), photos. Pré-remplis si la carte ou le menu les donnent. | Non | *Skip* · *Next* · *Save now* |
| 5 | *How was it?* | `RatingPicker`, puis `FlavorsBlock` (les saveurs déclarées par la carte sont proposées, pas cochées). | Non | *Skip* · *Next* · *Save now* |
| 6 | *Anything to remember?* | `TasteBlock` replié comme aujourd'hui (« Taste ⌄ », tasse précédente superposée), puis *Note to self* avec `DictationField`. | Non | ***Save*** |

- **Six étapes, cinq quand le lieu arrive déjà choisi** (scan depuis la home, §4) : l'étape 1 saute et la progression compte cinq segments.
- **Save now** (bouton secondaire de `StepFlow`) apparaît dès l'étape 4 si `draft.canSave`. Les étapes 4 à 6 sont des bonus, jamais un passage obligé. *Save* enregistre comme aujourd'hui (`tastings.add`, `rememberServes`, haptique `.saved`), ferme, et ouvre l'onglet *Tastings* de la home avec la nouvelle dégustation en tête.
- **Retour** : la flèche revient d'une étape sans rien perdre.
- **Fermer (×)** : si le brouillon contient autre chose que le lieu automatique → `confirmationDialog` « Discard this tasting? » (*Discard* / *Keep going*). Sinon, la sheet se ferme directement.
- **Type it in** : l'étape 3 s'ouvre vide, focus sur le nom, clavier ou dictée.
- **From my Coffee Collection** : le picker existant (`pickingFromCollection`), puis `draft.link(card)` ; l'étape 3 s'ouvre remplie, avec « In Coffee Collection · … » et *Unlink*.

**Modifier une dégustation** ne passe pas par le parcours : `TastingDetailView` → `TastingComposeSheet(editing:)`. Le formulaire d'un écran reste, c'est le bon outil pour corriger un champ. Pour que les deux restent identiques, extraire de `TastingComposeSheet` les sous-vues `TastingCoffeeFields` (étape 3) et `TastingMadeFields` (étape 4), utilisées par le parcours et par le formulaire.

**Points d'entrée** vers `TastingFlow()` : le `+` de l'onglet *Tastings*, *Add your first tasting* (`TastingsScreen`, `EmptyStateView`), et le scan depuis la home (§4). `GridScreen.composesTasting` présente `TastingFlow` à la place de `TastingComposeSheet()`.

### 3.3 Un seul scan : l'app trie

Nouveau `Kohi/Tastings/TastingCapture.swift`, `nonisolated`, pur et testable :

```swift
nonisolated enum TastingCapture {
    enum Reading: Equatable {
        /// Une seule fiche : carte du café, sachet, ou ardoise avec un seul café.
        case fields(ParsedFields, extra: [MenuField])
        /// Plusieurs cafés : on demande lequel est dans la tasse.
        case menu([MenuCandidate])
        /// Rien de lisible.
        case nothing
    }

    static func sort(_ lines: [String], roasters: [String]) -> Reading
}
```

1. `MenuParser.parse(lines, roasters:)` trouve **au moins deux** candidats → `.menu` → `MenuPickSheet` (« Which one is in your cup? »), puis `apply` comme aujourd'hui. Le second avis IA (`FieldExtract.menu`) reste branché tel quel, sous ses flags.
2. Sinon → `FieldParser.parse(lines)` → `.fields`. Il lit déjà les étiquettes des sachets (« Process: », « Altitude: », « Farmer: »), et une carte de café a la même forme. Si `MenuParser` a trouvé **un** candidat, ses champs `.read` de méthode et de prix passent dans `extra` : une ardoise « Ethiopia Chelchele — V60 — 5,50 € » remplit aussi l'étape 4.
3. Ni nom, ni torréfacteur, ni origine → `.nothing` : l'étape 3 s'ouvre vide avec une ligne `inkMuted` « Couldn't read this one. Type it, or rescan. »
4. **Jamais d'écrasement** : `draft.fill(from:)` ne remplit que les champs vides (règle actuelle), et `extra` suit la même règle.
5. `CardMatch.find` après lecture, comme aujourd'hui → offre de lien.

`TastingScanKind` (`.bag`, `.menu`) disparaît. Le formulaire d'édition remplace ses deux actions *Scan bag* et *Scan menu* par une seule, *Scan the card*, branchée sur `TastingCapture`. `Copy.toConfirm` (« Read on the menu, to confirm ») devient « Read, to confirm » : la lecture ne vient plus forcément d'un menu.

---

## 4. Scanner depuis la home près d'un café

### 4.1 L'idée

Le bouton de scan de la home sert aujourd'hui à un seul geste : un sachet → une carte dans la collection. Dans un coffee shop, le même geste veut souvent dire autre chose : une tasse → une dégustation. L'app le devine quand le signal est fort et pose **une** question. Sinon, rien ne change : la caméra s'ouvre tout de suite.

### 4.2 Quand demander (`Kohi/Process/ScanIntent.swift`, pur)

```swift
nonisolated struct Fix: Equatable, Sendable {
    var coordinate: CLLocationCoordinate2D
    var horizontalAccuracy: CLLocationDistance
    var at: Date
}

nonisolated enum ScanIntent: Equatable {
    case bag
    case ask(PlaceSuggestion)

    static func decide(
        fix: Fix?,
        yours: [PlaceSuggestion],
        seeds: [PlaceSuggestion],
        maps: [Place],
        spots: [ScanSpot],
        now: Date
    ) -> ScanIntent
}
```

- **Le fix est déjà là, ou on ne demande pas.** `GridScreen` prend un fix unique quand l'onglet *Coffee Collection* apparaît (et au retour au premier plan), **seulement si** `PlaceLocator.isAuthorized` est déjà vrai : jamais de demande d'autorisation depuis la home. Puis `NearbyPlaces.searchCafes()` (une fois par fix, comme aujourd'hui). `PlaceLocator` expose en plus `horizontalAccuracy` et l'heure du fix. Un fix de plus de 5 minutes est périmé et refait à la prochaine apparition. Au tap, on n'attend jamais le GPS.
- **Précision** : `horizontalAccuracy ≤ 65 m`, sinon `.bag`.
- **Candidat**, par priorité : un lieu de tes dégustations à ≤ 75 m, un lieu de la base (`seed-paris`) à ≤ 75 m, un café Apple Maps à ≤ 40 m. Le plus prioritaire gagne, puis le plus proche. Aucun → `.bag`.
- **Chez toi, elle se tait.** `ScanSpot` garde, arrondi à ~100 m, ce que tu as répondu à un endroit. Là où tu as répondu *A bag* deux fois de suite sans jamais *A cup*, c'est `.bag` sans question. Une réponse *A cup* remet le compteur à zéro. On n'apprend jamais « maison » d'une seule réponse : acheter un sachet au comptoir ne doit pas faire taire ce café.
- `ScanSpots` : `UserDefaults` `scan.spots`, 20 endroits au plus (les plus anciens sortent). **Local, jamais synchronisé**, effacé par le reset de debug.

Les rayons sont serrés exprès : à Paris, il y a un café Apple Maps à moins de 100 m de presque partout. Les lieux de tes dégustations et de la base sont des coffee shops ; un POI Maps peut être un bistrot.

### 4.3 La question (`Kohi/Grid/ScanIntentSheet.swift`)

Sheet papier courte (`presentationDetents([.height(…)])`), une question, deux rangées catalogue de 52 pt :

- *What are you scanning?*
- **A cup at Galata Bakery & Coffee** — « Add a tasting »
- **A bag for my collection** — « Add to Coffee Collection »

Les libellés parlent de **l'objet**, pas du lieu : on peut être dans un café et scanner un sachet qu'on emporte. Haptique `selection` au choix. Glisser la sheet vers le bas annule : rien ne s'ouvre.

### 4.4 Les deux suites

- **A bag** → exactement le flux actuel (`ScanScreen` → `ingest` → `CardEditSheet`). La réponse est notée dans `ScanSpots`.
- **A cup** → la même `ScanScreen`. Au scan, `TastingFlow(place: suggestion, scan: result)` s'ouvre **à l'étape 3**, lieu choisi, lecture en cours (`TastingCapture`). La réponse est notée dans `ScanSpots`. Annuler la caméra ramène à la home sans rien créer. À l'enregistrement, la home passe sur l'onglet *Tastings*.
- La caméra ne change pas : même cadrage, même revue. La carte d'un café se scanne comme un sachet.

### 4.5 Debug

`DebugHooks` : `-kohi.fakeFix <lat>,<lon>,<accuracy>` remplace le fix (simulateur, snapshots). Ajouter un exemple dans `docs/guide-de-test.md`, sur un lieu de la base parisienne.

---

## 5. Fichiers

### 5.1 Nouveaux

| Fichier | Rôle |
|---|---|
| `Kohi/Detail/CardDetailTab.swift` | `CardDetailTab` (§2.2) |
| `Kohi/Detail/BrewsSection.swift` | Journal, notes maison et *Tasted at*, sortis de `TastingsBlock` |
| `Kohi/Tastings/TastingFlow.swift` | Le parcours (§3.2) |
| `Kohi/Tastings/TastingFields.swift` | `TastingCoffeeFields`, `TastingMadeFields`, partagés avec le formulaire d'édition |
| `Kohi/Tastings/TastingCapture.swift` | Tri du scan (§3.3), pur |
| `Kohi/Process/ScanIntent.swift` | `Fix`, `ScanSpot`, décision `.bag` / `.ask` (§4.2), pur |
| `Kohi/Grid/ScanIntentSheet.swift` | La question (§4.3) |
| `KohiTests/DevBrief10Tests.swift`, `KohiTests/DevBrief10SnapshotTests.swift` | §7 |

### 5.2 Modifiés

- `GridDensity` (`launch`) ; `GridScreen` (densité, fix au premier plan, `ScanIntent` au tap, `TastingFlow` à la place de `TastingComposeSheet()`, onglet *Tastings* après une dégustation).
- `RootView` : `onScan` passe par `ScanIntent` ; la branche *A cup* présente `TastingFlow` après `ScanScreen`, avec la même garde que `pendingScan` contre la course entre la fermeture du cover et la sheet.
- `CardDetailView` (§2) ; `TastingList.swift` (`TastingsBlock` découpé).
- `TastingComposeSheet` : sert à l'édition, sous-vues extraites, un seul scan.
- `PlaceLocator` : `horizontalAccuracy` et heure du fix.
- `Strings.swift` : `coffee`, `noBrewsYet`, `brewThisCoffee`, `scanTheCard`, `typeItIn`, `discardTasting`, questions des étapes et de la sheet ; `toConfirm` reformulé ; `showTheScan` et `showTheKohiCard` supprimés.
- `DebugHooks` (`fakeFix`).

---

## 6. Docs

- `design-system.md` : §8 *Grille* (densité par défaut 2) ; §8 *Détail — ordre de lecture* (rail *Coffee* / *Brews*, épinglé, *Ask* en trailing) ; §7 *Composants de parcours* : ajouter `TastingFlow` (« six ticks, cinq quand le lieu est connu ») et `ScanIntentSheet`.
- `fonctionnalites.md` : la fiche, les dégustations, le scan depuis la home.

---

## 7. Tests et critères d'acceptation

- **Grille** : `GridDensity.launch == .two` ; `stepped(by:)` inchangé ; lancement à froid sur l'archive d'exemple → deux colonnes.
- **Fiche** :
  - ouverture → *Coffee* ; `startsAtSuggested` → *Coffee* et scroll sur *Suggested* ; `startsOn: .brews` → *Brews* ;
  - une fonction pure `CardDetailSections.ordered(for:card:flags:)` donne l'ordre des blocs : aucun bloc de brew dans *Coffee*, aucune action *Edit* / *Symbol* / *Remove* dans *Brews* ;
  - carte sans brew → *Brews* visible, « No brews yet. » et *Brew this coffee* ;
  - brew enregistré depuis la fiche → *Brews* sélectionné à la fermeture ; brew abandonné → onglet inchangé ;
  - la barre du haut ne contient plus que le retour ; un tap sur l'objet change la face, et la face est gardée après réouverture ;
  - snapshots : *Coffee* ; *Brews* avec six brews et une dégustation en coffee shop ; *Brews* vide ; rail épinglé après scroll.
- **Capture** (`TastingCapture.sort`, fixtures texte dans `KohiTests/Fixtures/tasting/`) :
  - carte de café d'une origine → `.fields` avec nom, pays, process, notes. La carte Kenya Tekangu de l'archive d'exemple (déjà dans `FieldParserTests`) a exactement la forme d'une carte de café : la réutiliser ;
  - menu de trois cafés → `.menu` à trois candidats ;
  - ardoise d'un seul café avec méthode et prix → `.fields`, `extra` contient la méthode et le prix ;
  - texte vide ou illisible → `.nothing` ;
  - un nom déjà tapé n'est jamais remplacé par la lecture ;
  - les tests existants de `TastingCaptureTests` (menu, torréfacteur incertain, prix, lien) restent verts.
- **Parcours** :
  - six étapes, cinq avec un lieu fourni ; *Save now* absent tant que `canSave` est faux, présent dès l'étape 4 sinon ;
  - × avec un nom saisi → dialogue *Discard* ; × avec seulement le lieu automatique → fermeture sans dialogue ;
  - *Save* → la dégustation est dans `TastingStore` avec lieu, café, méthode et note ; la home est sur *Tastings* ;
  - modifier une dégustation ouvre toujours `TastingComposeSheet(editing:)` (`editingKeepsIdentityAndCreation` reste vert) ;
  - snapshots : les six étapes ; l'étape 3 pendant la lecture (shimmer) puis après, avec une chip *To confirm*.
- **ScanIntent** (fix et lieux injectés) :
  - pas de fix → `.bag` ; précision 120 m → `.bag` ; fix de 6 minutes → `.bag` ;
  - lieu de tes dégustations à 50 m → `.ask(lui)` ; lieu de la base à 70 m → `.ask` ; café Maps à 60 m → `.bag` ; café Maps à 30 m → `.ask` ;
  - lieu à toi à 70 m et café Maps à 20 m → `.ask(lieu à toi)` ;
  - deux *A bag* de suite au même endroit → la troisième fois, `.bag` sans question ; un *A cup* ensuite → la question revient ;
  - autorisation non accordée → aucun `start()` du locator depuis la home (faux `PlaceLocator`).
- **Réseau** : `cardRenderingDoesNotCallTheNetwork` reste vert ; la recherche Maps ne part que si la localisation est déjà autorisée.

---

## 8. Ordre d'exécution

1. Commiter le lot 9 en cours.
2. Grille à deux colonnes (§1) : une ligne et un test.
3. Fiche à onglets et suppression de *Cards* (§2). Vérifier sur la fiche du Zoma Colombia Geisha et sur une carte à dix brews.
4. `TastingCapture` (pur) + tests, et le scan unique dans le formulaire actuel. Rien d'autre ne bouge encore.
5. `TastingFlow`, sous-vues partagées, points d'entrée (§3).
6. `ScanIntent`, `ScanIntentSheet`, câblage de la home (§4). Tester sur place : dans un coffee shop de la base, puis chez soi deux fois de suite.
7. Docs (§6).

## 9. Plus tard

- Un sachet scanné dans un café : proposer ce café comme *Bought at* sur la nouvelle carte (suggestion, jamais imposée).
- Deviner l'objet depuis l'image (sachet ou carte de café) pour se passer de la question.
- Intent et widget « Log a tasting », sur le modèle de « Log a brew ».
- Importer la photo d'une carte depuis la photothèque à l'étape 2 (`PhotoImport` existe).
