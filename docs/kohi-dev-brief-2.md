# Kohi — Dev brief #2 : données propres, profil sensoriel, roue aromatique, comparaison

**Statut** : brief pour Cursor, version 2.1 · **Date** : 13 septembre 2026 · **Owner** : JBK (jbk studio)
**À lire avant de coder** : `design-system.md` (contrat UI, valeurs qui font foi dans `Palette` / `Typography` / `Motion` / `Haptic`), `fonctionnalites.md` du 13 septembre (état du binaire), `kohi-prd-v1.md` (0.3), `kohi-manifeste.md`.
**Fichier livré avec ce brief** : `flavor-wheel.json` (taxonomie SCA 2016, EN / FR, synonymes, classes d'origine) — à déposer dans `Kohi/Resources/Reference/`.

**2.1 (même jour)** : inventaire écran par écran d'iBrewCoffee (captures fournies) avec la correspondance de champs iBrew → Kohi (§2.1–2.2, réutilisable pour l'annexe I du PRD) ; enseignements de la démo « Profil de café » (§2.3) ; alignement sur le manifeste *wip* du 13 septembre — sept convictions (§0.1) ; ajouts qui en découlent dans WP1, WP3, WP4, WP5 et dans les questions ouvertes.

---

## 0. Pourquoi ce lot

Le Must 1.0 est dans le binaire. Ce lot ne rajoute pas de surface : il rend les données du brew **propres et complètes**, remplace le profil de dégustation par un **profil à 7 axes sur 10**, ajoute la **roue aromatique de référence** (SCA) à côté de la perception personnelle, et ouvre la **comparaison entre extractions**. C'est la base pour que les Insights, le diagnostic et, demain, la communauté aient quelque chose de solide à lire.

En une phrase : **faire iBrewCoffee, en mieux** — les mêmes fondamentaux (produit, brew, équipement, profil, export), avec un objet au lieu d'une fiche, des données structurées au lieu de texte libre, et une référence scientifique à côté du goût personnel.

Ce que ce lot ne touche pas : la grille, le scan, l'OCR, les posters, la sync (sauf colonnes ajoutées), Ask, les agents. Pas de nouveau token de couleur, pas de nouveau spring, pas de nouveau haptic hors ceux listés ici.

### 0.1 Ce que le manifeste impose à ce lot

Le manifeste *wip* du 13 septembre (sept convictions) fait foi. Ce qu'il change concrètement ici :

| Conviction | Conséquence dans ce lot |
| --- | --- |
| Un objet, pas une donnée | Aucune icône de méthode, aucune illustration de brewer (iBrew et la démo en ont) : la méthode est un mot, l'appareil vit dans Setup |
| Du papier, pas un feed | Pas de tri / regroupement de la grille par torréfacteur comme l'écran *Home* d'iBrew ; le regroupement viendra par la vue torréfacteur (1.1) et la recherche |
| Un seul geste d'ajout | « Brew again » est une action dans une carte, pas un bouton flottant |
| Une variable à la fois | La phrase de comparaison (§7.3) ne nomme qu'une cause principale ; quand plusieurs paramètres ont changé, elle le dit |
| Honnête sur ce qu'on sait | Le µm proxy porte « ≈ » ; la phrase de comparaison porte son niveau de preuve ; `origin` n'alimente le diagnostic qu'une fois vérifié |
| L'intelligence sert, elle ne décide pas | Ce lot est déterministe ; la dictée ne remplit que le vide et se surligne |
| Le vocabulaire du café | Labels de la roue et des axes tels que le café les nomme (Aftertaste, Clarity, Bloom, Drawdown) — pas « Score », « Niveau » |

« Pas de likes » vaut aussi pour un cœur *favori* personnel (iBrew, démo) : le rating et le *best brew* suffisent.

---

## 1. Definition of done

Le lot est terminé quand, sur un café de l'archive :

1. Un brew peut être saisi **sans texte libre pour la mouture** (broyeur + valeur), avec ses **étapes et masses**, son agitation, son eau, son kit — et l'app sait dire s'il est *comparable*.
2. Le profil sensoriel est **7 axes, 0–10**, dictable, dessiné en radar encre ; les anciens brews sont migrés sans perte.
3. Les saveurs viennent de la **roue SCA 2016** (bundle), avec recherche, quick set, texte libre toléré ; les notes de la carte sont **rapprochées** de la roue quand c'est possible.
4. Deux brews comparables s'ouvrent **côte à côte** : radar superposé, paramètres et deltas, saveurs communes / propres, et une phrase « ce qui a changé → ce qui a bougé ».
5. La fiche d'une carte montre un **Profile** : radar médian de ses brews, saveurs trouvées vs déclarées.
6. « Brew again » existe sur n'importe quel brew ; la recherche filtre par méthode et par saveur.
7. Aucun composant nouveau ne sort de la grammaire (label catalogue, valeur SF, filet hairline, papier, encre). Aucun test existant ne casse ; les nouveaux tests listés en §9 passent.

---

## 2. Analyse iBrewCoffee — ce qu'on reprend, ce qu'on fait mieux, ce qu'on laisse

Source : site et fiches store d'iBrewCoffee (Stanislav Nováček). Leur modèle : *Product* (sachet) → *Brews* → export. Bases de référence : ~3 000 torréfacteries, ~2 000 régions, ~300 variétés, ~300 profils de saveur, ~60 méthodes avec icônes + méthodes custom. Brew : méthode, équipement, réglage de mouture, dose, eau, température, temps d'extraction, TDS, ratios calculés, profil (aroma, sweetness, acidity, bitterness, body), notes, photos, rating. Actions : New Brew, Create Similar, Export PDF (A4 / A5), export CSV / XLSX, image carrée à partager, recherche par torréfacterie / saveur / méthode / pays / région / variété. Cloud en Premium. Reproches utilisateurs : interface chargée, abonnement, verrouillage des données.

