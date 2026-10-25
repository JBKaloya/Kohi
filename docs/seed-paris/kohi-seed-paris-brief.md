# Kohi — Seed Paris : torréfacteurs et cafés de spécialité (source specialtycoffee.paris)

**1er octobre 2026 · JBK / jbk studio — brief d'injection pour Cursor.** Fichiers livrés : `roasters-paris-seed.csv` / `.json` (127 torréfacteurs) et `places-paris-seed.csv` / `.json` (694 lieux). Extraction faite le 01/10/2026 depuis les pages publiques du site, à la main dans le navigateur (6 pages de l'index Roasters, 21 pages de l'index Coffee Shops, 127 fiches torréfacteur, la page « Closed »). Les fiches détaillées des cafés (horaires, machine, prix, coordonnées GPS) n'ont **pas** été extraites : inutile pour Kohi, et c'est la part la plus « substantielle » de la base du site (voir §1).

---

## 1. Ce qu'on peut en faire — à lire avant d'injecter

specialtycoffee.paris est une base **curatée** (677 cafés, un « Specialty Score » éditorial, un suivi des fermetures) et le site a sa propre app iOS/Android. En droit européen, l'extraction d'une partie substantielle d'une base de données est protégée indépendamment du droit d'auteur (droit *sui generis*, directive 96/9/CE). Les faits eux-mêmes (un nom, une adresse, un site web, un pays) ne sont pas protégés, et c'est ce qu'on a pris. Trois règles :

1. **Usage interne / TestFlight : OK** avec la provenance affichée (« from specialtycoffee.paris ») — c'est de toute façon la règle d'honnêteté de Kohi.
2. **Avant une sortie publique** : écrire à l'auteur du site — c'est exactement le « réseau de gens qui aiment le café » du manifeste, et un partenariat de données (lien vers leur fiche depuis Kohi, par exemple) vaut mieux qu'une copie. Sinon, reconstruire le seed depuis les sources primaires (sites des torréfacteurs, Apple Maps) et ne garder que les faits.
3. **Ne pas réutiliser le « Specialty Score »** dans l'app : c'est leur travail éditorial. La colonne `siteScore` est dans le CSV pour ton tri, pas pour l'affichage. Même chose pour les textes et photos, qu'on n'a pas pris.

---

## 2. Les chiffres

| | Total | Détail |
| --- | --- | --- |
| Torréfacteurs | **127** | 89 FR, 5 NL, 3 DK / US / IT / DE, puis 1–2 par pays (23 pays) ; 21 déjà dans l'Annexe D du PRD → `alsoInAnnexeD` |
| Lieux | **694** | 674 ouverts · 15 fermés (avec le mois) · 5 fermés temporairement |
| Lieux reliés à ≥ 1 torréfacteur | 462 | 34 servent plusieurs torréfacteurs (Crible : KB + Drop ; Noeud : Friedhats + Datura + Manhattan…) |
| Lieux sans torréfacteur connu | 232 | le site ne le renseigne pas — à compléter par l'usage (voir §5) |
| Torréfacteurs avec boutique(s) à Paris | 56 | dérivé par nom de marque (`ownShopIds`) : Noir 20, The Coffee 20 (dont 2 fermés), Terres de Café 9, Cuvée Noire 9, Coutume 7… |
| Sans site web | 3 | Cœur Coffee, Brûlerie de la Folie-Méricourt, Ola's ; 7 n'ont qu'un Instagram (`instagram`) |
| Arrondissements | 20 | 11ᵉ 85 lieux · 9ᵉ 63 · 3ᵉ 62 · 2ᵉ 55 · 10ᵉ 55 · 18ᵉ 42 · 6ᵉ 41 · 1ᵉʳ 40 · 4ᵉ 40 … 13ᵉ 5 |

À exclure ou à marquer avant injection (colonne `note`) : **Illy** et **Hausbrandt** (industriels, pas spécialité) ; **The Coffee** (chaîne brésilienne, 20 points de vente, spécialité à confirmer) ; **Café Joyeux** (chaîne solidaire, torréfaction propre à confirmer). Les chaînes de cafés (Goodnews, Kozy, Immersion, Copains, Saint Pearl, Blondie…) sont des **lieux**, pas des torréfacteurs — elles n'apparaissent que dans `places`.

---

## 3. Schémas

### 3.1 `roasters-paris-seed` (→ fusion dans `roasters.json`)