| Fondamental iBrew | Kohi aujourd'hui | Ce lot | Mieux, comment |
| --- | --- | --- | --- |
| Product : roastery (base), origine, variété, process, roast level, prix, cupping score, lot, site, photos | Livré (carte + On the bag + Roaster + pièces) | — | L'objet scanné remplace la fiche ; OCR remplit |
| Decaf method, farm, wash station, harvest | Decaf toggle, Producer, Harvest | **WP5** : `decafMethod` (chips), `farm` optionnel | On garde le vocabulaire café, pas une fiche à 30 champs |
| ~300 profils de saveur (liste plate) | ~40 chips SCA réduites | **WP3** : roue SCA 2016 complète, hiérarchique, EN / FR, synonymes, rapprochement des notes de la carte | Une taxonomie de référence, pas une liste ; le déclaré vs le perçu |
| Profil 5 axes (aroma, sweetness, acidity, bitterness, body) | 6 axes 1–5 | **WP2** : 7 axes 0–10 (+ Aftertaste, + Clarity) | Échelle qui discrimine ; radar en encre ; brew précédent superposé ; dictable |
| Grinder settings (texte) | Texte libre | **WP1** : broyeur + valeur numérique + repli texte | Conversion « In your terms », calibration, Insights par broyeur deviennent fiables |
| Dose, eau, temp, temps, TDS, ratios calculés | Livré (+ EY, flux) | **WP1** : étapes avec masses, agitation, filtre hérité du brewer | Recette complète, pas un résumé |
| Create Similar | Last brew comme graine | **WP1** : *Brew again* sur tout brew | Une graine choisie, pas seulement la dernière |
| Compare (dans la liste) | Compare replié vs recette / carte / meilleur | **WP4** : deux brews côte à côte, radar superposé, deltas, phrase | La comparaison lit paramètres *et* perception |
| 60 méthodes + custom | 7 méthodes | **WP5** : familles + brewer du Setup ; +Siphon, +Batch (Could) | Méthode = famille physique ; l'appareil vit dans Setup |
| Smart search (roastery, flavor, method, country…) | Nom, torréfacteur, pays, région, variété, process, notes | **WP5** : + méthode, + saveur (id roue), + lieu | Recherche sur ids, pas sur texte |
| Export PDF A4 / A5, image carrée | Aucun | **Hors lot** (1.1 : export JSON / CSV du PRD ; « Print a card » à étudier) | Le papier est notre matière : une carte imprimable est cohérente, un post social non |
| Cloud premium, abonnement | Supabase optionnel, gratuit | — | Local-first, ce qui est à toi reste chez toi |
| Icônes par méthode, fiche chargée | Grammaire catalogue | — | On ne reprend pas |

### 2.1 Inventaire écran par écran (captures)

| Écran iBrew | Ce qu'il montre | Ce qu'on en retient |
| --- | --- | --- |
| **Home › Products** | Produits regroupés par torréfacterie + drapeau du pays ; par produit : pays / région, variétés, process, *flavor profile*, roast level, prix au gramme (€0.08/g), cupping score, **note moyenne** (8.4/10 ★), cœur favori, lien, photo | La note moyenne par café est utile → *Profile* (WP4). Le regroupement par torréfacteur → vue torréfacteur (1.1), pas la grille. Pas de cœur |
| **Home › Brews** | Par brew : icône + méthode + note (9/10 ★) ; produit, torréfacterie, pays, process ; ligne « process » avec icônes : dose, eau, température, temps, ratio (1:14.29), « Filter + 4 » (nombre d'équipements) ; pour l'espresso : dose, temp, temps, boisson, 1:2, TDS 10.25 %, EY 20.5 %, mouture 0.5, note en clair, date | Une rangée de brew doit porter la mouture et, s'ils existent, TDS / EY → `BrewList` (WP1 §4.2). Ratio affiché avec une décimale quand il n'est pas rond |
| **Brew** (détail) | Method (icône) ; Equipment (Mahlkönig) ; Grind setting (0.5, texte) ; Process : coffee amount, water amount, temperature, brew weight, TDS, extraction time ; ratios calculés coffee/brew et coffee/water | Deux sorties distinctes : **eau versée** et **boisson obtenue** ; Kohi n'a qu'un `output`. Pour l'espresso, `waterIn` optionnel (WP1, Could) |
| **Product › Roastery and Product** | Roastery (nom, pays) ; Product : flavor profile, roast level, roast date, weight (225 g), price (£8.50 · £0.038/g · £37.778/kg), cupping score, lot #, name, **product URL**, product photos, more info, delete | `productURL` manque sur la carte Kohi (le QR le lit mais ne le garde pas) → WP5 |
| **Product › Coffee and Source** | Coffee : country (drapeau), region / area, altitude (plage 1,150–1,250 m), varietals, processings, harvest date (March 2021) ; Source : **farm, wash station, producer** | `farm` (Could), `washStation` (Could) ; altitude en plage déjà possible en texte |
| **Product › Methods and Ratings** | Notes par méthode pour ce produit | → *Profile* : « V60 4/5 · Espresso 3/5 » (WP4 §7.4) |
| **Choose a method** | ~60 méthodes avec icônes (French Press, AeroPress, AeroPress Inverted, Delter, V60, Clever Dripper, LilyDrip, Immersion Switch, Origami, Koar, Kalita, Kalita Wave, Melitta, Daiso…) + custom | Chez Kohi, ce sont des **brewers** de Setup, pas des méthodes ; on n'ajoute que les familles physiques manquantes (WP5) |

### 2.2 Correspondance de champs iBrew → Kohi

Sert deux fois : à mesurer la parité maintenant, et comme base de l'**annexe I** du PRD (import v2). Statut : *ok* = existe ; *lot 2* = ajouté par ce brief ; *hors lot* ; *non* = volontairement absent.

| iBrew | Kohi | Statut |
| --- | --- | --- |
| Product › Name | `Card.name` | ok |
| Roastery name, country | `Roaster.name`, `Roaster.country` | ok |
| Flavor profile (liste plate) | `Card.tastingNotes` + `declaredFlavors` (roue) | lot 2 |
| Roast level, Roast date, Weight, Price (+ /g, /kg), Cupping score, Lot # | On the bag | ok |
| Product URL | `Card.productURL` | lot 2 (WP5) |
| Product photos | Attachments (`bag`, `page`) | ok |
| More info | `Card.note` | ok |
| Country, Region / area, Altitude, Varietals, Processings, Harvest date | champs de la carte | ok |
| Farm, Wash station, Producer | `producer` ok ; `farm`, `washStation` | lot 2 (Could) |
| Decaf method | `decafMethod` | lot 2 (WP5) |
| Favorite ♥ | — | non |
| Avg. rating | *Profile* (moyenne + médiane) | lot 2 (WP4) |
| Brew › Method (60 + custom) | `method` (familles) + `brewer` (Setup) | ok / WP5 |
| Equipment (liste) | `equipmentIds` (kit) | ok |
| Grind setting (texte) | `GrindSetting` (broyeur + valeur + raw) | lot 2 (WP1) |
| Coffee amount, Water amount, Brew weight | `dose`, `output` ; `waterIn` optionnel (espresso) | ok / lot 2 (Could) |
| Temperature, Extraction time, TDS | ok ; EY calculé | ok |
| Coffee/brew ratio, Coffee/water ratio | `ratio` (une décimale si non rond) | ok |
| Profil : aroma, sweetness, acidity, bitterness, body (/5 puis /10) | `TasteProfile` 7 axes /10 (+ aftertaste, clarity) | lot 2 (WP2) |
| Rating /10 ★ | `rating` 1–5 dots | ok (import : /2 arrondi, original en note) |
| Notes, Date, Photos de brew | ok / ok / attachments | ok |
| Export PDF / CSV / XLSX, image carrée | export JSON / CSV en 1.1 ; « Print a card » à instruire | hors lot |
| Smart search | recherche + filtres méthode / saveur / lieu | lot 2 (WP5) |
| Sort control | — | Could (dans la recherche seulement) |

### 2.3 Démo « Profil de café » — ce qu'on en retient

La démo (prototype mobile, écran par écran) parcourt : notes de mouture → étapes d'extraction (*Verser, Verser en cercles, Pré-infusion, Attendre, Remuer, Faire tourner, Personnalisé*) → récapitulatif « Ce contenu est-il correct ? » (Hario V60 illustré, mouture *Gros*, dose 12 g, boisson 200 ml) → sélecteur de saveurs en **treemap coloré** (familles SCA en français : *Sucré brun · Noisette · Amande · Chocolat · Mélasse · Sirop d'érable · Miel · Fruité · Baie · Fruits séchés · Autres fruits · Vert / végétal · Foin · Herbe · Piquant · Poivre · Épices brunes…*) → évaluations à **étoiles** (Favori, Arrière-goût, Complexité, Acidité, Corps, Amertume, Douceur) → note libre → récapitulatif avec un **radar triangulaire** (Amertume / Acidité / Corps) → listes *Grains de café vert* / *Grains de café torréfiés*.