| Colonne | Type | Note |
| --- | --- | --- |
| `id` | slug | slug du site ; stable, sert de clé de rapprochement avec `places.roasterIds` |
| `name` | texte | tel qu'affiché par le site (« Fève », « L'Arbre à Café ») ; « supreme roastworks. » normalisé en « Supreme Roastworks » |
| `country` / `countryName` | ISO 3166-2 / texte | |
| `website` | URL | `https://` ajouté ; pour 7 torréfacteurs c'est l'Instagram (voir `instagram`) |
| `instagram` | @handle | rempli seulement quand le site n'avait qu'un Instagram — l'agent d'enrichissement du PRD (§6, Annexe D) complète les autres |
| `parisShopsServed` | entier | nombre de cafés parisiens qui servent ce torréfacteur selon le site — **ordre de tri** du picker, jamais affiché tel quel |
| `ownShopsInParis` / `ownShopIds` / `ownShopAddresses` | dérivés | lieux dont la marque = le torréfacteur ; c'est l'indice « a une boutique / un atelier à Paris » |
| `alsoInAnnexeD` | oui/vide | présent dans le seed Annexe D du PRD → statut *partiel (deux sources)* |
| `sourceUrl` / `fetchedAt` | | provenance, obligatoire dans l'app (ligne « from specialtycoffee.paris · Oct 2026 ») |
| `status` | | `partiel (deux sources)` ou `à vérifier (specialtycoffee.paris)` — jamais *vérifié* : personne n'a ouvert les 127 sites |
| `note` | texte | exclusions et coquilles (le slug du site pour Onyx est `onxy`) |