| Vu dans la démo | Décision Kohi |
| --- | --- |
| Un écran par question, Précédent / Suivant | Non : c'est la fatigue de saisie que le PRD combat. Une feuille, la dictée, les défauts |
| Étapes nommées, dont *Verser en cercles*, *Attendre*, *Personnalisé* | Oui : `StepAction` gagne `wait` et `custom` ; « en cercles » est une note d'étape, pas une action (WP1 §4.1) |
| Récapitulatif « est-ce correct ? » | Non comme écran ; oui comme mécanisme : le surlignage 1,1 s de ce qui a été deviné joue ce rôle |
| Treemap de saveurs, en couleur, en français | La taxonomie et les libellés FR confirment `flavor-wheel.json`. Le treemap est une **variante de layout** possible pour la vue *All* du picker, en hairline (§6.4) — à trancher. Pas de couleur |
| Étoiles par attribut, *Complexité*, *Favori* | Rails 0–10 plutôt que 5 étoiles (§5.2). *Complexité* : candidat à un 8ᵉ axe, question ouverte §12. Pas de favori |
| Radar triangulaire | Non : les trois axes du diagnostic (−/·/+) restent des corrections, le radar reste à 7 axes |
| Illustration du brewer | Non (design system §10 : pas d'illustration custom) |
| Grains verts / torréfiés | Hors périmètre définitif (PRD : pas de torréfaction maison) |

---

## 3. Décisions prises pour ce lot

1. **Profil sensoriel** : 7 axes — `acidity · bitterness · sweetness · aroma · aftertaste · body · clarity` — entiers **0–10**, `nil` = non noté. Ordre horaire du radar à partir de midi : Acidity, Bitterness, Sweetness, Aroma, Aftertaste, Body, Clarity (celui du prototype partagé).
2. **Taxonomie aromatique** : la roue **SCA 2016** (WCR Sensory Lexicon) est la référence, pas le fichier `docs/coffeechart.json` du repo — celui-ci est la roue **SCAA 1995** (Lingle : Enzymatic / Sugar Browning / Dry Distillation, plus Tastes et Faults), historique mais remplacée. On en garde une seule idée : la **classe d'origine** d'un arôme (enzymatique, brunissement des sucres, distillation sèche, défaut), utile au diagnostic. Elle est portée par `flavor-wheel.json` (`origin`), marquée *à vérifier*.
3. **Pas de couleur dans l'app pour la roue.** Le JSON porte des couleurs approximatives pour un export ou une impression futurs ; à l'écran, la roue et les chips restent encre / hairline / papier (§3 du design system : « ne pas introduire d'accent »).
4. **Un brew reste une feuille** (édition = lecture), comme aujourd'hui. La comparaison est une feuille à part.
5. **Rien d'obligatoire** dans le brew sheet. La complétude est *calculée* (`isComparable`), montrée en `tag`, jamais bloquante.
6. **Dictée** : la grammaire locale (`SpokenBrewParser`) apprend les 7 axes et les étapes ; `field-extract` reste le repli.
7. **Migration** sans perte : les six anciens axes 1–5 deviennent sept axes 0–10 (`v × 2`), `clarity = nil` ; les anciennes valeurs restent en `legacyTaste` jusqu'à la prochaine version majeure.

---

## 4. WP1 — Données propres : le détail d'une recette

### 4.1 Modèle

```swift
struct GrindSetting: Codable, Equatable {
    var grinderId: UUID?        // Equipment.kind == .grinder
    var value: Double?          // clics, numéro, position — l'unité vient du broyeur (adjustmentType)
    var raw: String?            // repli texte libre ("22 clicks", "2.4 tours", "fine")
    var micronsProxy: Double?   // calculé : calibration perso > pas fabricant > nil ; toujours affiché "≈"
}

enum Agitation: String, Codable, CaseIterable { case none, swirl, stir, wdt, pulse, other }

struct BrewStep: Codable, Identifiable {        // existe — compléter
    var id: UUID
    var action: StepAction                       // bloom · pour · stir · swirl · press · steep · release · drawdown · wait · custom
    var targetTime: TimeInterval?
    var targetMass: Double?                      // cible (recette)
    var actualTime: TimeInterval?                // enregistré par le timer guidé
    var actualMass: Double?                      // saisi / dicté / confirmé
    var note: String?                            // ex. « en cercles », « au centre » — le style de versement est une note, pas une action
}

extension Brew {
    var grind: GrindSetting                      // remplace `grind: String`
    var waterIn: Double?                         // espresso : eau versée, distincte de `output` (boisson) — Could
    var agitation: Agitation?
    var filterId: UUID?                          // hérité du brewer par défaut, modifiable
    var steps: [BrewStep]                        // existe
    var isComparable: Bool {                     // calculé, pas stocké
        method != nil && dose != nil && output != nil && time != nil
        && (grind.value != nil || grind.raw?.isEmpty == false) && rating != nil
    }
    var completeness: Completeness               // .complete / .missing([Field])
}
```

`captureSource` reste par brew (décision tenue). `flowGs` reste calculé.

### 4.2 UI (brew sheet, grammaire inchangée)

- **Grind** : la rangée devient `[label 74] [chip broyeur] [valeur numérique en Typography.value] [unité en tag]`. Sans broyeur par défaut : champ texte comme aujourd'hui, et `raw` est rempli. Un tap sur le chip cycle les broyeurs du Setup. Si `value` est saisi et qu'une calibration existe, « ≈ 700 µm » en `tag` `inkMuted` à droite.
- **Pours** (nouveau groupe replié, sous *Parameters*, seulement si la recette a des étapes ou si l'utilisateur ajoute une étape) : rangées `t · action · mass` en `Typography.tag`, filet hairline entre rangées ; ajouter une étape = `plus` 10 pt + « Add a step » en `catalogueLabel`. Pendant le timer guidé, la masse réelle d'une étape est **confirmée** d'un tap sur la cible (haptic `tap`) ou corrigée en tapant la valeur ; « Next » enregistre le temps réel (inchangé).
- **Agitation** : chips dans *More* (`none · swirl · stir · WDT · pulse`).
- **Filter** : rangée dans *More*, préremplie depuis le brewer par défaut ; tap cycle les filtres déclarés dans Setup.
- **Complétude** : dans la rangée de titre de *More*, un `tag` `inkMuted` : « Comparable » ou « 2 fields missing » ; tap → surligne (`paperShade` 1,1 s, même mécanisme que la dictée) les champs manquants. Jamais un bloqueur, jamais rouge.
- **Rangée `BrewList`** : ajouter la mouture (« 22 clicks » ou `raw`) après le ratio, et TDS / EY en `tag` `inkMuted` quand ils existent. Le ratio s'affiche « 1:16 » s'il est rond, « 1:14.3 » sinon. Même densité (padding V 10, `Typography.tag`), une seule ligne de plus au maximum.
- **Brew again** : action `catalogueLabel` sur chaque rangée de `BrewList` (swipe ou dans la feuille du brew, à côté de *Save as recipe*). Crée un brouillon pré-rempli depuis *ce* brew (kit, eau, recette, étapes, mouture), date du jour, rating et Taste vides.

### 4.3 Dictée

`SpokenBrewParser` reconnaît en plus :
- la mouture avec unité : « vingt-deux clics », « 22 clicks », « position 2.4 », « setting 14 » → `grind.value` (+ `raw` conservé) ;
- les étapes : « bloom cinquante grammes quarante-cinq secondes, puis cent grammes à une minute, puis… » → `steps[]` (cible), en FR / EN ;
- l'agitation : « swirl », « stir », « WDT ».

### 4.4 Setup

- `Equipment.grinder` : `adjustmentType` existe ; ajouter `unitLabel` calculé (`clicks` / `number` / `position`) pour l'affichage.
- `Equipment.brewer` : ajouter `filters: [Filter]` (marque, forme) si absent, et `defaultFilterId`.

### 4.5 Migration

- `grind: String` → `GrindSetting(raw: old)`; si `old` parse en nombre + unité connue (`clicks`, `clics`, `#`, `position`), remplir `value` ; si un seul broyeur existe dans Setup, `grinderId` = ce broyeur (heuristique, pas une certitude → `captureSource` inchangé).
- Décodage tolérant : un `Brew` sans `agitation` / `filterId` / `steps` reste valide.
- Supabase : colonnes `grind_grinder_id`, `grind_value`, `grind_raw`, `agitation`, `filter_id`, `steps` (jsonb). Migration SQL additive uniquement.

---

## 5. WP2 — Profil sensoriel 7 axes / 10

### 5.1 Modèle

```swift
enum TasteAxis: String, Codable, CaseIterable {
    case acidity, bitterness, sweetness, aroma, aftertaste, body, clarity   // ordre = ordre du radar, sens horaire depuis midi
}

struct TasteProfile: Codable, Equatable {
    var values: [TasteAxis: Int]                 // 0...10 ; absent = non noté
    var isEmpty: Bool { values.isEmpty }
    subscript(axis: TasteAxis) -> Int? { values[axis] }
}

extension Brew {
    var taste: TasteProfile                      // remplace l'ancien 6 axes 1–5
    var legacyTaste: [String: Int]?              // ancien profil, conservé tel quel jusqu'à v2
}
```

Validation : entier, 0…10, sinon rejeté à l'écriture. `0` est une note (« absent »), pas « non noté ».

### 5.2 Saisie — `AxisRail`

Un composant d'archive par axe, sous *Taste* (replié, comme aujourd'hui) :

```
ACIDITY                                     7
─·─·─·─·─·─·─●─·─·─·─                          ← rail hairline 1 pt, 11 ticks (0…10), dot ink 8 pt
```

- Label `catalogueLabel` à gauche, valeur en `Typography.tag` `ink` à droite (« — » si nil).
- Tap sur un tick ou drag le long du rail. Snap entier. Haptic `tap` à chaque changement de valeur (déjà « chip, rating, axe »). Retaper la valeur courante → `nil` (même convention que le rating).
- Hauteur de rangée 34 pt ; hit slop vertical ±10 pt.
- Pas de slider système, pas d'accent.

### 5.3 Lecture — `TasteRadar`

Remplace l'hexagone actuel.

- Heptagone, centre au milieu de la largeur de contenu, rayon = 38 % de la largeur du sheet ; labels des axes en `catalogueLabel` `inkMuted` à `rayon + 14 pt` ; anneaux hairline à 2 / 4 / 6 / 8 / 10 ; rayons hairline.
- Polygone du brew courant : stroke `ink` 1 pt, fill `ink` à 8 % ; sommets = dots `ink` 4 pt. Axe non noté : pas de sommet, le polygone saute l'axe (segment direct entre voisins notés) et le rayon reste hairline.
- Brew de comparaison (précédent du même café par défaut ; celui choisi en WP4) : stroke `inkMuted` 1 pt, pas de fill, pas de dots.
- Animation : le polygone se met à jour en `quick` à chaque changement de valeur.
- Accessibilité : `accessibilityLabel` = « Acidity 7, bitterness 4, … » ; valeurs non notées omises.
- Le tracé est un `Path` dans `Canvas` ; aucune valeur de géométrie dans la vue : rayon, épaisseur, opacité de fill dans `Motion.Radar` (nouveau namespace, mêmes règles que `Motion.Tile`).

### 5.4 Dictée

Grammaire FR / EN pour les 7 axes, deux formes :
- chiffrée : « acidité 7 », « acidity seven », « corps quatre » → valeur ;
- qualitative (mappée) : `faible / low` → 3, `moyen / medium` → 5, `élevé / high` → 7, `très / very` ±2, `longue finale / long finish` → aftertaste 8, `courte / short` → 3, `propre / clean` → clarity 8, `boueux / muddy` → clarity 3.

Ce qui est parsé se surligne 1,1 s (`paperShade`), tap = undo — mécanisme existant.

### 5.5 Migration

`legacy[axis] (1…5)` → `values[axis] = legacy × 2` pour les six axes existants ; `clarity` absent. `legacyTaste` conserve l'original. Supabase : `taste` (jsonb) remplace les six colonnes ou s'ajoute à côté selon le schéma actuel ; les anciennes colonnes ne sont pas supprimées dans ce lot.

---

## 6. WP3 — Roue aromatique de référence

### 6.1 Données : `flavor-wheel.json`

Livré avec ce brief. Schéma `kohi.flavor-wheel/1`, 111 nœuds, 9 familles, 3 niveaux.

| Champ | Contenu |
| --- | --- |
| `id` | chemin stable en kebab-case (`fruity-berry-blackberry`) — c'est ce qui est stocké dans les brews et les cartes |
| `level` | 1 famille · 2 sous-famille · 3 descripteur |
| `parent` | id du parent, `null` pour les familles |
| `en` / `fr` | libellés ; l'app affiche selon la locale, stocke l'id |
| `synonyms` | minuscules, EN + FR, pour le rapprochement des notes de carte |
| `origin` | `enzymatic` · `sugar-browning` · `dry-distillation` · `defect` — heuristique pour le diagnostic, **à vérifier** |
| `quick` | 42 descripteurs du quick set (chips par défaut) |
| `color` (familles) | approximation pour export / impression **uniquement** |
| `order` (familles) | ordre angulaire de la roue |

Statut de vérification : structure et libellés EN = roue SCA 2016 (à re-contrôler contre la liste officielle avant seed) ; FR, synonymes, `origin`, couleurs = ajouts Kohi, **à vérifier** par JBK. La roue française partagée (« Roue des arômes perçus », 10 familles) n'est pas une taxonomie de référence ; on l'utilise comme source de vocabulaire FR, et ses familles se projettent ainsi sur la roue SCA : Fruité → Fruity (Berry / Other / Dried) · Agrumes → Citrus Fruit · Floral → Floral · Sucré → Sweet · Noix & graines → Nutty · Chocolat & cacao → Cocoa · Épicé → Spices · Boisé → Woody (Other) + Burnt / Smoky (Roasted) · Végétal → Green/Vegetative · Fermenté & alcoolisé → Sour/Fermented.

Chargement : `FlavorWheel.shared` (bundle, décodage au premier accès, index par id et par synonyme). Aucune modification à chaud ; une nouvelle version du JSON = une nouvelle version d'app.

### 6.2 Modèle

```swift
struct FlavorTag: Codable, Hashable {
    var id: String            // id de la roue, ou "custom:<texte normalisé>"
    var custom: String?       // texte tel que saisi, si custom
}

extension Brew { var flavors: [FlavorTag] }          // remplace les chips string
extension Card {
    var tastingNotes: [String]                        // existant, texte OCR / saisi — inchangé
    var declaredFlavors: [FlavorTag]                  // calculé et mis en cache : FlavorMatcher(tastingNotes)
}
```

### 6.3 `FlavorMatcher` (déterministe)

Entrée : une note de carte (« Myrtille, chocolat au lait, finale florale »). Sortie : `[FlavorTag]` + les fragments non reconnus.

1. Normaliser (minuscules, sans accents, singulier simple, séparation sur `,` `/` `·` `&` `et` `and`).
2. Chercher chaque fragment dans l'index des synonymes (exact, puis préfixe, puis distance d'édition ≤ 1 sur ≥ 6 lettres).
3. Un fragment qui matche un niveau 2 (« floral ») retourne le niveau 2, pas ses feuilles.
4. Non reconnu → `custom:`.

Tests : « blueberry, milk chocolate » → `fruity-berry-blueberry`, `nutty-cocoa-cocoa-chocolate` ; « fleur d'oranger » → `floral-floral-jasmine` (synonyme) ; « Rooibos » → custom. Le matcher tourne aussi sur les chips string des brews existants à la migration.

### 6.4 UI — `FlavorPicker`

Remplace le picker de chips actuel dans le brew sheet (*Taste*) et dans l'édition de carte (*Tasting notes* garde son texte ; le picker s'y ajoute en « Match to wheel » — voir 6.5).

- **Recherche** en tête : `TextField` `value`, résultats en chips au fil de la frappe (id ou synonyme), Entrée sur un texte inconnu → chip `custom:`.
- **Quick** : les 42 chips `quick` en `FlowLayout` (spacing 7 / 8), plus les saveurs des N derniers brews de l'utilisateur en premier.
- **All** (replié) : 9 en-têtes de famille en `catalogueLabel`, filet hairline, sous chaque famille les niveaux 2 en chips ; un niveau 2 avec feuilles se déplie (`chevron.right` 8 pt) en une rangée de feuilles. Sélection = fill `ink` / texte `paper` (TagChip).
- Chips sélectionnés affichés au-dessus du picker, regroupés par famille dans l'ordre `order`, séparés par un `·` `inkMuted`.
- Aucune image, aucune couleur, aucune icône de fruit.
- **Variante à trancher (§12)** : la vue *All* en **`FlavorMap`**, un treemap fixe en hairline — 9 cellules de familles (aires proportionnelles au nombre de descripteurs), sous-familles en cellules internes, feuilles en chips au tap ; sélection = fill `ink` / texte `paper`. Même information que la liste, lecture plus rapide, mais 111 nœuds sur 340 pt de large demandent deux niveaux de zoom (famille → sous-famille). Prototyper les deux sur simulateur avant de choisir.