Colonnes cibles du PRD conservées : `name · city · country · website · instagram · source · status` ; `city` = « Paris » quand `ownShopsInParis > 0`, sinon vide (un torréfacteur étranger n'a pas de ville parisienne).

### 3.2 `places-paris-seed` (→ nouveau `places.json`)

| Colonne | Type | Note |
| --- | --- | --- |
| `id` | slug | slug du site |
| `name` | texte | nom complet (« Noir - Rue Richer ») |
| `brand` | texte | partie avant « - » : la marque, pour grouper les chaînes et rapprocher d'un torréfacteur |
| `address` / `postalCode` / `arrondissement` / `city` | | adresse telle que le site l'écrit (abréviations « Bd », « R. », « Pass. ») ; **pas de coordonnées** → géocoder à l'import avec `CLGeocoder` (ou à la première ouverture, en tâche de fond), jamais à l'écran |
| `roasterIds` / `roasterNames` | liste | depuis les fiches torréfacteur ; vide = inconnu, pas « aucun » |
| `status` | `open · closed · temp` | `closed` = page « Closed » du site ou mention sur une fiche torréfacteur ; `temp` = « temporarily closed » |
| `closedOn` | AAAA-MM | pour les 15 fermés récents |
| `siteScore` | S+ … C+ | **ne pas afficher** (§1) ; utile pour choisir un sous-ensemble |
| `sourceUrl` / `fetchedAt` | | provenance |

Modèle Swift proposé :

```swift
struct Place: Codable, Identifiable {
    let id: String                 // slug
    var name: String, brand: String
    var address: String, postalCode: String, arrondissement: Int?, city: String
    var roasterIds: [String]
    var status: PlaceStatus        // .open, .closed, .temp
    var closedOn: String?
    var coordinate: Coordinate?    // rempli par géocodage, jamais par le seed
    var source: SeedSource         // .specialtyCoffeeParis(fetchedAt) · .user · .import
}
```

---

## 4. Règles d'injection (Cursor)

1. **Fusion des torréfacteurs** : clé = nom normalisé (sans accents, sans ponctuation, minuscules) **ou** domaine du site web. Un torréfacteur déjà dans `roasters.json` garde son `id` Kohi ; on lui ajoute `externalIds.specialtyCoffeeParis = slug`, `parisShopsServed`, et son statut passe à *partiel* s'il avait une autre source. Test : aucune ligne du CSV ne crée un doublon de « Belleville Brûlerie », « Terres de Café », « KB Coffee Roasters », « L'Arbre à Café » (graphies différentes dans l'Annexe D).
2. **Les lieux fermés entrent dans le seed** mais n'apparaissent pas dans les pickers ; ils servent au rapprochement d'une carte ancienne (« acheté chez Brouillon, mai 2025 ») et s'affichent avec « Closed · May 2026 » en `tag`.
3. **Provenance partout** : toute fiche issue du seed porte « from specialtycoffee.paris · Oct 2026 » en `tag` ; une correction par l'utilisateur passe la ligne en *from you* et prime.
4. **Rien n'est « vérifié »** : les statuts restent *à vérifier* / *partiel* jusqu'à la passe de vérification de l'Annexe H (ouvrir le site, confirmer qu'il torréfie).
5. **Pas de score, pas de texte, pas de photo** du site dans l'app.
6. **Rafraîchissement** : pas de job automatique. Relancer l'extraction (annexe A) à la main avant un build, diff sur `id`, et appliquer seulement les ajouts, les fermetures et les changements de site web.

---

## 5. Où ça sert dans Kohi

- **Carte › Roaster** : le `CatalogPicker` des torréfacteurs trié par `parisShopsServed` puis alphabétique, FROM YOUR ARCHIVE en tête (ceux déjà présents sur tes cartes), puis ALL, puis *Add manually*. L'OCR du scan (`field-extract`) matche le nom du torréfacteur contre ce seed avant de proposer une saisie.
- **Carte › Bought at / Drunk at** (nouveau champ `placeId`, optionnel) : picker des lieux, NEARBY d'abord si la localisation est accordée (géocodage), puis par arrondissement, puis *Add manually*. Choisir un lieu **pré-remplit le torréfacteur** quand `roasterIds` n'en contient qu'un ; en propose plusieurs sinon, avec « served here » en `tag`. C'est le lien caféothèque ↔ lieu du manifeste, sans réseau social.
- **Fiche torréfacteur** (plus tard) : ses boutiques à Paris (`ownShopIds`) et les cafés qui le servent — la donnée est là, l'écran n'est pas prioritaire.
- **Enrichissement par l'usage** : quand l'utilisateur saisit un torréfacteur pour une carte achetée dans un lieu dont `roasterIds` est vide, on propose « Remember that *Silo* serves *Fève*? » — c'est ainsi que les 232 lieux sans torréfacteur se remplissent, localement d'abord.
- **Import** (brief #3 §10) : les lieux et torréfacteurs importés d'iBrewCoffee / Beanconqueror se rapprochent du seed par nom normalisé, comme en 4.1.

---

## 6. Limites connues

- Les adresses sont celles du site : quelques-unes sont bruitées (« Boutique & Atelier à l'angle, RDC, 7 Rue du Général Blaise », « 75010 20 Rue d'Hauteville », « Trombone — 69 Rue des Haies 75020, 75020 »). Le géocodeur s'en sort ; à nettoyer à la main si une fiche est erronée.
- `roasterIds` vient des fiches torréfacteur, pas des fiches café : un café qui change de torréfacteur n'est à jour que si le site l'a mis à jour.
- `ownShopsInParis` est une heuristique par nom de marque : « Café La Procure x Coutume » compte comme Coutume (collab), Merci Noir ne compte pas comme Noir. À relire pour les 56 concernés.
- Le site ne couvre que Paris intra-muros (aucun 92–95 dans l'index).
- Les 232 lieux sans torréfacteur ne sont pas « sans torréfacteur » : le site ne le sait pas.

---

## Annexe A — Procédure d'extraction (navigateur, ~10 min)

Depuis une page du site, dans la console (ou via l'extension) — `fetch` same-origin, 250–400 ms entre deux pages, aucune donnée hors nom / adresse / site / pays / statut :

```js
// 1. Torréfacteurs (6 pages) : a[href^="/roasters/"] → h3 (nom), span « N shops », span domaine, span drapeau + pays
// 2. Cafés (21 pages, ?page=N) : a[href^="/shops/"] avec h3 → nom, span adresse (code postal 750xx), span score
// 3. Fiches torréfacteur (/roasters/{slug}) : a[href^="/shops/"] → slug ; « Permanently closed » / « temporarily » dans le texte → statut
// 4. /shops/closed → 15 fermetures datées
// Dédupliquer sur slug (la première carte de chaque fiche est répétée), puis build_seeds.py → CSV / JSON
```

Le script Python de construction (`build_seeds.py`, livré) fait le reste : code postal → arrondissement, marque = texte avant « - », rapprochement torréfacteur ↔ boutiques par alias, fusion des statuts, marquage Annexe D, exclusions.