### 6.5 Carte : déclaré vs perçu

Dans `CardDetailView`, sous *Notes* :

- Les chips *Notes* restent le texte de la carte (outline, inchangé).
- Nouvelle rangée `catalogueLabel` **On the wheel** : les `declaredFlavors` reconnus, en chips outline ; un fragment non reconnu n'apparaît pas ici (il reste dans *Notes*). Tap sur « Match to wheel » en édition permet de corriger le rapprochement (ouvre `FlavorPicker` pré-sélectionné).
- Section **Profile** (voir WP4 §7.4) : « Found in your brews » — les saveurs des brews de ce café, triées par fréquence, avec un `tag` `✓` `inkMuted` quand elles sont aussi déclarées par la carte. C'est le pont déclaré ↔ perçu.

### 6.6 Diagnostic

`BrewDiagnosis` reçoit les `flavors` et leur `origin` : si ≥ 2 saveurs `dry-distillation` (ashy, smoky, acrid) *et* amertume « too much », la proposition passe en tête : « Ashy and bitter: shorter contact or cooler water », niveau de preuve *pratique*. Si ≥ 2 saveurs `defect` (papery, cardboard, stale), pas de proposition de réglage — note « These read like staling: check the roast date » (F18 du PRD, *à vérifier*). Une variable à la fois, comme aujourd'hui.

### 6.7 `FlavorWheelView` (Could)

Sunburst en lecture seule, encre sur papier : anneaux hairline, secteurs sans fill, un secteur sélectionné fill `ink` 8 %, feuille sélectionnée fill `ink` ; labels de familles en `catalogueLabel` sur l'anneau extérieur. Utilisé dans *Profile* si le temps le permet. Pas de rotation, pas d'interaction en 1.0 de ce lot.

---

## 7. WP4 — Comparaison entre extractions

### 7.1 Modèle

```swift
struct BrewComparison {
    let a: Brew                         // référence (brew ouvert)
    let b: Brew                         // comparé
    var parameterDeltas: [ParameterDelta]      // dose, output, ratio, temperature, time, grind, tds, ey, flow, agitation, water, kit
    var tasteDeltas: [TasteAxis: Int]          // b − a, axes notés des deux côtés seulement
    var flavors: (common: [FlavorTag], onlyA: [FlavorTag], onlyB: [FlavorTag])
    var sentence: String?                       // ce qui a changé → ce qui a bougé
}
```

Éligibilité : `isComparable` des deux côtés ; par défaut même carte ; option « any coffee, same method » (chip).

### 7.2 `BrewCompareSheet`

Ouverture : depuis le brew sheet (*Compare* actuel devient une rangée « Compare with… ») et depuis `BrewList` (long press → « Compare with… »). Feuille papier, padding 26 / 14 / 60.

1. **Picker B** : rangées `BrewList`-like des brews éligibles (date · méthode · ratio · rating), les plus proches en date d'abord ; chip « Best », chip « Previous ». Choisir B ferme le picker.
2. **Radar** superposé : A `ink`, B `inkMuted` (TasteRadar, mode comparaison).
3. **Parameters** : rangées label 74 pt · A · B · Δ ; Δ en `Typography.tag`, `ink` si ≠ 0, `inkMuted` si égal ; unités en `tag`. Mouture : Δ en clics si même broyeur, sinon en µm proxy « ≈ », sinon « — ».
4. **Flavors** : trois lignes `catalogueLabel` — *Both* · *Only this* · *Only that* — chips outline.
5. **What changed** : une phrase en `Typography.body`, générée par règles (§7.3) ; absente si aucune règle ne s'applique.
6. Actions en `catalogueLabel` : « Brew again from A », « Brew again from B ».

Pas de graphique en dehors du radar. Pas d'export dans ce lot.

### 7.3 Règles de la phrase

Une seule cause principale (le paramètre avec le plus grand Δ normalisé), un ou deux effets (les axes avec |Δ| ≥ 2). Gabarits :

- grind plus fin + acidity ↓ / body ↑ : « Finer grind (−2 clicks) → less acidity, more body »
- temp ↑ + bitterness ↑ : « Hotter water (+3 °C) → more bitterness »
- ratio plus court + body ↑ / clarity ↓ : « Shorter ratio (1:15) → more body, less clarity »
- time ↑ + aftertaste ↑ : « Longer contact (+20 s) → longer aftertaste »
- eau différente + sweetness ↑ / acidity ↓ : « Different water (Volvic) → sweeter, softer »
- plusieurs paramètres changés : « Several things changed (grind, temp) — hard to attribute » ; c'est vrai, on le dit.

Chaque phrase porte, en `tag` `inkMuted`, le niveau de preuve `practice` ; ces relations viennent des règles G7 du PRD, pas d'une mesure.

### 7.4 Carte : section **Profile**

Dans `CardDetailView`, entre `BrewList` et *Pages & documents* (nouvel ordre de lecture, à refléter dans `design-system.md` §8) :

- `TasteRadar` du **brew médian** par axe sur les brews comparables du café (≥ 2 brews, sinon la section n'apparaît pas), et le **meilleur brew** en `inkMuted` par-dessus.
- « Found in your brews » : saveurs par fréquence, `✓` si déclarées par la carte (§6.5).
- Une rangée `tag` : « 5 brews · avg 3.6 · best 4/5 » puis, si ≥ 2 méthodes, une rangée par méthode : « V60 4/5 · Espresso 3/5 » (moyenne des ratings, une décimale).

C'est le « Profil de café » : ce que ce café donne *chez toi*, à côté de ce que dit la carte.

### 7.5 Insights

Ajouter une quatrième rangée, même seuil (3 brews comparables) : **Trend** — « Your last three brews of X: acidity ↓, body ↑ ». Rien d'autre.

---

## 8. WP5 — Parité iBrew, ce qui manque encore

| Item | Où | Détail | Priorité |
| --- | --- | --- | --- |
| `decafMethod` | On the bag | chips `Swiss Water · CO₂ · Sugarcane EA · Mountain Water · Other` ; OCR `BagFieldParser` reconnaît les libellés | Should |
| `productURL` | Caption / édition | URL de la fiche produit : remplie par le QR / code-barres (déjà lu, pas conservé) ou collée ; Caption « Link » avec `arrow.up.right` 9 pt comme *Place* ; base de la Share Extension (PRD 6.8) | Should |
| `farm` | Caption / édition | texte, sous Producer ; OCR « Farm », « Finca », « Fazenda », « 農園 » | Could |
| `washStation` | Caption / édition | texte, sous Farm ; OCR « Washing station », « Station de lavage » | Could |
| Méthodes | Brew / Setup | garder les 7 familles ; ajouter `siphon`, `batch`, `ibrik` ; Chemex / Kalita / Origami / Switch / Clever restent des **brewers** de la famille Filter ou AeroPress-Immersion, pas des méthodes | Could |
| Recherche | Grille | filtres méthode (brews), saveur (id roue, déclaré ou perçu), lieu ; tri (date d'ajout, torréfacteur, pays, meilleur brew) **dans la recherche seulement**, la grille reste triée par date | Should (tri : Could) |
| « Brew again » | BrewList | WP1 | Must |
| Photos multiples | Attachments | déjà couvert ; rien à faire | — |
| PDF / image de partage | — | hors lot ; le PRD garde export JSON / CSV en 1.1 ; « Print a card » à instruire à part | — |

---

## 9. Tests attendus

- `GrindSettingTests` : parse de « 22 clicks », « 2.4 », « fine » ; migration depuis texte ; `micronsProxy` avec calibration > pas fabricant > nil.
- `BrewComparabilityTests` : `isComparable` sur les combinaisons de champs manquants.
- `TasteProfileTests` : bornes 0…10, `nil`, migration 1–5 → 0–10, encodage / décodage tolérant.
- `SpokenBrewParserTests` : 7 axes FR / EN (formes chiffrée et qualitative), mouture avec unité, étapes.
- `FlavorWheelTests` : le JSON charge, 9 familles, ids uniques, chaque `parent` existe, `quick` ≥ 40.
- `FlavorMatcherTests` : les trois cas de §6.3 + accents + pluriels + custom.
- `BrewComparisonTests` : deltas de paramètres et d'axes, gabarits de phrase, cas « plusieurs paramètres ».
- `CardProfileTests` : médiane par axe avec axes partiellement notés ; seuil ≥ 2 brews.
- Snapshot tests (light only) : `AxisRail` nil / 0 / 7, `TasteRadar` complet / partiel / comparaison, `FlavorPicker` quick / all, `BrewCompareSheet`.

---

## 10. Feature flags, sync, télémétrie

- Flags locaux (Compte, section développeur) : `taste7`, `flavorWheel`, `brewCompare`, `cardProfile` — on par défaut en DEBUG, on en release une fois les snapshots validés.
- Sync : migrations SQL **additives** (nouvelles colonnes / jsonb), aucune suppression ; les clients anciens ignorent les champs inconnus (décodage tolérant des deux côtés).
- `AIEvent` : rien de nouveau, ce lot est déterministe. La dictée des axes passe par la grammaire locale ; si `field-extract` est sollicité, l'event existant suffit.

---

## 11. Ordre d'exécution proposé

1. **WP1** modèle + migration + tests (sans UI) → 2. **WP2** modèle + migration + `AxisRail` + `TasteRadar` → 3. **WP3** JSON + `FlavorWheel` + `FlavorMatcher` + `FlavorPicker` → 4. **WP1** UI (Grind, Pours, Agitation, Filter, Brew again) → 5. **WP4** `BrewComparison` + sheet + *Profile* → 6. **WP5** → 7. **WP3** `FlavorWheelView` si le temps le permet.

Le modèle avant l'UI, toujours : la migration doit tourner sur une archive réelle (celle de JBK) avant qu'un écran change.

---

## 12. Questions ouvertes pour JBK

1. **Clarity** : garder ce libellé (usage spécialité) ou « Cleanliness » ? Le prototype dit Clarity ; on le garde sauf avis contraire.
2. **0 vs nil** : un axe à 0 est une note (« pas d'amertume »). D'accord pour que « retaper la valeur » remette à nil ?
3. **Origine des arômes** (`origin`) : à valider avant que le diagnostic s'en serve ; sinon on la laisse dans le JSON sans l'utiliser.
4. **Roue en couleur** : confirmé qu'on reste encre / papier à l'écran ? Les couleurs du JSON ne servent qu'à un export futur.
5. **Complexité** (démo) : huitième axe, ou couverte par Aroma + Aftertaste ? Recommandation : ne pas l'ajouter — un axe de plus coûte une rangée à chaque brew, et « complexité » se lit déjà dans le nombre de saveurs trouvées.
6. **`FlavorPicker` vs `FlavorMap`** pour la vue *All* (§6.4) : liste hiérarchique ou treemap hairline ? À prototyper.
7. **`waterIn`** pour l'espresso : utile pour toi, ou seulement pour l'import iBrew ? Si import seulement, on le garde comme colonne sans UI.
8. **Retours « choses à améliorer »** : le PDF *Manifeste (wip)* contient le manifeste seul, sans commentaires. S'ils sont ailleurs (commentaires Notion, notes), les coller ici pour une 2.2.

---

## 13. Hors lot (pour ne pas dériver)

Export PDF / image carrée · commandes vocales pendant l'extraction · rosace du timer · scan IA sachet / ticket / eau · Ask contextualisé · seeds torréfacteurs / connaissances · balance Bluetooth · communauté · thème sombre.
