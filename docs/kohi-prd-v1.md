# Kohi — PRD v1

**Statut** : brouillon 0.2 · **Date** : 9 septembre 2026 · **Owner** : JBK (jbk studio)  
**Documents liés** : `fonctionnalites.md` (état actuel), `design-system.md` (fondation UI)

---

## 0. En une page

Kohi passe d'une **archive** (des cartes posées sur du papier) à un **atelier** : le même objet-carte devient le point d'entrée d'une pratique — brasser mieux, avec son propre matériel, et garder la trace de ce qui a marché.

Quatre paris pour la v1 :

1. **Deux objets, deux onglets.** *Coffees* (l'archive, inchangée dans son esprit) et *Recipes* (tout ce qui touche à l'extraction, agrégé au-delà d'une carte).
2. **Le setup comme invariant.** Broyeur, méthode, eau : enregistrés une fois, rattachés à chaque brew. C'est ce qui rend les extractions comparables entre elles — et demain entre utilisateurs.
3. **Capturer, ne pas saisir.** Scan, OCR, dictée, import : l'utilisateur *dit* ou *montre*, l'app structure. Le clavier est le dernier recours.
4. **Une intelligence expérimentale mais honnête.** L'IA est dans la 1.0, marquée comme telle (`sparkles`), avec des règles déterministes en filet de sécurité. Elle remplit, explique, adapte ; elle n'invente pas de science.

Ce qui sort : le calcul de caféine. Ce qui attend : balance Bluetooth, communauté, stats globales.

---

## 1. Contexte — ce que Kohi fait aujourd'hui

- Un flux d'ajout unique (scan → recadrage → OCR → fiche), une grille d'objets, un détail « catalogue de musée ».
- Un journal de brews par carte, pensé pour le *deuxième* café : Save suffit si rien n'a changé.
- 100 % local par défaut ; Supabase optionnel pour la sync, le second avis OCR (`card-vision`) et les posters (`card-poster`).

Ce qui manque pour l'objectif « meilleur café chez moi » :

- Aucune notion d'**équipement** ni d'**eau** : deux brews ne sont pas comparables.
- Aucune **recette de référence** : le premier brew d'un café part de zéro (ou de la recette imprimée, quand il y en a une).
- Le rating 1–5 et les axes −/·/+ sont **collectés mais pas exploités** : rien ne dit quoi changer la prochaine fois.
- Tout ce qui n'est pas sur la carte se **tape** : notes, réglages, sensations. C'est là que la saisie fatigue.

---

## 2. Vision, objectifs, non-objectifs

### Thèse

> Un café, une carte, un geste. Kohi garde la mémoire de ce que tu as bu *et* de comment tu l'as préparé, pour que le prochain soit meilleur.

L'archive reste le cœur émotionnel (l'objet, le papier, l'ombre). L'atelier est la couche utile qui justifie d'ouvrir l'app tous les matins, pas seulement à chaque nouveau sachet.

### Objectifs v1


| #   | Objectif                                        | Signal de succès                                                                                                    |
| --- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| O1  | Créer et suivre ma collection                   | 100 % des cafés achetés ou dégustés ont une carte ; chaque carte est rattachée à un torréfacteur normalisé          |
| O2  | Faire du meilleur café avec *mes* équipements   | ≥ 80 % des cafés ont ≥ 1 brew ; le brew n°2 ou n°3 d'un café est mieux noté que le n°1 dans la majorité des cas     |
| O3  | Poser les fondations de la donnée communautaire | Torréfacteurs, lieux, équipements, eaux et recettes sont des entités normalisées, pas du texte libre                |
| O4  | Saisir moins                                    | Médiane < 45 s pour logger un brew ; ≥ 70 % des champs de brew remplis sans clavier (pré-remplissage, dictée, scan) |


### Non-objectifs v1

- Partage social, profils publics, feed.
- Balance / capteurs Bluetooth (v2, uniquement si le suivi manuel montre une traction).
- Statistiques globales (cafés par mois, heatmap).
- iPad / Mac, thème sombre.
- Torréfaction maison (green beans, roast log) — hors périmètre définitif.

---

## 3. Pour qui


| Persona                                                                                                       | Ce qu'il veut                                                                                                 | Ce que la v1 lui donne                                                                                      |
| ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| **Le collectionneur-brasseur** (JBK) : bon matériel, plusieurs méthodes, achète en torréfacterie et en voyage | Retrouver un café, savoir *comment* il l'a bien réussi, ne pas gâcher les premiers grammes d'un sachet à 30 € | Recette suggérée dès la fiche, setup pré-rempli, diagnostic après dégustation, dictée du brew en une phrase |
| **Le débutant curieux** : un V60 ou un AeroPress, un broyeur manuel, achète en boutique                       | Une recette qui marche, comprendre pourquoi c'est acide ou amer, améliorer sa pratique du café                | Recettes de référence attribuées, correction d'une seule variable à la fois                                 |
| **Le pointu / compétiteur** : TDS-mètre, eau sur mesure, plusieurs broyeurs                                   | De la précision, de la comparabilité, des sources                                                             | Profil d'eau minéral par minéral, rendement d'extraction, base de connaissances citée                       |


La v1 est construite pour le premier. Les deux autres sont les gardes-fous : rien ne doit exiger un TDS-mètre, rien ne doit être faux pour quelqu'un qui en a un.

---

## 4. Analyse des idées soumises

Chaque idée est reprise avec un verdict, un enrichissement et une fenêtre de livraison (1.0 / 1.1 / 1.2 / v2).

### Navigation


| Idée                                      | Verdict | Enrichissement                                                                                                                                                                                                                                                           | Cible |
| ----------------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----- |
| Deux onglets « Mes cafés » / « Recettes » | **Oui** | Pas de `TabBar` système (hors grammaire). Deux mots en `catalogueLabel` à côté du wordmark, filet hairline sous l'actif. Le scan reste l'unique bouton de la grille. Un troisième lieu, *Setup* (équipement + eau), vit comme une feuille d'archive, pas comme un onglet | 1.0   |


### Carte et scan


| Idée                                                                         | Verdict                | Enrichissement                                                                                                                                                                                                                                                                                                             | Cible |
| ---------------------------------------------------------------------------- | ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- |
| Base de torréfacteurs Supabase, recherche + ajout (adresse, site, Instagram) | **Oui, entité clé**    | *Roaster* devient une entité liée, avec cache local et repli texte libre hors ligne. Dédoublonnage par nom normalisé + pays. Le fetch d'URL déjà existant (QR → Open Graph) alimente `website`. Seed : les torréfacteurs de ton archive + la liste de l'annexe D                                                           | 1.0   |
| Le champ Place pour capter *où* vont les amateurs                            | **Garder et typer**    | `Place` devient « Bought at » avec un type : *Roastery / Café / Shop / Online*. Lié au *Roaster* quand c'est le même lieu. La donnée intéressante (sourcing, torréfaction, méthode) vient de la carte et du brew, pas du lieu ; le lieu est l'index géographique qui reliera tout ça demain                                | 1.0   |
| Roast colour / level                                                         | **Oui**                | Échelle 5 crans (*Light · Medium-light · Medium · Medium-dark · Dark*) en chips, Agtron optionnel en nombre. C'est le champ n°1 pour proposer une température et un ratio                                                                                                                                                  | 1.0   |
| Cupping score                                                                | **Oui**                | Nombre 0–100 tel qu'imprimé. Pas de calcul ; on note ce que dit le torréfacteur. À terme, un profil CVA (voir §6.5) décrit mieux qu'un score                                                                                                                                                                               | 1.0   |
| Prix + quantité (50 / 100 / 250 g…)                                          | **Oui**                | Prix + devise + poids du sachet (chips 100 / 200 / 250 / 500 / 1000 g + libre). Prix au kilo calculé et affiché en `tag`. Utile perso, très utile en communauté                                                                                                                                                            | 1.0   |
| Numéro de lot                                                                | **Oui**                | Texte libre, parsé depuis la carte (« Lot », « Batch », « Roast # »)                                                                                                                                                                                                                                                       | 1.0   |
| *(ajout)* Date de torréfaction                                               | **Oui, prioritaire**   | Le champ le plus utile pour brasser : fraîcheur, dégazage. Distinct de « Date » (date du café) et de la date d'ajout. Parsé (« Roasted on », « Torréfié le », 焙煎日)                                                                                                                                                         | 1.0   |
| *(ajout)* Décaféiné                                                          | **Oui**                | Toggle dans le formulaire (le modèle existe déjà). Impacte la recette suggérée (mouture, température). `species` sort de l'UI                                                                                                                                                                                              | 1.0   |
| Recette suggérée par IA (torréfacteur, ou type de café + équipement)         | **Oui, cœur de la v1** | Trois niveaux de provenance, toujours affichés : (1) recette imprimée sur la carte, (2) recette de référence Kohi pour la méthode + le niveau de torréfaction, (3) adaptation à *ton* broyeur et *ton* eau. Les paramètres viennent de règles ; l'IA rédige le « pourquoi » et propose l'adaptation, marquée expérimentale | 1.0   |
| Retirer le calcul de caféine                                                 | **Oui**                | Supprimer l'estimation, la ligne dans `BrewList`, l'override manuel et les tables de rendement                                                                                                                                                                                                                             | 1.0   |


### Recettes et assistant


| Idée                                                                         | Verdict             | Enrichissement                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Cible              |
| ---------------------------------------------------------------------------- | ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------ |
| Recettes connues pour débutants                                              | **Oui**             | 16 recettes de référence embarquées hors ligne, attribuées (annexe A). Chaque recette est *traduite* dans le vocabulaire de ton setup (mouture, eau)                                                                                                                                                                                                                                                                                                                             | 1.0                |
| Suggestions à partir de mes cafés, historique, goûts, équipement             | **Oui, progressif** | 1.0 : méthode + roast level + équipement + historique (ton meilleur brew d'un café similaire). 1.1 : goûts (tes axes −/·/+ récurrents deviennent un biais de recette : « tu préfères plus de corps »)                                                                                                                                                                                                                                                                            | 1.0 → 1.1          |
| Assistant + littérature scientifique (percolation, statique, humidification) | **Oui, reformulé**  | La littérature est plus mince que le marketing ne le laisse croire, et certaines conclusions vont contre l'intuition (à TDS et extraction fixés, la température de l'eau change peu le profil sensoriel d'un filtre). L'assistant doit donc être *ancré et honnête* : une base de connaissances curée avec sources (annexe F), un diagnostic à règles, et l'IA pour expliquer. « Ask » arrive en 1.0 comme fonction expérimentale, contextualisée (carte, setup, derniers brews) | 1.0 (expérimental) |
| Pont subjectif ↔ objectif                                                    | **Oui**             | Le brew stocke à la fois la perception (profil 6 axes) et la mesure (ratio, temps, température, TDS si dispo, rendement calculé). Le diagnostic relie les deux avec la Brewing Control Chart révisée de UC Davis comme carte de fond                                                                                                                                                                                                                                             | 1.0                |


### Avant


| Idée                                                                    | Verdict                   | Enrichissement                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Cible                                      |
| ----------------------------------------------------------------------- | ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| Mes équipements, accessoires (WDT, Melodrip), flux                      | **Oui**                   | Feuille *Setup* : broyeurs, brewers / machine, bouilloire, balance, filtres, accessoires (annexe E). Un setup par défaut par méthode. Flux (g/s) v1 = eau ÷ temps total ; par phase dès que le timer guidé enregistre les étapes ; courbe réelle seulement avec balance BT (v2)                                                                                                                                                                                         | 1.0                                        |
| Config mouture + correspondance entre broyeurs + base de broyeurs       | **Oui, promesse modeste** | Base propre (annexe B) : modèle, type de burrs, type de réglage (clics / continu / cadran), pas fabricant en µm par cran. Attention : le « µm par clic » des fabricants est un déplacement mécanique de la meule, pas une taille de particule — il sert à convertir *proportionnellement*, pas à prédire une granulométrie. La correspondance passe donc par une calibration perso (« mon 22 clics = ton 700 µm ») et plus tard par la foule. On affiche toujours « ≈ » | 1.0 (base + saisie) · 1.1 (correspondance) |
| Onglet eau : PPM, minéraux, base d'eaux, code-barres, gouttes minérales | **Oui, dans Setup**       | Profils d'eau : *tap / filtered / bottled / recipe*. On stocke **Ca, Mg, Na, HCO₃** et le TDS — le TDS seul ne dit rien ; dureté et alcalinité font le goût. Base d'eaux FR/EU seedée depuis les étiquettes (annexe C ; Montcalm résidu sec 32 mg/L, pas 57). Produits minéraux (Third Wave Water, Lotus, Apax, Aquacode) comme « additif » avec dose. Code-barres → Open Food Facts pour identifier la marque ; la composition vient de notre table                    | 1.0 (profils + base) · 1.1 (barcode)       |
| Température de l'eau                                                    | **Existe**                | Sort de « More », devient une rangée principale avec défaut par méthode et roast level                                                                                                                                                                                                                                                                                                                                                                                  | 1.0                                        |


### Pendant


| Idée                             | Verdict            | Enrichissement                                                                                                                                                                                                                                                                                    | Cible |
| -------------------------------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- |
| Timer                            | **Existe → guidé** | Le chrono suit les étapes de la recette (bloom, pour 1, pour 2…) avec masse cible et temps cible ; « Next » manuel ; haptic `tick` existant, plus un `stepAdvance`. Animation très minimale type lotus / rosace en filets hairline qui s'ouvre au fil des étapes — un tracé, pas une illustration | 1.0   |
| Suivi de la quantité, balance BT | **Manuel en v1**   | Masse d'eau par étape saisie, dictée ou confirmée. Bluetooth (Acaia, Timemore, Felicita…) en v2 seulement si les étapes sont réellement utilisées                                                                                                                                                 | v2    |


### Après


| Idée                                                                      | Verdict              | Enrichissement                                                                                                                                                                                                                                                                                                                                                                                                                                  | Cible                  |
| ------------------------------------------------------------------------- | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| Notation aftertaste / aroma / sweetness + graphique plus complet qu'iBrew | **Oui**              | Profil optionnel 6 axes, vocabulaire aligné sur le CVA de la SCA : *Aroma · Acidity · Sweetness · Body · Bitterness · Aftertaste*, 1–5. Radar dessiné en encre sur papier, grille hairline, brew précédent en `inkMuted` superposé. Le rating 1–5 reste le chemin rapide ; les axes −/·/+ restent le *diagnostic* (« trop / juste / pas assez »). Les six axes peuvent être **dictés** (« acidité 4, sucrosité 3, corps léger, finale courte ») | 1.0                    |
| Espace texte perso                                                        | **Existe**           | Dictée ajoutée                                                                                                                                                                                                                                                                                                                                                                                                                                  | 1.0                    |
| Comparer domestique vs pro                                                | **Oui, par étapes**  | v1 : ton brew vs recette de la carte, vs référence, vs ton meilleur brew de ce café (deltas en `tag`). Pro = torréfacteur / champion : quand la communauté existe                                                                                                                                                                                                                                                                               | 1.0 (perso) · v2 (pro) |
| Corrélation équipement ↔ qualité                                          | **Capturer d'abord** | v1 : chaque brew porte son setup. 1.2 : *Insights* simples (meilleur réglage par broyeur, meilleure eau par café). Corrélations robustes : communauté                                                                                                                                                                                                                                                                                           | 1.0 → v2               |


### Capture et IA (nouveaux axes 0.2)


| Idée                                                                              | Verdict                     | Enrichissement                                                                                                                                                                                                                                                                                                        | Cible     |
| --------------------------------------------------------------------------------- | --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| Gagner du temps sans perdre en précision : scan / OCR, dictée                     | **Oui, principe de design** | Chaque champ a un chemin sans clavier : pré-rempli (setup, dernier brew, recette), scanné (carte, sachet, ticket, étiquette d'eau), dicté (brew, sensations, notes) ou importé (photo, QR, code-barres, URL partagée). Détail en §6.8                                                                                 | 1.0       |
| IA expérimentale dès la v1 (instance GPT déjà configurée)                         | **Oui, cadrée**             | L'instance existante sert côté serveur (edge functions), jamais depuis l'app. On combine avec les APIs on-device d'iOS 26 (SpeechAnalyzer pour la voix, Foundation Models pour l'extraction structurée quand l'appareil le permet). Chaque feature IA a un fallback déterministe et un badge `sparkles`. Détail en §9 | 1.0       |
| Sourcing scientifique et documentaire en annexes, vérifiable avant implémentation | **Oui**                     | Annexes A–H avec colonne *Statut*. Rien n'est seedé en base sans passer par « vérifié »                                                                                                                                                                                                                               | avant 1.0 |


---

## 5. Architecture de l'information

```
Kohi
├── Coffees ─────────── grille (inchangée) → détail carte
│     └── détail : tombstone · objet · notes · caption · SUGGESTED RECIPE · brews · pages · note
├── Recipes
│     ├── For your coffees   (suggestions pour les cartes sans brew ou mal notées)
│     ├── Reference          (16 recettes attribuées, traduites dans ton setup)
│     └── Mine               (recettes sauvegardées depuis un brew)
├── Setup (feuille, depuis Recipes et depuis le brew sheet)
│     ├── Grinders · Brewers · Kettle · Scale · Filters · Accessories
│     ├── Water profiles
│     └── Defaults per method
└── Account (List système) — + toggle « Experimental AI »
```

Règles de navigation :

- Les deux onglets sont deux mots en `catalogueLabel` dans la barre de la grille, à droite du wordmark. Actif : encre + filet 1 pt ; inactif : `inkMuted`. Pas de fond de barre.
- Le scan button n'apparaît que sur *Coffees*. *Recipes* n'a pas de bouton d'ajout : une recette naît d'un brew (« Save as recipe »).
- *Setup* s'ouvre depuis un `catalogueLabel` en tête de *Recipes* (« Setup ») et depuis la rangée « With » du brew sheet.
- Le micro (« Say it ») vit dans le brew sheet et dans la fiche d'édition, en `catalogueLabel` + glyphe `mic` ; jamais un bouton primaire.

---

## 6. Spécifications fonctionnelles

### 6.1 Coffees — la carte s'enrichit

**Édition.** Les nouveaux champs vivent dans un groupe replié **« On the bag »** sous les champs actuels, pour ne pas alourdir la feuille *New card* :


| Champ         | Contrôle                                                | Capture sans clavier                                                        |
| ------------- | ------------------------------------------------------- | --------------------------------------------------------------------------- |
| Roaster       | Texte + suggestions (entité *Roaster*, §6.2)            | OCR existant ; QR → site                                                    |
| Roast level   | Chips 5 crans + Agtron optionnel                        | OCR mots-clés (light / omni / espresso roast…)                              |
| Roasted on    | Date                                                    | OCR « Roasted on », « Torréfié le », 焙煎日, 烘焙日期                              |
| Harvest       | Texte court (« 2025/26 »)                               | OCR « Harvest », « Crop »                                                   |
| Cupping score | Nombre                                                  | OCR « 86.5 », « SCA 87 »                                                    |
| Price · Bag   | Prix + devise · chips poids                             | Scan du ticket ou de l'étiquette prix ; dictée (« quatorze euros les 250 ») |
| Lot           | Texte                                                   | OCR « Lot », « Batch »                                                      |
| Decaf         | Toggle                                                  | OCR « Decaf », « Swiss Water », « Sugarcane EA »                            |
| Bought at     | Place (MapKit) + type *Roastery / Café / Shop / Online* | Localisation courante proposée si autorisée                                 |


**Scan du sachet.** En plus de la carte, une *page* de type **Bag** (photo du sachet, avant/arrière) passe par le même flux caméra + revue, puis par l'extraction IA (vision) pour remplir les champs encore vides. Le sachet n'est pas l'objet d'archive — la carte le reste — mais il porte souvent la date de torréfaction et le lot.

**Détail.** `CaptionBlock` ajoute les rangées remplies. Prix affiché « 14 € · 250 g · 56 €/kg ». Sous les notes, une nouvelle rangée **Suggested recipe** (§6.5) avec sa provenance en `tag` (*Card · Reference · Adapted*).

**Suppressions.** Caféine (calcul, override, affichage) ; `species` hors UI.

### 6.2 Roasters

- **Entité** : `id · name · normalizedName · city · country · website · instagram · lat/lng · aliases[] · verified · createdBy`.
- **Saisie** : en tapant dans *Roaster*, suggestions depuis le cache local (nom, ville). Choisir lie la carte ; ignorer garde le texte libre.
- **Ajout** : « Add roaster » → mini-formulaire (nom, ville, pays, site, Instagram). Adresse par MapKit, comme *Place*. Dédoublonnage avant création (nom normalisé + pays, distance d'édition courte → « Did you mean… »).
- **Enrichissement (agent, §9.4)** : à la création, un agent serveur cherche site et Instagram et *propose* ; rien n'est validé sans l'utilisateur.
- **Hors ligne** : texte libre ; rapprochement au prochain sync.
- **Seed** : annexe D, une fois vérifiée. Pas de scraping de répertoires tiers : on construit notre table, la communauté la complète.
- **Vue torréfacteur (1.1)** : tap sur le nom → toutes tes cartes de ce torréfacteur, site, Instagram.

### 6.3 Setup — équipements et eau

**Équipements.** Un item = `kind · brand · model · notes · isDefaultFor[methods]`.


| Kind             | Champs spécifiques                                                                                                                                                       |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Grinder          | référence dans la base broyeurs (annexe B) ou custom, burrs (conical / flat), réglage (*clicks / stepless / dial*), plage utile pour moi (« espresso 8–12 · V60 20–26 ») |
| Brewer           | type (annexe E), filtre (marque, forme)                                                                                                                                  |
| Espresso machine | modèle, panier (g), pression si réglable                                                                                                                                 |
| Kettle           | col de cygne, contrôle de température                                                                                                                                    |
| Scale            | modèle, 0,1 g, timer intégré                                                                                                                                             |
| Accessory        | WDT, distributor, puck screen, Melodrip / Gabi, RDT (spray), dosing cup…                                                                                                 |


**Ajout par photo (expérimental).** Photo du broyeur ou de la machine → identification du modèle par vision → proposition, à confirmer. Utile pour un setup de dix objets en deux minutes.

**Broyeurs — base de référence.** `brand · model · year · burrType · burrMm · adjustmentType · stepsPerRotation · makerMicronsPerStep · rangeHint`. Utilisée pour : (a) pré-remplir les plages par méthode, (b) exprimer une recette de référence « dans tes clics » par proportionnalité, (c) demain, la correspondance entre utilisateurs, calibrée par la foule. Toujours affiché avec « ≈ ».

**Eau.** Un profil = `name · source (tap / filtered / bottled / recipe) · tds · ca · mg · na · hco3 · additive (produit + dose) · notes`. Dureté (GH) et alcalinité (KH) calculées et affichées. Une bande cible hairline sous les valeurs : TDS 75–250 mg/L (cible 150), alcalinité ~40 mg/L, pH 6,5–7,5 — la norme SCA, ni plus ni moins. Base d'eaux en bouteille (annexe C). Étiquette d'eau : scan de l'analyse imprimée sur la bouteille → OCR → Ca / Mg / Na / HCO₃ pré-remplis. Code-barres (1.1) : scan → Open Food Facts → marque + nom → rapprochement avec notre table ; si absente, formulaire pré-rempli.

**Défauts par méthode.** *Espresso → machine A + broyeur B + eau C*, *V60 → …*. Le brew sheet part de là.

### 6.4 Recipes

**Recette** = `method · dose · water (ou beverage) · ratio · temperature · grind (valeur dans ton broyeur + proxy µm) · steps[] · totalTime · source (card / reference / mine / adapted) · attribution · notes`.

**Step** = `t · action (bloom / pour / stir / press / swirl / drawdown / steep / release) · targetMass · note`.

Trois sections :

1. **For your coffees.** Cartes récentes sans brew, ou dont le dernier brew est ≤ 2/5, avec leur recette suggérée. Tap → brew pré-rempli.
2. **Reference.** 16 recettes attribuées, hors ligne (annexe A), chacune « In your terms » (mouture proposée dans tes clics, eau par défaut). Filtre par méthode en chips.
3. **Mine.** Recettes sauvegardées depuis un brew (« Save as recipe »). Applicables à n'importe quelle carte.

### 6.5 Brew — avant, pendant, après

**Avant.** Le brew sheet gagne trois rangées en tête :

- **Recipe** : *Card recipe · Suggested · Reference · Last brew · Mine* → pré-remplit tout.
- **With** : le setup par défaut de la méthode, modifiable (chips broyeur / brewer).
- **Water** : profil par défaut, modifiable. Température devient rangée principale.

**Recette suggérée — logique.**

1. Si la carte a une recette imprimée complète → *Card*, telle quelle.
2. Sinon, recette de référence pour la méthode → *Reference*, ajustée par des règles (annexe G) :
  - roast level : *Light* → eau plus chaude et ratio légèrement plus long ; *Dark* → eau moins chaude, ratio plus court ;
  - decaf → un cran plus grossier, température un peu plus basse ;
  - fraîcheur : < 5 jours après torréfaction → bloom plus long, note « dégazage » ;
  - broyeur : conversion proportionnelle → tes clics, à partir de ta plage déclarée.
3. Si tu as déjà bien noté un café proche (même process, même roast level, même méthode) → *Adapted from your best brew of X*.
4. **Expérimental** : le modèle propose une variante en tenant compte de tout ce qui précède *et* des notes de dégustation de la carte, avec un « pourquoi » en une phrase. Toujours sous la recette à règles, jamais à sa place.

La provenance est toujours visible.

**Pendant — timer guidé.** Si la recette a des étapes : chaque étape affiche action, masse cible, temps cible ; « Next » avance (haptic `stepAdvance`), le temps réel de chaque étape est enregistré. Sans étapes : le chrono actuel. Flux moyen calculé en fin (`water ÷ time`, en g/s) ; flux par étape si étapes. Commande vocale minimale pendant l'extraction (« next », « stop ») via reconnaissance on-device, mains occupées.

**Après.**

- **Rating 1–5** (inchangé, chemin rapide).
- **Taste** (nouveau, replié) : six axes 1–5 — *Aroma · Acidity · Sweetness · Body · Bitterness · Aftertaste* — plus chips de saveurs (vocabulaire de la roue SCA, réduit à ~40 termes). Radar encre sur papier ; brew précédent du même café superposé en `inkMuted`. Dictable en une phrase.
- **Diagnostic** (les axes −/·/+ actuels, renommés « Too little / Right / Too much » pour *Acidity · Bitterness · Body*).
- **Next time** : à partir du diagnostic et des mesures, une seule proposition de changement avec sa raison (table complète en annexe G). « Use next time » crée un brouillon de brew avec ce seul changement. Une variable à la fois.
- **Compare** : deltas vs recette de la carte / référence / meilleur brew de ce café, en `tag` (« −2 clicks · +0,5 g · −10 s »).

### 6.6 Assistant (« Ask », expérimental en 1.0)

- Bouton « Ask » sur une carte ou un brew, badge `sparkles`. Contexte envoyé : carte, setup, eau, 3 derniers brews, question.
- Réponse ancrée sur la **base de connaissances curée** (annexe F ; résumés + liens, jamais de texte intégral). Chaque réponse cite ses sources et distingue *ce qui est mesuré* de *ce que font les pros*.
- **Garde-fous** : si la question sort de la base, l'assistant le dit. Pas de recette inventée sans provenance. Coût plafonné par utilisateur ; réponses cachées par (question normalisée, contexte).

### 6.7 Insights (1.2)

Trois rangées catalogue, pas un dashboard : *Best brew* par café ; *Your sweet spot* par broyeur (réglage le mieux noté par méthode) ; *Water* (eau la mieux notée par process). Suffisant pour voir une corrélation équipement ↔ résultat sans promettre une statistique.

### 6.8 Capture sans friction

Principe : **chaque champ a un chemin sans clavier**, et le clavier reste disponible. Quatre chemins, dans cet ordre de préférence.


| Chemin         | Quoi                                                                                                      | Comment                                                                                                                                                                                                                               |
| -------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Pré-rempli** | Setup, eau, recette, dernier brew, date, lieu                                                             | Défauts par méthode ; « Save suffit si rien n'a changé » reste la règle                                                                                                                                                               |
| **Scanné**     | Carte, sachet, ticket de caisse, étiquette d'eau, cadran du broyeur                                       | Même flux caméra + revue ; OCR Vision on-device puis extraction IA pour les champs vides                                                                                                                                              |
| **Dicté**      | Brew complet, sensations, diagnostic, notes, correction d'un champ                                        | « Say it » → transcription on-device (iOS 26 SpeechAnalyzer, repli SFSpeechRecognizer) → extraction structurée → champs vides remplis, champs parsés surlignés brièvement (`paperShade`) pour vérification ; rien n'écrase une saisie |
| **Importé**    | QR / code-barres, photo depuis la photothèque, URL partagée depuis Safari (fiche produit du torréfacteur) | Share Extension : une URL de fiche produit partagée dans Kohi crée un brouillon de carte (Open Graph + JSON-LD, déjà en place)                                                                                                        |


**Dictée — ce que l'app comprend.** Une phrase suffit pour un brew : « V60, quinze grammes, deux cent cinquante d'eau, quatre-vingt-quatorze degrés, vingt-deux clics, deux minutes quarante-cinq, plutôt bon, un peu acide ». Le modèle mappe vers `method · dose · water · temperature · grind · time · rating · diagnostic`. Les nombres ambigus (« vingt-deux ») sont attribués par contexte (clics vs grammes) et confirmés visuellement. Langues 1.0 : FR, EN. Si l'extraction échoue, la transcription brute va dans *Notes* — rien n'est perdu.

**Raccourcis système.** App Intents : « Log a brew in Kohi » (ouvre le brew sheet du dernier café, micro actif), « Start a V60 » (timer guidé de la recette par défaut). Exposés à Siri, à l'Action button et au Control Center. Widget minimal : le café du moment + « Log a brew ».

**Ce que la capture ne fait pas.** Pas de saisie « magique » silencieuse : ce qui a été deviné est visible et annulable. Pas d'audio conservé : la transcription est traitée puis jetée.

---

## 7. Modèle de données — deltas


| Entité                            | Nouveau / modifié                                                                                                                                                                                                     | Sync             |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| `Card`                            | + `roasterId?`, `roastLevel`, `agtron?`, `roastedOn?`, `harvest?`, `cuppingScore?`, `price?`, `currency?`, `bagWeightG?`, `lot?`, `isDecaf` (exposé), `placeType?`, `suggestedRecipeId?` ; − caféine                  | oui              |
| `Attachment`                      | + rôles `bag` (photo du sachet) et `receipt`                                                                                                                                                                          | oui              |
| `Roaster`                         | nouvelle, partagée (table publique + `createdBy`)                                                                                                                                                                     | oui, cache local |
| `Equipment`                       | nouvelle, perso                                                                                                                                                                                                       | oui              |
| `GrinderModel`                    | nouvelle, référence publique (annexe B)                                                                                                                                                                               | cache local      |
| `WaterProfile`                    | nouvelle, perso                                                                                                                                                                                                       | oui              |
| `BottledWater` / `MineralProduct` | nouvelles, référence publique (annexe C)                                                                                                                                                                              | cache local      |
| `Recipe` / `RecipeStep`           | nouvelles ; `Reference` embarquées en bundle (annexe A)                                                                                                                                                               | oui (Mine)       |
| `Brew`                            | + `recipeId?`, `equipmentIds[]`, `waterProfileId?`, `steps[] (réels)`, `flowGs?`, `taste{6 axes}`, `flavors[]`, `nextTimeSuggestion?`, `captureSource (typed / dictated / scanned / prefilled)` par champ ; − caféine | oui              |
| `KnowledgeEntry`                  | nouvelle, serveur uniquement (annexe F)                                                                                                                                                                               | —                |
| `AIEvent`                         | nouvelle, serveur : feature, modèle, tokens, latence, acceptée ou non — pour piloter le coût et la qualité                                                                                                            | —                |


Principe conservé : `cards.json` reste la source de vérité locale, décodage tolérant, sync par outbox. Les tables de référence (roasters, broyeurs, eaux, recettes) sont des caches en lecture avec un `updatedAt` global ; leur absence ne bloque rien. `captureSource` est ce qui permettra de mesurer O4.

---

## 8. Données de référence — sourcing et vérification

Toutes les données de référence sont listées en annexe avec un statut. Règle : **une ligne « à vérifier » n'entre pas en base**. Le plan de vérification est en annexe H.


| Jeu de données                     | Annexe | Source v1                                                                         | Note                                                                                  |
| ---------------------------------- | ------ | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Recettes de référence              | A      | Recettes publiées par leurs auteurs, réécrites en paramètres + étapes, attribuées | Une recette est une liste de paramètres ; on cite l'auteur, on ne copie pas son texte |
| Broyeurs                           | B      | Fiches fabricants (pas mécanique en µm), plages indicatives issues de l'usage     | Le pas fabricant ≠ taille de particule ; on annonce cette incertitude                 |
| Eaux et minéraux                   | C      | Étiquettes et sites des marques ; fiches fabricants des concentrés                | Open Food Facts pour identifier par code-barres ; composition maintenue chez nous     |
| Torréfacteurs                      | D      | Ton archive, sélections éditoriales 2025–2026, saisie manuelle                    | Contributions utilisateurs avec `verified`                                            |
| Équipements (hors broyeurs)        | E      | Catalogues fabricants                                                             | Liste ouverte, custom toujours possible                                               |
| Base de connaissances              | F      | Papiers évalués par les pairs, standards SCA, articles de référence               | Résumés + liens ; pas de texte intégral en base                                       |
| Tables de correspondance et règles | G      | Standards, papiers, pratique documentée                                           | Chaque règle porte son niveau de preuve                                               |


---

## 9. IA — expérimentale dès la 1.0

### 9.1 Principes

1. **Ne remplit que le vide.** Même règle que `card-vision` : l'IA propose, n'écrase jamais ce que l'utilisateur a saisi.
2. **Règles d'abord, modèle ensuite.** Tout ce qui a une réponse déterministe (paramètres d'une recette, diagnostic, conversions) passe par des règles testables et hors ligne. Le modèle remplit, extrait, adapte, explique.
3. **Visible et révocable.** Badge `sparkles` sur tout ce qui vient d'un modèle ; ce qui a été deviné est surligné puis annulable ; toggle « Experimental AI » dans Compte.
4. **On-device quand c'est possible, serveur quand c'est nécessaire.** Voix et petites extractions sur l'appareil ; vision lourde, adaptation de recette, « Ask » et agents côté serveur.
5. **Clés côté serveur.** L'instance GPT déjà configurée est appelée depuis des edge functions Supabase, jamais depuis l'app. Sorties structurées (JSON validé) avant affichage.
6. **Mesuré.** Chaque appel écrit un `AIEvent` (feature, modèle, tokens, latence, accepté ou non). C'est ce qui décide en 1.1 de ce qui reste, de ce qui passe on-device et de ce qui disparaît.

### 9.2 Moteurs


| Moteur                             | Où                                     | Sert à                                                                                                                                                                                   | Disponibilité                                   |
| ---------------------------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| Vision (Apple)                     | on-device                              | OCR documentaire, codes-barres, détection de carte — existant                                                                                                                            | tous iPhone                                     |
| SpeechAnalyzer / SpeechTranscriber | on-device, iOS 26                      | dictée du brew, des sensations, des notes ; commandes « next / stop »                                                                                                                    | iOS 26 ; repli `SFSpeechRecognizer` avant       |
| Foundation Models (Apple)          | on-device, iOS 26 + Apple Intelligence | extraction structurée légère (phrase dictée → champs de brew) via génération guidée                                                                                                      | iPhone 15 Pro et suivants ; repli serveur sinon |
| GPT (instance existante)           | serveur, edge functions                | second avis OCR (`card-vision`, existant), extraction sachet / ticket / étiquette d'eau, extraction structurée quand l'on-device n'est pas dispo, adaptation de recette, « Ask », agents | tous, si Supabase configuré                     |
| Génération d'image                 | serveur                                | posters (`card-poster`, existant)                                                                                                                                                        | inchangé                                        |


Le choix on-device vs serveur se fait à l'exécution : on-device si le modèle et la langue sont disponibles, sinon serveur, sinon règle. L'utilisateur ne choisit pas le moteur ; il voit seulement le badge.

### 9.3 Fonctions IA de la 1.0


| Fonction                               | Entrée                           | Sortie                                                   | Fallback                       | Mesure                                  |
| -------------------------------------- | -------------------------------- | -------------------------------------------------------- | ------------------------------ | --------------------------------------- |
| Dictée → brew                          | phrase                           | champs de brew vides remplis                             | transcription brute dans Notes | % champs acceptés sans correction       |
| Dictée → taste / diagnostic            | phrase                           | 6 axes + 3 axes −/·/+                                    | dots manuels                   | idem                                    |
| Scan sachet / ticket / étiquette d'eau | image                            | champs vides (date de torréfaction, lot, prix, minéraux) | saisie                         | idem                                    |
| Recette adaptée                        | carte + setup + eau + historique | variante de la recette à règles + « pourquoi »           | recette à règles seule         | brews lancés depuis la variante, rating |
| « Ask »                                | question + contexte              | réponse citée                                            | « pas dans ma base »           | questions / semaine, utilité (pouce)    |
| Identification d'équipement par photo  | image                            | modèle proposé                                           | saisie                         | taux de confirmation                    |


### 9.4 Agents (serveur, expérimental)

Des tâches planifiées, pas des conversations. Chaque agent *propose* ; un humain (toi en 1.0, l'utilisateur ou un modérateur ensuite) valide.


| Agent                       | Déclencheur             | Fait                                                                                       | Sortie                                        |
| --------------------------- | ----------------------- | ------------------------------------------------------------------------------------------ | --------------------------------------------- |
| Enrichissement torréfacteur | création d'un `Roaster` | cherche site, Instagram, ville                                                             | proposition dans la fiche, `verified = false` |
| Qualité des données         | hebdo                   | doublons torréfacteurs / eaux, champs incohérents (ratio impossible, température > 100 °C) | liste à traiter                               |
| Curateur de connaissances   | ajout d'une source      | résumé + citation + niveau de preuve                                                       | entrée `KnowledgeEntry` en attente            |
| Coach (1.2)                 | tous les N brews        | motifs dans tes brews (réglage récurrent des bons brews, eau, méthode)                     | brouillon d'*Insights*                        |


### 9.5 Ce que ça coûte, ce qu'on cadre

- Voix et extraction légère : gratuits si on-device. Serveur : quelques centimes par jour d'usage intensif ; plafond par utilisateur, cache par (entrée normalisée, contexte).
- Latence cible : dictée < 1,5 s après fin de phrase ; extraction image < 4 s ; recette adaptée < 3 s ; « Ask » < 6 s. Au-delà, on montre la règle d'abord et l'IA arrive après (shimmer, comme l'OCR).
- Confidentialité : pas d'audio conservé ; images envoyées au serveur uniquement pour l'extraction, non stockées hors de l'archive de l'utilisateur ; lieu jamais envoyé au modèle.
- Sans Supabase : voix on-device, OCR Vision, règles, recettes de référence et Setup fonctionnent. Seuls le serveur et les agents manquent.

---

## 10. Design — ce qui change, ce qui ne change pas

**Ne change pas** : paper, encre, Angusta, grammaire catalogue, un seul bouton sur la grille, light only, tokens dans `Palette` / `Typography` / `Motion` / `Haptic`.

**Nouveaux composants d'archive** (tous à partir de la grammaire : label catalogue, valeur SF, filet hairline, fond paper) :


| Composant        | Description                                                                                                                                                                      |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CatalogueTabs`  | Deux `catalogueLabel` (« COFFEES » · « RECIPES »), filet 1 pt sous l'actif, animation `quick`                                                                                    |
| `RecipeRow`      | Rangée `BrewList`-like : méthode · ratio · temp · temps · provenance en `tag` · action « Use »                                                                                   |
| `SetupRow`       | Rangée label / valeur avec chips (broyeur, brewer, eau)                                                                                                                          |
| `TargetBand`     | Filet hairline avec un segment encre pour la plage cible (eau) ; pas de couleur                                                                                                  |
| `StepTimer`      | Chrono existant + ligne d'étape (action · cible · « Next ») + rosace : un tracé hairline dont un pétale passe en encre à chaque étape ; spring `snappy` ; jamais plus d'un tracé |
| `TasteRadar`     | Hexagone hairline, tracé encre 1 pt, brew précédent `inkMuted` ; lecture seule en détail, édition par dots 22 pt                                                                 |
| `SayItLabel`     | `catalogueLabel` « SAY IT » + `mic` 10 pt ; en écoute : le label devient « LISTENING », un filet hairline pulse en `gentle` ; pas de forme d'onde                                |
| `GuessHighlight` | Fond `paperShade` de 1,1 s sur un champ rempli par dictée ou extraction, puis disparition ; tap pendant la fenêtre = annuler                                                     |


**Haptics** : + `stepAdvance` (impact light), + `listening` (selection, au début et à la fin de l'écoute). Le reste réutilise `tap`, `tick`, `saved`.

**Iconographie** : + `mic` 10 pt (Say it), `sparkles` existant pour tout ce qui vient d'un modèle.

**Copy** (anglais, court) : « Recipes », « Setup », « On the bag », « Roasted on », « Bought at », « With », « Suggested recipe », « In your terms », « Save as recipe », « Next time: grind finer », « Ask », « Say it », « Listening », « Heard: … » (transcription brute en `subtitle` si l'extraction échoue).

**Ce qui reste hors grammaire** : `AccountSheet`, et rien d'autre.

---

## 11. Préparer la communauté sans la construire

- **Entités normalisées** dès maintenant : roaster, lieu typé, modèle de broyeur, eau, méthode, recette. Le texte libre reste possible mais devient l'exception.
- **Identifiants stables** pour cartes, recettes et brews (déjà des UUID).
- **Un drapeau `shareable`** sur brew et recette, `false` par défaut ; rien n'est publié en v1, mais le schéma existe.
- **Séparation perso / public** dans Supabase : tables publiques en lecture (roasters, broyeurs, eaux, recettes de référence), tables perso sous RLS (existant).
- **Anonymisation par construction** : un brew partagé demain expose setup + paramètres + profil, jamais le lieu précis ni l'identité.
- **Calibration collective** : les couples (broyeur, réglage, méthode, rating) sont ce qui permettra une correspondance entre broyeurs meilleure que le pas fabricant.

---

## 12. Roadmap et priorisation


| Release                        | Contenu                                                                                                                                                                                                                                                                                                                                                                         | Pourquoi dans cet ordre                                                                                                             |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **1.0 — Fondations + capture** | Onglets · Roaster · champs « On the bag » · retrait caféine · Setup (équipements + eau) · 16 recettes de référence · brew avant/pendant/après (recipe, with, water, timer guidé, taste, diagnostic à règles, next time, compare) · **dictée on-device** · **scan sachet / ticket / étiquette d'eau** · **recette adaptée et « Ask » en expérimental** · App Intents · `AIEvent` | Tout ce qui rend un brew comparable, un premier brew moins hasardeux et la saisie rare ; l'IA entre marquée, mesurée, avec fallback |
| **1.1 — Ajustement**           | Correspondance broyeurs (calibration perso) · code-barres eau · vue torréfacteur · biais de goût dans les suggestions · arbitrage on-device / serveur d'après `AIEvent`                                                                                                                                                                                                         | S'appuie sur des brews déjà structurés et sur trois mois de mesures IA                                                              |
| **1.2 — Boucle**               | Insights · agent Coach · « Save as recipe » enrichi                                                                                                                                                                                                                                                                                                                             | Nécessite quelques dizaines de brews pour avoir du sens                                                                             |
| **v2 — Communauté**            | Partage opt-in, benchmark pro, calibration collective, balance BT si traction                                                                                                                                                                                                                                                                                                   | Hors PRD                                                                                                                            |


**Prérequis 1.0** : annexes A–G passées en « vérifié » (plan en annexe H).

MoSCoW 1.0 : *Must* = onglets, Roaster, roast level, roasted on, Setup broyeur + eau, recettes de référence, brew avec recipe/with/water, taste + diagnostic + next time, dictée du brew, `AIEvent`. *Should* = prix, lot, cupping score, timer guidé par étapes + rosace, compare, scan sachet, recette adaptée, Ask. *Could* = TargetBand eau, Agtron, harvest, identification d'équipement par photo, Share Extension. *Won't* = BT, insights, communauté.

---

## 13. Métriques

Usage perso (v1) :

- Part des cartes avec torréfacteur lié (cible 100 %).
- Part des cartes avec ≥ 1 brew (cible 80 %) ; médiane du temps pour logger un brew (< 45 s).
- Part des champs de brew remplis sans clavier, par `captureSource` (cible ≥ 70 %).
- Part des brews partis d'une recette (carte / référence / suggérée / adaptée).
- Δ rating entre le brew n°1 et le meilleur brew d'un café (cible : positif sur > 60 % des cafés).
- Part des « Next time » acceptés puis brassés.
- IA : taux d'acceptation sans correction par fonction ; coût par utilisateur actif ; latence p50 / p95.

Produit (quand ouvert) : rétention J7 / J30 des brasseurs vs collectionneurs ; nombre de roasters / eaux contribués et vérifiés.

---

## 14. Risques et questions ouvertes


| Risque / question                                       | Position proposée                                                                                                                                                                    |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Tension local-first vs features cloud (roasters, IA)    | Collection = 100 % locale, toujours. Intelligence = dégradée sans cloud, jamais absente (référence + règles embarquées, voix on-device)                                              |
| Fatigue de saisie                                       | O4 mesuré par `captureSource` ; rating seul reste le chemin rapide ; *Taste* replié ; dictée en une phrase                                                                           |
| Dictée : erreurs de mapping (22 clics vs 22 g)          | Attribution par contexte + surlignage + annulation ; transcription brute conservée dans Notes en cas d'échec                                                                         |
| Fausse précision (µm, correspondance broyeurs, flux)    | « ≈ » partout ; pas fabricant utilisé pour la proportionnalité seulement ; calibration perso avant correspondance                                                                    |
| Base scientifique plus mince que l'ambition             | La base de connaissances liste ce qui est mesuré ; l'assistant admet les trous. Les techniques popularisées par des baristas ou créateurs sont étiquetées *pratique*, pas *résultat* |
| Dérive IA (hallucination, coût, latence)                | Règles en filet, badge, `AIEvent`, plafond, cache ; toute fonction IA peut être coupée par feature flag serveur sans release                                                         |
| Dépendance iOS 26 / Apple Intelligence pour l'on-device | Kohi vise déjà iOS 26 (zoom transition, glass). Repli serveur pour les appareils sans Apple Intelligence                                                                             |
| Nom des onglets : *Recipes* ou *Brews* ?                | *Recipes* dit l'intention (aller plus loin) ; *Brews* dit la trace. Recommandation : **Recipes**, les brews restant sur la carte                                                     |
| Où vit Setup ?                                          | Feuille depuis Recipes et depuis le brew ; pas d'onglet. À valider en prototype                                                                                                      |
| Données de lieu et RGPD                                 | `Bought at` reste perso ; jamais envoyé au modèle ni exporté en clair dans une future couche communautaire                                                                           |
| Torréfacteurs : qualité de la base contributive         | `verified` + dédoublonnage + agent d'enrichissement ; un torréfacteur non vérifié n'est visible que par son créateur jusqu'à validation (1.1)                                        |
| Droits sur les recettes de référence                    | Les paramètres d'une recette ne sont pas protégeables ; le texte et la vidéo de l'auteur le sont. On réécrit, on attribue, on lie                                                    |


---

## 15. Sources consultées

- iBrewCoffee — App Store et site : [https://apps.apple.com/us/app/ibrewcoffee-coffee-journal/id1523175532](https://apps.apple.com/us/app/ibrewcoffee-coffee-journal/id1523175532) · [https://ibrew.coffee/](https://ibrew.coffee/)
- Beanconqueror — README : [https://github.com/graphefruit/Beanconqueror](https://github.com/graphefruit/Beanconqueror)
- Honest Coffee Guide — grind size chart : [https://honestcoffeeguide.com/coffee-grind-size-chart/](https://honestcoffeeguide.com/coffee-grind-size-chart/) · guide 1Zpresso (pourquoi le µm/clic fabricant est trompeur) : [https://honestcoffeeguide.com/1zpresso-comparison-guide/](https://honestcoffeeguide.com/1zpresso-comparison-guide/)
- Beean — convertisseur de réglages entre broyeurs : [https://beeancoffee.com/grinder-setting-converter/](https://beeancoffee.com/grinder-setting-converter/)
- Coffee Chronicler — base de broyeurs crowdsourcée : [https://coffeechronicler.com/grind-size-chart/](https://coffeechronicler.com/grind-size-chart/)
- 1Zpresso — gamme et pas par clic : [https://1zpresso.coffee/grinder/](https://1zpresso.coffee/grinder/) · [https://1zpresso.coffee/k-ultra/](https://1zpresso.coffee/k-ultra/) · [https://1zpresso.coffee/j-ultra/](https://1zpresso.coffee/j-ultra/)
- KINGrinder K6 (16 µm/clic, 60 clics/tour) : [https://thebasicbarista.com/en-us/blogs/reviews/king-grinder-k6-review](https://thebasicbarista.com/en-us/blogs/reviews/king-grinder-k6-review)
- SCAA/SCA — standard eau : [https://www.urbansaqua.com/wp-content/uploads/2023/09/www.urbansaqua.com-robust-ro-drinking-water-systems-water-standards.pdf](https://www.urbansaqua.com/wp-content/uploads/2023/09/www.urbansaqua.com-robust-ro-drinking-water-systems-water-standards.pdf)
- Montcalm — composition : [https://www.montcalm.fr/vertus/](https://www.montcalm.fr/vertus/) · [https://www.relaisbio.fr/fr/accueil/24624-eau-minerale-15l-montcalm-3435230150213.html](https://www.relaisbio.fr/fr/accueil/24624-eau-minerale-15l-montcalm-3435230150213.html)
- Coffeediag — Mont Roucous vs Volvic : [https://coffeediag.com/mont-roucous-ou-volvic-pour-sa-machine-a-cafe/](https://coffeediag.com/mont-roucous-ou-volvic-pour-sa-machine-a-cafe/)
- Third Wave Water — composition des profils : [https://support.thirdwavewater.com/en-US/what-is-in-third-wave-water-76575](https://support.thirdwavewater.com/en-US/what-is-in-third-wave-water-76575)
- Barista Hustle — DIY water recipes redux : [https://www.baristahustle.com/diy-water-recipes-redux/](https://www.baristahustle.com/diy-water-recipes-redux/)
- Coffee ad Astra — Water for coffee extraction : [https://coffeeadastra.com/2018/12/16/water-for-coffee-extraction/](https://coffeeadastra.com/2018/12/16/water-for-coffee-extraction/)
- Basic Barista — Apax vs Lotus : [https://thebasicbarista.com/en-us/blogs/reviews/apax-vs-lotus-water-minerals](https://thebasicbarista.com/en-us/blogs/reviews/apax-vs-lotus-water-minerals)
- Méndez Harper et al., Matter 2023 : [https://www.cell.com/matter/fulltext/S2590-2385(23)00568-4](https://www.cell.com/matter/fulltext/S2590-2385(23)00568-4)
- Méndez Harper, Hendon et al., stratégies anti-statique (arXiv 2312.03103, cite Cameron 2020 et Uman 2016) : [https://arxiv.org/html/2312.03103](https://arxiv.org/html/2312.03103)
- Guinard, Frost, Batali et al., J. Food Sci. 2023 : [https://pubmed.ncbi.nlm.nih.gov/36988107/](https://pubmed.ncbi.nlm.nih.gov/36988107/)
- SCA — Coffee Value Assessment : [https://sca.coffee/value-assessment](https://sca.coffee/value-assessment) · SCA-104 : [https://static1.squarespace.com/static/584f6bbef5e23149e5522201/t/671f8752d46f770772095ca4/1730119506964/AW_SCA-104_Affective-Assessment_Sept2024_Secured.pdf](https://static1.squarespace.com/static/584f6bbef5e23149e5522201/t/671f8752d46f770772095ca4/1730119506964/AW_SCA-104_Affective-Assessment_Sept2024_Secured.pdf)
- Open Food Facts — API : [https://openfoodfacts.github.io/openfoodfacts-server/api/tutorial-off-api/](https://openfoodfacts.github.io/openfoodfacts-server/api/tutorial-off-api/)
- Hoffmann V60 (Hario Europe) : [https://www.hario-europe.com/blogs/hario-community/v60-ambassadors-james-hoffmann](https://www.hario-europe.com/blogs/hario-community/v60-ambassadors-james-hoffmann) · Honest Coffee Guide : [https://honestcoffeeguide.com/brew-recipes/james-hoffmann-v60/](https://honestcoffeeguide.com/brew-recipes/james-hoffmann-v60/)
- iOS 26 SpeechAnalyzer : [https://picovoice.ai/blog/ios-speech-recognition/](https://picovoice.ai/blog/ios-speech-recognition/) · [https://dev.to/simple_memo/ios-26s-speechanalyzer-on-a-live-mic-the-5-things-the-docs-dont-tell-you-2ng5](https://dev.to/simple_memo/ios-26s-speechanalyzer-on-a-live-mic-the-5-things-the-docs-dont-tell-you-2ng5)
- Torréfacteurs — sélections : [https://grainnoble.fr/blog/top-10-torrefacteurs-france/](https://grainnoble.fr/blog/top-10-torrefacteurs-france/) · [https://filtre.cafe/journal/torrefacteurs-francais](https://filtre.cafe/journal/torrefacteurs-francais) · [https://fr.gaultmillau.com/fr/ile-de-france/paris/torrefacteurs](https://fr.gaultmillau.com/fr/ile-de-france/paris/torrefacteurs) · [https://beeancoffee.com/city-guides/best-european-specialty-coffee-roasters-of-2026/](https://beeancoffee.com/city-guides/best-european-specialty-coffee-roasters-of-2026/) · [https://www.timeout.com/news/this-austrian-coffee-shop-is-officially-the-best-in-europe-and-third-best-in-the-world-022525](https://www.timeout.com/news/this-austrian-coffee-shop-is-officially-the-best-in-europe-and-third-best-in-the-world-022525)

---

# Annexes — données à vérifier avant implémentation

Convention de statut :

- **vérifié** : lu sur une source primaire (fabricant, auteur, papier, standard) pendant la rédaction ; à re-contrôler une fois avant seed.
- **partiel** : une partie des valeurs vient d'une source primaire, le reste d'une source secondaire ou de mémoire.
- **à vérifier** : de mémoire ou de source secondaire ; ne pas seeder sans contrôle.
- **pratique** : convention d'usage documentée (barista, auteur), pas un résultat mesuré. Reste « à vérifier » quant aux chiffres.

Rien n'entre dans une table de référence tant que la ligne n'est pas *vérifié*. Le plan de contrôle est en annexe H.

## Annexe A — Recettes de référence (16)

Format cible : `method · dose · water/beverage · ratio · temperature · grind (proxy) · steps[] · totalTime · attribution · sourceUrl`. Les étapes ci-dessous sont des paramètres réécrits, pas le texte des auteurs.


| #   | Recette                       | Paramètres                                                                                                          | Étapes                                                                                                                                                                                                                    | Attribution                           | Statut                                                                          |
| --- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------- |
| A1  | V60 « Ultimate »              | 30 g / 500 g (1:16,7) · eau juste sous ébullition (light) ; 93–95 °C pour plus torréfié · mouture medium-fine       | 0:00 bloom 60 g + swirl · 0:45 verser jusqu'à 300 g (atteint à 1:15) · 1:15 verser jusqu'à 500 g (atteint à 1:45) · 1 tour de cuillère dans chaque sens + swirl · drawdown, fin ≈ 3:30                                    | James Hoffmann (2019)                 | vérifié (Hario Europe, Honest Coffee Guide)                                     |
| A2  | V60 « 1 cup »                 | 15 g / 250 g (1:16,7) · eau bouillante pour light · medium-fine                                                     | 0:00 bloom 50 g + swirl · 0:45 verser 100 g en ~15 s (150 g) · 1:00 → 4 versements de 25 g toutes les 10 s (250 g) · swirl · fin ≈ 3:00                                                                                   | James Hoffmann (2022)                 | partiel (dose, eau, temps total vérifiés ; découpage des versements à vérifier) |
| A3  | V60 « 4:6 »                   | 20 g / 300 g (1:15) · ~92 °C · mouture coarse                                                                       | 5 × 60 g à 0:00 · 0:45 · 1:30 · 2:15 · 3:00 · fin ≈ 3:30. Les 2 premiers versements (40 %) règlent sucrosité / acidité ; les 3 suivants (60 %) règlent la force (3 versements = équilibré, 2 = plus fort, 1 = plus léger) | Tetsu Kasuya (WBrC 2016)              | partiel (principe vérifié ; température et sens des ajustements à vérifier)     |
| A4  | Hario Switch (hybride)        | 20 g / 280 g (1:14) · ~90 °C · medium                                                                               | 0:00 switch ouvert, 60 g · 0:30 ouvert, 60 g · 1:15 switch fermé, 160 g · 1:45 ouvrir · fin ≈ 3:00                                                                                                                        | Tetsu Kasuya                          | à vérifier                                                                      |
| A5  | Kalita Wave 185 / fond plat   | 20 g / 320 g (1:16) · 93 °C · medium                                                                                | 0:00 bloom 50 g · 0:30 · 1:15 · 2:00 trois versements de 90 g · fin ≈ 3:15                                                                                                                                                | pratique générique                    | pratique                                                                        |
| A6  | Chemex 6 tasses               | 40 g / 640 g (1:16) · 94 °C · medium-coarse                                                                         | 0:00 bloom 100 g · 0:45 verser jusqu'à 400 g (1:45) · jusqu'à 640 g (3:00) · fin ≈ 4:30–5:00                                                                                                                              | pratique générique                    | pratique                                                                        |
| A7  | AeroPress « Ultimate »        | 11 g / 200 g (1:18) · ~100 °C pour light, 85–90 °C pour dark · fine-medium                                          | droit, sans bloom, sans agitation · 0:00 verser 200 g, poser le piston · 2:00 swirl léger · 2:30 presser doucement ≈ 30 s                                                                                                 | James Hoffmann (2023)                 | partiel (grandes lignes vérifiées ; températures à vérifier)                    |
| A8  | AeroPress inversé (générique) | 14 g / 200 g (1:14) · 90 °C · medium-fine                                                                           | inversé · 0:00 verser tout · remuer 3× · 1:30 filtre + retourner · presser ≈ 30 s                                                                                                                                         | pratique générique                    | pratique                                                                        |
| A9  | Espresso standard             | 18 g in / 36 g out (1:2) · 25–30 s · 92–94 °C · ~9 bar                                                              | régler la mouture par le temps, puis par le goût : acide → plus fin / plus long ; amer → plus grossier / plus court                                                                                                       | convention (Barista Hustle, Hoffmann) | pratique (convention stable)                                                    |
| A10 | Espresso light / « turbo »    | 18 g / 45–54 g (1:2,5–1:3) · 15–25 s · 94–96 °C · 6 bar si réglable                                                 | mouture plus grossière que A9 ; même logique de réglage                                                                                                                                                                   | pratique (Rao, Barista Hustle)        | pratique                                                                        |
| A11 | Moka (Bialetti 3 tasses)      | panier rempli à niveau sans tasser (≈ 15–17 g) · eau préchauffée jusqu'au dessous de la valve · mouture fine (moka) | feu moyen-doux, couvercle ouvert · retirer au premier gargouillis · refroidir la base sous l'eau                                                                                                                          | James Hoffmann                        | partiel (méthode vérifiée ; dose à vérifier)                                    |
| A12 | French press                  | 30 g / 500 g (1:16,7) · eau juste sous ébullition · medium-coarse                                                   | 0:00 verser tout · 4:00 casser la croûte, écumer · attendre 5–8 min · verser lentement sans enfoncer le piston (ou juste sous la surface)                                                                                 | James Hoffmann                        | vérifié                                                                         |
| A13 | Clever Dripper                | 20 g / 320 g (1:16) · 93 °C · medium                                                                                | 0:00 verser tout, remuer · 2:00 remuer, couvrir · 2:30–3:00 relâcher · fin ≈ 4:00                                                                                                                                         | pratique générique                    | pratique                                                                        |
| A14 | Cold brew (concentré)         | 1:8 (ex. 60 g / 480 g) · eau ambiante · coarse                                                                      | 12–16 h à température ambiante ou 16–24 h au réfrigérateur · filtrer · diluer ~1:1                                                                                                                                        | pratique générique                    | pratique                                                                        |
| A15 | Cupping SCA                   | 8,25 g / 150 mL (1:18,2) · 93 °C · medium-coarse                                                                    | 0:00 verser · 4:00 casser la croûte, écumer · goûter en refroidissant à partir de ~10 min                                                                                                                                 | SCA cupping protocol                  | vérifié (protocole historique ; vérifier la version CVA 2024)                   |
| A16 | Batch / drip (Moccamaster)    | 55–60 g/L (ex. 60 g / 1 L) · 92–96 °C · medium                                                                      | selon la machine ; bloom manuel 30 s si possible                                                                                                                                                                          | SCA Golden Cup (55 g/L ± 10 %)        | partiel (ratio vérifié ; température à vérifier)                                |


## Annexe B — Broyeurs (seed initial)

Colonnes cibles : `brand · model · year · kind (manual/electric) · burrType · burrMm · adjustmentType · stepsPerRotation · makerMicronsPerStep · hintV60 · hintEspresso · sourceUrl · status`.

**Avertissement pour la base** : le « µm par clic » fabricant est un déplacement vertical de la meule, pas une taille de particule mesurée. Il sert à la proportionnalité entre réglages d'un même broyeur, pas à comparer deux broyeurs. Les plages indicatives sont des points de départ d'usage ; elles seront remplacées par la calibration perso puis par la foule.


| Marque          | Modèle                                      | Type                 | Meules                    | Réglage                               | Pas fabricant                | Plage indicative                                                                                                 | Statut                                                  |
| --------------- | ------------------------------------------- | -------------------- | ------------------------- | ------------------------------------- | ---------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| 1Zpresso        | J-Ultra                                     | manuel               | conique 48 mm             | externe, 100 clics/tour               | 8 µm/clic                    | espresso                                                                                                         | vérifié (1zpresso.coffee)                               |
| 1Zpresso        | K-Ultra                                     | manuel               | conique 48 mm heptagonale | externe, 100 clics/tour               | 20 µm/clic                   | espresso ≈ 2.7 · French press ≈ 9.5 (notation Beean, à confirmer : incompatible avec 20 µm × 100 clics par tour) | vérifié (pas) · plage à vérifier (Beean)                |
| 1Zpresso        | X-Ultra / X-Pro S                           | manuel               | conique                   | externe                               | 12,5 µm/clic                 | all-round                                                                                                        | vérifié (pas)                                           |
| 1Zpresso        | ZP6 Special                                 | manuel               | conique 48 mm             | externe                               | —                            | filtre (light roast)                                                                                             | à vérifier                                              |
| 1Zpresso        | Q2 / Q Air                                  | manuel               | conique (petites meules)  | interne, clics                        | —                            | filtre, voyage                                                                                                   | à vérifier                                              |
| 1Zpresso        | JX-Pro S / JE-Plus                          | manuel               | conique 48 mm             | top adjustment                        | —                            | espresso / all                                                                                                   | à vérifier                                              |
| KINGrinder      | K6                                          | manuel               | conique 48 mm heptagonale | externe, 60 clics/tour                | 16 µm/clic                   | V60 ≈ 90–110 clics · AeroPress ≈ 70–90 · French press ≈ 110                                                      | vérifié (pas, Basic Barista) · plage à vérifier (Beean) |
| KINGrinder      | K4                                          | manuel               | conique 48 mm hexagonale  | externe                               | — (16 ?)                     | all-round, corps                                                                                                 | à vérifier                                              |
| KINGrinder      | K2 / K5                                     | manuel               | conique                   | interne                               | 18 µm/clic                   | filtre                                                                                                           | partiel (coffeeble)                                     |
| KINGrinder      | K0 / K1 / P0 / P2                           | manuel               | conique                   | interne                               | —                            | budget                                                                                                           | à vérifier                                              |
| Comandante      | C40 MK4                                     | manuel               | conique 39 mm Nitro Blade | clics                                 | ≈ 30 µm/clic (Red Clix ≈ 15) | V60 ≈ 20–26 · espresso ≈ 8–12                                                                                    | à vérifier                                              |
| Timemore        | Chestnut C3 / C3S Pro / C3 ESP              | manuel               | conique 38 mm S2C         | clics                                 | —                            | all-round                                                                                                        | à vérifier                                              |
| Timemore        | Chestnut X / X Lite                         | manuel               | conique                   | clics                                 | —                            | all-round                                                                                                        | à vérifier                                              |
| Timemore        | Sculptor 064S / 078S                        | électrique           | plat 64 / 78 mm           | cadran continu                        | —                            | filtre / all                                                                                                     | à vérifier                                              |
| Kinu            | M47 (Classic / Phoenix / Simplicity)        | manuel               | conique 47 mm             | cadran, 50 clics/tour                 | —                            | all-round                                                                                                        | à vérifier                                              |
| Made by Knock   | Aergrind                                    | manuel               | conique 38 mm             | clics                                 | —                            | filtre, voyage                                                                                                   | à vérifier                                              |
| Hario           | Skerton Pro / Mini Slim Pro                 | manuel               | céramique conique         | clics                                 | —                            | budget filtre                                                                                                    | à vérifier                                              |
| Porlex          | Mini II                                     | manuel               | céramique conique         | clics                                 | —                            | voyage                                                                                                           | à vérifier                                              |
| Fellow          | Ode Gen 2                                   | électrique           | plat 64 mm                | cadran cranté (31 positions)          | —                            | filtre uniquement                                                                                                | à vérifier                                              |
| Fellow          | Opus                                        | électrique           | conique 40 mm             | cadran 41 positions + réglage interne | —                            | all-round                                                                                                        | à vérifier                                              |
| Baratza         | Encore                                      | électrique           | conique 40 mm             | 40 crans                              | —                            | filtre                                                                                                           | vérifié (40 crans)                                      |
| Baratza         | Encore ESP                                  | électrique           | conique 40 mm             | 40 crans, pas fins 1–20               | —                            | espresso + filtre                                                                                                | à vérifier                                              |
| Baratza         | Virtuoso+                                   | électrique           | conique 40 mm             | 40 crans                              | —                            | filtre                                                                                                           | à vérifier                                              |
| Baratza         | Sette 270 / 270Wi                           | électrique           | conique 40 mm             | macro + micro                         | —                            | espresso                                                                                                         | à vérifier                                              |
| Niche           | Zero                                        | électrique           | conique 63 mm             | continu, cadran 0–50                  | —                            | all-round, single dose                                                                                           | vérifié (continu)                                       |
| Niche           | Duo                                         | électrique           | plat 83 mm (2 jeux)       | continu                               | —                            | all-round                                                                                                        | à vérifier                                              |
| DF (Turin)      | DF54 / DF64 Gen 2 / DF83                    | électrique           | plat 54 / 64 / 83 mm      | continu numéroté                      | —                            | all-round                                                                                                        | à vérifier                                              |
| Eureka          | Mignon Specialita / Silenzio / Zero / Libra | électrique           | plat 55 mm                | continu                               | —                            | espresso / all                                                                                                   | à vérifier                                              |
| Varia           | VS3 / VS6 / EVO Hybrid                      | électrique / hybride | plat 38 mm (VS3)          | continu                               | —                            | all-round                                                                                                        | à vérifier                                              |
| Option-O        | Lagom Mini / P64 / P100                     | électrique           | plat                      | continu                               | —                            | all / pro                                                                                                        | à vérifier                                              |
| Zerno           | Z1                                          | électrique           | plat 64 mm                | continu                               | —                            | all-round                                                                                                        | à vérifier                                              |
| Mahlkönig       | X54                                         | électrique           | plat 54 mm                | cranté                                | —                            | all-round                                                                                                        | à vérifier                                              |
| Mahlkönig       | EK43 / EK43S                                | électrique           | plat 98 mm                | cadran 0–11                           | —                            | référence torréfacteurs (souvent cité sur les cartes)                                                            | vérifié (référence)                                     |
| Wilfa           | Svart Uniform                               | électrique           | plat 58 mm                | continu                               | —                            | filtre                                                                                                           | à vérifier                                              |
| Wilfa           | Svart Aroma / Nymalt                        | électrique           | conique                   | cranté                                | —                            | filtre                                                                                                           | à vérifier                                              |
| Sage / Breville | Smart Grinder Pro                           | électrique           | conique 40 mm             | 60 crans                              | —                            | all-round                                                                                                        | à vérifier                                              |
| Sage / Breville | Dose Control Pro                            | électrique           | conique                   | 60 crans                              | —                            | all-round                                                                                                        | à vérifier                                              |
| Mazzer          | Philos                                      | électrique           | plat 64 mm                | continu                               | —                            | all-round                                                                                                        | à vérifier                                              |
| Rancilio        | Rocky                                       | électrique           | plat 50 mm                | cranté                                | —                            | espresso                                                                                                         | à vérifier                                              |
| Lelit           | Fred / William                              | électrique           | plat                      | cranté / continu                      | —                            | espresso                                                                                                         | à vérifier                                              |
| Weber Workshops | Key / HG-2                                  | électrique / manuel  | plat 83 mm / conique      | continu                               | —                            | all / pro                                                                                                        | à vérifier                                              |


## Annexe C — Eaux et minéraux

### C1. Cibles de référence


| Paramètre         | Cible SCA     | Plage acceptable | Statut              |
| ----------------- | ------------- | ---------------- | ------------------- |
| TDS               | 150 mg/L      | 75–250           | vérifié (SCAA 2009) |
| Dureté calcique   | 68 mg/L CaCO₃ | 17–85            | vérifié             |
| Alcalinité totale | 40 mg/L CaCO₃ | ≈ 40             | vérifié             |
| pH                | 7,0           | 6,5–7,5          | vérifié             |
| Sodium            | 10 mg/L       | ≈ 10             | vérifié             |
| Chlore            | 0             | 0                | vérifié             |


Tendance « filtre light roast » (pratique, Barista Hustle / Rao / Gagné) : GH plutôt magnésien, KH bas (≈ 20–40). Ne pas l'afficher comme norme.

**Conversions** (chimie, vérifiées) : GH (ppm CaCO₃) ≈ 2,50 × Ca + 4,12 × Mg ; KH (ppm CaCO₃) ≈ 0,82 × HCO₃ (concentrations en mg/L).

### C2. Eaux en bouteille (mg/L)


| Eau                        | Pays | Ca         | Mg         | Na    | HCO₃    | Résidu sec  | pH    | Adaptée café                                 | Statut                           |
| -------------------------- | ---- | ---------- | ---------- | ----- | ------- | ----------- | ----- | -------------------------------------------- | -------------------------------- |
| Montcalm                   | FR   | 3          | 0,7        | 2,2   | 5,2     | 32          | 6,8   | base très douce (à minéraliser ou couper)    | vérifié (montcalm.fr, étiquette) |
| Mont Roucous               | FR   | 2,6        | 0,49       | —     | —       | ≈ 33        | —     | base très douce                              | partiel (coffeediag)             |
| Volvic                     | FR   | ≈ 12–13    | ≈ 8–9      | 12    | ≈ 74–80 | ≈ 130       | ≈ 7   | oui, compromis courant                       | partiel (coffeediag, Mirabilis)  |
| Rosée de la Reine          | FR   | —          | —          | —     | —       | très faible | —     | base douce                                   | à vérifier                       |
| Cristaline                 | FR   | varie      | varie      | varie | varie   | varie       | —     | dépend de la source imprimée sur l'étiquette | à vérifier par source            |
| Evian                      | FR   | ≈ 80       | ≈ 26       | ≈ 6,5 | ≈ 360   | ≈ 345       | ≈ 7,2 | non (alcalinité élevée)                      | à vérifier                       |
| Thonon                     | FR   | ≈ 108      | ≈ 14       | ≈ 3   | ≈ 350   | ≈ 340       | —     | non                                          | à vérifier                       |
| Vittel                     | FR   | ≈ 240      | ≈ 42       | ≈ 5   | ≈ 384   | ≈ 1080      | —     | non                                          | à vérifier                       |
| Contrex / Hépar            | FR   | très élevé | très élevé | —     | —       | > 1500      | —     | non                                          | exclues                          |
| Spa Reine                  | BE   | ≈ 3,5      | ≈ 1,3      | ≈ 3   | ≈ 15    | ≈ 33        | ≈ 6   | base douce                                   | à vérifier                       |
| Lauretana                  | IT   | ≈ 1        | ≈ 0,3      | ≈ 1   | ≈ 4     | ≈ 14        | ≈ 6,5 | base très douce                              | à vérifier                       |
| Black Forest (Schwarzwald) | DE   | —          | —          | —     | —       | faible      | —     | souvent citée par les baristas               | à vérifier                       |
| Icelandic Glacial          | IS   | —          | —          | —     | —       | ≈ 62        | ≈ 8,4 | —                                            | à vérifier                       |


### C3. Produits minéraux (additifs)


| Produit                                  | Forme                                        | Composition annoncée                                                                             | Cible annoncée                                          | Statut                                          |
| ---------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------- | ----------------------------------------------- |
| Third Wave Water — Classic / Light Roast | sachet pour 1 gal ou 1 L d'eau distillée     | MgSO₄ + citrate de calcium + NaCl                                                                | TDS ≈ 150 · alcalinité ≈ 40                             | vérifié (support TWW)                           |
| Third Wave Water — Medium Roast          | sachet                                       | MgSO₄ + citrate de Ca + KHCO₃                                                                    | TDS ≈ 150 · alcalinité ≈ 80                             | vérifié                                         |
| Third Wave Water — Dark Roast            | sachet                                       | MgSO₄ + citrate de Ca + NaHCO₃                                                                   | TDS ≈ 180 · alcalinité ≈ 135–140                        | vérifié                                         |
| Third Wave Water — Espresso              | sachet                                       | MgSO₄ + citrate de Ca + KHCO₃                                                                    | TDS ≈ 150 · alcalinité ≈ 80                             | vérifié                                         |
| Third Wave Water — Cold Brew / Low Acid  | sachet                                       | MgSO₄ + NaHCO₃ + KHCO₃                                                                           | —                                                       | partiel (composition vérifiée, ppm non publiés) |
| Lotus Coffee Water                       | 4 concentrés (Mg, Ca, Na, K) + recettes      | à assembler soi-même                                                                             | recettes « light & bright », « simple & sweet »…        | à vérifier (valeurs)                            |
| Apax Lab — Tonik / Jamm / Lylac / Tanat  | concentrés liquides pré-assemblés            | Tonik : acidité vive · Jamm : Ca + bicarbonate, sucrosité et corps · Lylac : sulfate + K, floral | par profil de saveur ; utilisable aussi post-extraction | partiel (Basic Barista)                         |
| Aquacode                                 | concentré liquide, recette unique, 1 L / 7 L | —                                                                                                | —                                                       | à vérifier                                      |
| Perfect Coffee Water                     | sachet                                       | —                                                                                                | —                                                       | à vérifier                                      |
| Peak Water                               | carafe filtrante à dureté réglable           | filtration, pas additif                                                                          | —                                                       | à vérifier                                      |


### C4. Recettes DIY (documentées)


| Recette                         | Ingrédients                                                                       | Principe                                                                 | Statut                      |
| ------------------------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | --------------------------- |
| Barista Hustle — concentrés     | sel d'Epsom (MgSO₄·7H₂O) et bicarbonate de soude (NaHCO₃) dans de l'eau distillée | concentrés dosés pour viser un GH et un KH donnés ; calculateur en ligne | vérifié (baristahustle.com) |
| Coffee ad Astra — tableur       | collation des recettes publiées (dont TWW) avec GH / KH / conductivité calculés   | outil de vérification ; conductivité mesurable au TDS-mètre à 25 °C      | vérifié (existence)         |
| « Rao-like » via Barista Hustle | Mg + bicarbonate                                                                  | cible proche des recommandations de Scott Rao                            | à vérifier (valeurs)        |


## Annexe D — Torréfacteurs (seed)

Colonnes cibles : `name · city · country · website · instagram · source · status`. Les sites et handles ne sont **pas** renseignés ici : ils seront collectés par l'agent d'enrichissement puis vérifiés à la main. Liste de départ = Paris + France, puis Europe ; à compléter par ton archive.


| Torréfacteur                  | Ville                 | Pays | Source de la mention                          | Statut                          |
| ----------------------------- | --------------------- | ---- | --------------------------------------------- | ------------------------------- |
| Belleville Brûlerie           | Paris                 | FR   | filtre.cafe 2026                              | à vérifier                      |
| Coutume                       | Paris                 | FR   | Singular Coffee 2026, filtre.cafe             | à vérifier                      |
| Lomi                          | Paris                 | FR   | GrainNoble 2026, filtre.cafe                  | à vérifier                      |
| Terres de Café                | Paris                 | FR   | terresdecafe.com, GrainNoble                  | vérifié (existence)             |
| Tanat (ex-Kawa)               | Paris                 | FR   | filtre.cafe 2026, Gault&Millau, Time Out 2025 | partiel (renommage à confirmer) |
| L'Arbre à Café                | Paris                 | FR   | filtre.cafe, Gault&Millau                     | à vérifier                      |
| Hexagone Café                 | Paris                 | FR   | GrainNoble 2026                               | à vérifier                      |
| Café Kitsuné                  | Paris                 | FR   | Gault&Millau                                  | à vérifier                      |
| Cafés Verlet                  | Paris                 | FR   | Gault&Millau                                  | à vérifier                      |
| Télescope                     | Paris                 | FR   | Gault&Millau                                  | à vérifier                      |
| Cafés Pfaff                   | Paris                 | FR   | Gault&Millau                                  | à vérifier                      |
| L'Atelier de Torréfaction     | Paris                 | FR   | Made in City                                  | à vérifier                      |
| KB Coffee Roasters            | Paris                 | FR   | mémoire                                       | à vérifier                      |
| Ten Belles                    | Paris                 | FR   | mémoire                                       | à vérifier                      |
| La Caféothèque                | Paris                 | FR   | mémoire                                       | à vérifier                      |
| The Beans on Fire             | Paris                 | FR   | mémoire                                       | à vérifier                      |
| Partisan Café Artisanal       | Paris                 | FR   | mémoire                                       | à vérifier                      |
| Substance Café                | Paris                 | FR   | mémoire                                       | à vérifier                      |
| Noir Torréfacteur             | Paris                 | FR   | mémoire                                       | à vérifier                      |
| Tactile (Pierre de Chanterac) | Paris                 | FR   | Singular Coffee 2026                          | à vérifier (torréfie ?)         |
| Esperanza Café                | Villeneuve-la-Garenne | FR   | esperanzacafe.com                             | à vérifier                      |
| Brûlerie du Cantin            | Lens                  | FR   | filtre.cafe (MOF 2023)                        | à vérifier                      |
| Omnino                        | Strasbourg            | FR   | filtre.cafe                                   | à vérifier                      |
| Hayuco                        | Toulouse              | FR   | filtre.cafe                                   | à vérifier                      |
| Ximun                         | Pays basque           | FR   | filtre.cafe                                   | à vérifier                      |
| Mokxa                         | Lyon                  | FR   | mémoire                                       | à vérifier                      |
| Piha                          | Bordeaux              | FR   | mémoire                                       | à vérifier                      |
| L'Alchimiste                  | Bordeaux              | FR   | mémoire                                       | à vérifier                      |
| Tim Wendelboe                 | Oslo                  | NO   | Time Out 2025, home-barista                   | vérifié (existence)             |
| Supreme Roastworks            | Oslo                  | NO   | mémoire                                       | à vérifier                      |
| Coffee Collective             | Copenhague            | DK   | J Coffee Collection 2026                      | à vérifier                      |
| April                         | Copenhague            | DK   | J Coffee Collection 2026                      | à vérifier                      |
| Prolog                        | Copenhague            | DK   | mémoire                                       | à vérifier                      |
| La Cabra                      | Aarhus / Copenhague   | DK   | Beean 2026                                    | vérifié (existence)             |
| Koppi                         | Helsingborg           | SE   | J Coffee Collection                           | à vérifier                      |
| Morgon                        | Göteborg              | SE   | J Coffee Collection                           | à vérifier                      |
| Drop Coffee                   | Stockholm             | SE   | home-barista                                  | à vérifier                      |
| Kaffa Roastery                | Helsinki              | FI   | mémoire                                       | à vérifier                      |
| The Barn                      | Berlin                | DE   | home-barista, J Coffee Collection             | à vérifier                      |
| Five Elephant                 | Berlin                | DE   | home-barista                                  | à vérifier                      |
| Bonanza                       | Berlin                | DE   | mémoire                                       | à vérifier                      |
| Man Versus Machine            | Munich                | DE   | mémoire                                       | à vérifier                      |
| Elbgold                       | Hambourg              | DE   | mémoire                                       | à vérifier                      |
| Friedhats                     | Amsterdam             | NL   | Beean 2026                                    | vérifié (existence)             |
| DAK                           | Amsterdam             | NL   | Beean 2026                                    | vérifié (existence)             |
| Rum Baba                      | Amsterdam             | NL   | BrewFusion 2026                               | à vérifier                      |
| Manhattan                     | Rotterdam             | NL   | BrewFusion 2026                               | à vérifier (ville)              |
| White Label                   | Amsterdam             | NL   | mémoire                                       | à vérifier                      |
| MOK                           | Bruxelles / Louvain   | BE   | Time Out 2025                                 | à vérifier                      |
| Caffènation                   | Anvers                | BE   | mémoire                                       | à vérifier                      |
| Nomad                         | Barcelone             | ES   | BrewFusion 2026                               | à vérifier                      |
| Right Side                    | Barcelone             | ES   | mémoire                                       | à vérifier                      |
| Hola Coffee                   | Madrid                | ES   | Time Out 2025                                 | à vérifier                      |
| Toma Café                     | Madrid                | ES   | mémoire                                       | à vérifier                      |
| Gardelli                      | Forlì                 | IT   | home-barista                                  | à vérifier                      |
| Nero Scuro                    | Italie                | IT   | home-barista                                  | à vérifier (ville)              |
| Bugan Coffee Lab              | Bergame               | IT   | home-barista                                  | à vérifier                      |
| Garage Coffee Bros            | Italie                | IT   | home-barista                                  | à vérifier (ville)              |
| Ditta Artigianale             | Florence              | IT   | mémoire                                       | à vérifier                      |
| Square Mile                   | Londres               | UK   | J Coffee Collection                           | à vérifier                      |
| Assembly                      | Londres               | UK   | J Coffee Collection                           | à vérifier                      |
| Colonna                       | Bath                  | UK   | J Coffee Collection                           | à vérifier                      |
| Origin                        | Cornouailles          | UK   | mémoire                                       | à vérifier                      |
| Hasbean                       | Stafford              | UK   | mémoire                                       | à vérifier                      |
| Dark Arts                     | Londres               | UK   | mémoire                                       | à vérifier                      |
| Workshop                      | Londres               | UK   | mémoire                                       | à vérifier                      |
| Round Hill                    | Bath                  | UK   | mémoire                                       | à vérifier                      |
| Obadiah                       | Édimbourg             | UK   | mémoire                                       | à vérifier                      |
| 3fe                           | Dublin                | IE   | mémoire                                       | à vérifier                      |
| Mame                          | Zurich                | CH   | J Coffee Collection                           | à vérifier                      |
| Stoll                         | Zurich                | CH   | mémoire                                       | à vérifier                      |
| Gota Coffee Experts           | Vienne                | AT   | Time Out 2025                                 | à vérifier (torréfie ?)         |
| Süssmund                      | Vienne                | AT   | mémoire                                       | à vérifier                      |
| Kross Coffee Roasters         | Grèce                 | GR   | Time Out 2025                                 | à vérifier (ville)              |
| Taf                           | Athènes               | GR   | mémoire                                       | à vérifier                      |
| Fábrica Coffee Roasters       | Lisbonne              | PT   | mémoire                                       | à vérifier                      |
| Doubleshot                    | Prague                | CZ   | mémoire                                       | à vérifier                      |
| HAYB                          | Varsovie              | PL   | mémoire                                       | à vérifier                      |
| Kawa (si distinct de Tanat)   | Paris                 | FR   | Time Out 2025                                 | à vérifier                      |


## Annexe E — Équipements (hors broyeurs)

Listes ouvertes : l'utilisateur peut toujours créer un item custom. Statut global : **à vérifier** (catalogues fabricants 2026), sauf mention.

**Brewers (filtre / immersion)** : Hario V60 01 · 02 · 03 (plastique, céramique, verre, métal) · Hario Switch 02 / 03 · Hario Mugen · Kalita Wave 155 / 185 · Chemex 3 / 6 / 8 tasses · Origami S / M · Orea V3 / V4 · April Brewer · Cafec Flower / Deep 45 · Kono Meimon · Melitta 1×2 / 1×4 · Clever Dripper · Fellow Stagg X / XF · Tricolate · Pulsar (NextLevel) · Aeropress Original / Clear / XL / Go · French press (Bodum Chambord, Espro P3/P7, Hario) · Moka Bialetti Express 1 / 3 / 6 · Bialetti Brikka · Cold brew (Hario Mizudashi, Toddy).

**Filtres papier** : Hario V60 (tabbed / untabbed, blanchi / non blanchi) · Cafec Abaca · Cafec Abaca+ · Cafec T-92 · Cafec T-90 · Cafec Light Roast · Cafec Deep 27 / 45 · Kalita Wave 155 / 185 · Chemex bonded (carré / rond) · Origami (cône / wave) · Sibarist FAST · Sibarist B3 · Aeropress papier · Aesir (AeroPress) · Timemore · Kinto · Melitta 1×2 / 1×4. Métal : Able Kone, Aeropress métal.

**Bouilloires** : Fellow Stagg EKG / EKG Pro · Hario Buono / Kasuya · Timemore Fish Smart / Fish Pure Over · Brewista Artisan · Bonavita · Cosori · Kinto.

**Balances** : Acaia Pearl / Pearl S / Lunar / Pyxis · Timemore Black Mirror Basic 2 / Nano / Plus / Mini · Felicita Arc / Incline / Parallel · Hario V60 Drip Scale · Fellow Tally Pro · Decent Scale · Varia AKU · Brewista Smart Scale II · Weightman. (Bluetooth : v2.)

**Machines espresso et leviers** : La Marzocco Linea Mini / Micra · Lelit Bianca / Elizabeth / Mara X · Profitec Pro 500 / 600 / 700 / Go · ECM Synchronika / Mechanika · Rocket Appartamento / Mozzafiato · Rancilio Silvia / Silvia Pro X · Gaggia Classic Pro / Evo · Sage / Breville Bambino Plus / Barista Express / Dual Boiler / Oracle · Decent DE1 · Ascaso Steel Duo · Bezzera · Flair 58 / Pro 2 / Classic · Cafelat Robot · Wacaco Picopresso · 9Barista.

**Accessoires** : WDT (Normcore, Sworksdesign, Weber Unifier, fait maison) · distributeur · tamper (58 / 58,5 / 53 mm) · puck screen (Normcore, IMS) · paniers précision (IMS, VST, Pullman) · dosing cup / funnel · Melodrip · Gabi Master A / B · Hario Drip Assist · spray RDT · brosse à meules · TDS-mètre / réfractomètre (Atago PAL-Coffee, DiFluid R2, VST LAB) · thermomètre.

## Annexe F — Base de connaissances (entrées initiales)

Chaque entrée sera stockée comme `KnowledgeEntry` : citation, année, type (peer-reviewed / standard / pratique documentée), résumé en une phrase, ce que Kohi en fait, lien. Pas de texte intégral.


| #   | Référence                                                                                                                                                             | Type                | Ce qu'elle établit                                                                                                                                  | Usage dans Kohi                                                                                 | Statut                                             |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| F1  | Lockhart, 1957 — *The Soluble Solids in Beverage Coffee as an Index to Cup Quality*                                                                                   | historique          | origine de la Brewing Control Chart (TDS × extraction)                                                                                              | contexte                                                                                        | vérifié (cité par UC Davis / Fresh Cup)            |
| F2  | Guinard, Frost, Batali, Cotter, Lim, Ristenpart — *A new Coffee Brewing Control Chart…*, J. Food Sci. 2023                                                            | peer-reviewed       | nouvelle carte sensorielle et consommateur ; deux groupes de préférence ; les attributs suivent des tendances plus complexes que la carte classique | carte de fond du diagnostic ; « Ask »                                                           | vérifié                                            |
| F3  | Batali, Ristenpart, Guinard — *Brew temperature, at fixed brew strength and extraction, has little impact on the sensory profile of drip brew coffee*, Sci. Rep. 2020 | peer-reviewed       | à TDS et extraction fixés, 87 / 90 / 93 °C changent peu le profil d'un filtre                                                                       | la température est un levier d'extraction, pas un bouton de goût direct ; tempère les règles G3 | vérifié (titre via PubMed)                         |
| F4  | Frost, Ristenpart, Guinard — roast level × TDS × extraction, J. Food Sci. 2020                                                                                        | peer-reviewed       | interaction du niveau de torréfaction avec force et extraction                                                                                      | règles roast level                                                                              | à vérifier (titre exact)                           |
| F5  | Cotter, Batali, Ristenpart, Guinard — préférences consommateurs à travers la carte, J. Food Sci. 2021                                                                 | peer-reviewed       | deux segments de préférence chez les buveurs de café noir                                                                                           | biais de goût (1.1)                                                                             | à vérifier (titre exact)                           |
| F6  | Cameron et al. — *Systematically Improving Espresso*, Matter 2020                                                                                                     | peer-reviewed       | modèle + expériences : une mouture trop fine peut rendre l'extraction inégale ; reproductibilité via mouture plus grossière et dose réduite         | règles espresso ; « Ask »                                                                       | vérifié (cité, DOI 10.1016/j.matt.2019.12.019)     |
| F7  | Méndez Harper et al. — *Moisture-controlled triboelectrification during coffee grinding*, Matter 2023                                                                 | peer-reviewed       | l'humidité des grains contrôle la charge statique ; ajouter un peu d'eau réduit les agglomérats et augmente l'extraction en espresso                | note RDT dans les recettes espresso ; « Ask »                                                   | vérifié                                            |
| F8  | Méndez Harper, Hendon et al. — *Chemical strategies to mitigate electrostatic charging…*, arXiv 2312.03103                                                            | preprint            | seule l'eau (< 0,05 mL/g) modifie les paramètres d'extraction ; ≥ 15 % de concentration en plus sur torréfactions sombres                           | idem F7                                                                                         | vérifié (arXiv ; statut de publication à vérifier) |
| F9  | Uman et al. — *The effect of bean origin and temperature on grinding roasted coffee*, Sci. Rep. 2016                                                                  | peer-reviewed       | des grains plus froids donnent une distribution plus fine et plus étroite                                                                           | note « grains froids » ; « Ask »                                                                | vérifié (cité)                                     |
| F10 | Hendon, Colonna-Dashwood — *The Role of Dissolved Cations in Coffee Extraction*, J. Agric. Food Chem. 2014                                                            | peer-reviewed       | Mg et Ca influencent l'extraction de composés aromatiques ; les bicarbonates tamponnent                                                             | explications eau                                                                                | à vérifier (référence de mémoire)                  |
| F11 | SCAA — *Water for Brewing Specialty Coffee*, 2009                                                                                                                     | standard            | cibles TDS, dureté, alcalinité, pH, Na                                                                                                              | `TargetBand`                                                                                    | vérifié                                            |
| F12 | SCA — Coffee Value Assessment, SCA-103 / SCA-104 (2023–2024)                                                                                                          | standard            | attributs descriptifs et affectifs : fragrance, arôme, saveur, finale, acidité, sucrosité, mouthfeel, global                                        | axes *Taste*                                                                                    | vérifié                                            |
| F13 | SCA / WCR — Coffee Taster's Flavor Wheel et Sensory Lexicon (2016)                                                                                                    | standard            | vocabulaire de saveurs                                                                                                                              | chips de saveurs (~40 termes)                                                                   | vérifié (existence)                                |
| F14 | Gagné — *The Physics of Filter Coffee* (2020) ; Coffee ad Astra                                                                                                       | pratique documentée | fines, percolation, recettes d'eau, tableurs                                                                                                        | « Ask » ; C4                                                                                    | vérifié (existence)                                |
| F15 | Colonna-Dashwood, Hendon — *Water for Coffee* (2015)                                                                                                                  | livre               | chimie de l'eau pour le café                                                                                                                        | explications eau                                                                                | à vérifier                                         |
| F16 | Moroney et al. — modélisation multi-échelle de l'extraction, Chem. Eng. Sci. 2015                                                                                     | peer-reviewed       | modèle d'extraction en lit de grains                                                                                                                | contexte « Ask »                                                                                | à vérifier                                         |
| F17 | Mo, Johnston, Navarini, Ellero — érosion induite par l'écoulement en filtration, Phys. Fluids 2021                                                                    | peer-reviewed       | migration des fines / érosion pendant l'extraction                                                                                                  | contexte « Ask »                                                                                | vérifié (cité, arXiv 2512.21528)                   |
| F18 | Smrke et al. — dégazage du café torréfié (méthode gravimétrique), J. Agric. Food Chem. 2018                                                                           | peer-reviewed       | cinétique du dégazage selon torréfaction et mouture                                                                                                 | règle « fraîcheur »                                                                             | à vérifier                                         |
| F19 | Barista Hustle — *DIY Water Recipes Redux* ; *The Coffee Compass*                                                                                                     | pratique documentée | recettes d'eau ; boussole de diagnostic acide / amer / fort / faible                                                                                | C4 ; G7                                                                                         | vérifié (existence)                                |


## Annexe G — Tables de correspondance et règles

### G1. Granulométrie indicative par méthode (µm)


| Méthode             | Plage indicative | Source                             | Statut                        |
| ------------------- | ---------------- | ---------------------------------- | ----------------------------- |
| Espresso            | ≈ 180–380        | Honest Coffee Guide (via Bean Box) | à vérifier sur le site source |
| AeroPress           | ≈ 320–960        | idem                               | à vérifier                    |
| V60                 | ≈ 400–700        | Honest Coffee Guide                | vérifié                       |
| Pour-over (général) | ≈ 410–930        | Honest Coffee Guide                | vérifié                       |
| French press        | ≈ 690–1300       | Honest Coffee Guide (via Bean Box) | à vérifier                    |
| Cold brew           | ≈ 820–1270       | Honest Coffee Guide                | vérifié                       |
| Moka                | fine, > espresso | pratique                           | pratique                      |
| Turkish / ibrik     | < 200            | pratique                           | pratique                      |


Réserve : ce sont des D50 approximatifs d'un site de référence, pas des mesures Kohi. Servent uniquement de point de départ « In your terms ».

### G2. Ratios par méthode


| Méthode               | Ratio usuel                                    | Statut   |
| --------------------- | ---------------------------------------------- | -------- |
| Espresso              | 1:1,5 – 1:3 (standard 1:2)                     | pratique |
| V60 / Kalita / Chemex | 1:15 – 1:17                                    | pratique |
| AeroPress             | 1:12 – 1:18                                    | pratique |
| French press / Clever | 1:15 – 1:17                                    | pratique |
| Moka                  | dépend du remplissage (≈ 1:7 – 1:10)           | pratique |
| Cold brew             | concentré 1:5 – 1:8 ; prêt à boire 1:12 – 1:16 | pratique |
| Cupping SCA           | 1:18,2 (8,25 g / 150 mL)                       | vérifié  |
| Drip SCA Golden Cup   | 55 g/L ± 10 %                                  | vérifié  |


### G3. Température de départ par niveau de torréfaction (règle de suggestion)


| Roast level  | Filtre    | Espresso | Niveau de preuve                                                                                                                   |
| ------------ | --------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Light        | 94–100 °C | 94–96 °C | pratique ; F3 montre un effet sensoriel faible à TDS/extraction fixés — la température sert surtout à atteindre l'extraction visée |
| Medium-light | 92–96 °C  | 93–95 °C | pratique                                                                                                                           |
| Medium       | 90–94 °C  | 92–94 °C | pratique                                                                                                                           |
| Medium-dark  | 88–92 °C  | 90–93 °C | pratique                                                                                                                           |
| Dark         | 85–90 °C  | 88–92 °C | pratique                                                                                                                           |


Decaf : un cran plus grossier, −2 °C. Fraîcheur < 5 jours : bloom + 15 s, note « dégazage ». Ces deux règles sont **pratique** ; F18 à vérifier pour la seconde.

### G4. Force et extraction


| Méthode  | TDS usuel   | Extraction usuelle | Formule                                                           | Statut                                                  |
| -------- | ----------- | ------------------ | ----------------------------------------------------------------- | ------------------------------------------------------- |
| Filtre   | 1,15–1,45 % | 18–22 %            | EY = TDS × boisson ÷ dose ; boisson ≈ eau − ~2 × dose (rétention) | standard (BCC classique) ; F2 nuance la zone « idéale » |
| Espresso | 8–12 %      | 18–22 %            | EY = TDS × boisson ÷ dose                                         | standard                                                |


### G5. Repos après torréfaction (pratique)


| Usage         | Fenêtre courante              | Statut   |
| ------------- | ----------------------------- | -------- |
| Filtre, light | 7–21 jours (souvent plus)     | pratique |
| Espresso      | 10–30 jours                   | pratique |
| Dark roast    | plus court (dégaze plus vite) | pratique |
| Congélation   | prolonge la fenêtre           | pratique |


### G6. Flux (g/s), repères


| Contexte                           | Repère                                | Statut       |
| ---------------------------------- | ------------------------------------- | ------------ |
| Versement col de cygne (pour-over) | ≈ 3–6 g/s                             | pratique     |
| Espresso, débit en sortie          | ≈ 1–2 g/s (36 g en 25–30 s ≈ 1,3 g/s) | arithmétique |


Kohi calcule le flux moyen `eau ÷ temps` et, avec les étapes, le flux par phase. Aucune cible n'est affichée comme norme.

### G7. Règles de diagnostic « Next time »

Une seule variable change par proposition. Ordre de priorité : mouture → ratio → température → temps → agitation → eau.


| Signal (diagnostic + mesures)                       | Proposition                                                   | Raison courte                             | Niveau de preuve                  |
| --------------------------------------------------- | ------------------------------------------------------------- | ----------------------------------------- | --------------------------------- |
| Acidité *trop* · amertume *pas assez* · temps court | mouture plus fine                                             | sous-extraction probable                  | pratique (Coffee Compass) + BCC   |
| Amertume *trop* · astringence · temps long          | mouture plus grossière                                        | sur-extraction probable                   | pratique + BCC                    |
| Corps *pas assez* · reste juste                     | ratio plus court (ex. 1:15)                                   | plus de force sans changer l'extraction   | BCC                               |
| Corps *trop* · saveur boueuse                       | ratio plus long ou mouture plus grossière                     | moins de force / moins de fines           | pratique                          |
| Acide *et* amer                                     | ne pas toucher la mouture ; vérifier eau (KH) et distribution | extraction inégale plutôt qu'insuffisante | F6 (espresso) ; pratique (filtre) |
| Rendement calculé > 22 % + amertume                 | temps plus court ou eau moins chaude                          | sur-extraction mesurée                    | BCC                               |
| Rendement calculé < 18 % + acide                    | mouture plus fine (ou eau plus chaude si déjà fin)            | sous-extraction mesurée                   | BCC                               |
| Espresso < 20 s                                     | mouture plus fine                                             | temps hors fenêtre                        | pratique (convention)             |
| Espresso > 35 s, canalisation                       | mouture plus grossière ; WDT                                  | F6 : trop fin → écoulement inégal         | F6 + pratique                     |
| Statique, mouture qui colle, shots irréguliers      | RDT (quelques gouttes d'eau avant mouture)                    | F7 / F8                                   | peer-reviewed                     |
| Plat, terne, eau très douce                         | eau : GH ≈ 50–80, KH ≈ 30–40                                  | C1                                        | standard                          |
| Éteint, sans acidité, eau dure                      | eau : baisser KH (couper, filtrer, remineraliser)             | C1, F10                                   | standard / à vérifier             |


### G8. Conversion entre réglages de broyeurs (proxy)

Deux étapes, toutes deux affichées avec « ≈ » :

1. **Proportionnel au sein d'un même broyeur** : `µm_proxy = clics × pasFabricant` (mécanique, pas granulométrique).
2. **Entre broyeurs, par plage déclarée** : pour une méthode donnée, `réglage_B = min_B + (réglage_A − min_A) ÷ (max_A − min_A) × (max_B − min_B)`, où `min/max` sont les plages utiles déclarées par chaque utilisateur (ou les plages indicatives de l'annexe B à défaut).

La calibration collective (v2) remplacera (2) par des couples observés (broyeur, réglage, méthode, rating).

## Annexe H — Plan de vérification avant seed


| Annexe            | Qui                          | Comment                                                                                                                                 | Critère « vérifié »                                                         | Format de sortie                                                                                                                                       |
| ----------------- | ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| A — Recettes      | JBK                          | relire chaque recette à la source de l'auteur (vidéo / page), reformuler en étapes ; brasser au moins une fois A1, A2, A7, A9, A12      | paramètres + étapes concordent avec la source ; attribution + URL présentes | `recipes.json` (bundle) avec `sourceUrl`, `attribution`, `verifiedOn`                                                                                  |
| B — Broyeurs      | JBK + agent                  | pas fabricant depuis la page produit officielle ; plages indicatives depuis 2 sources concordantes ou ta propre expérience              | pas fabricant sourcé ; plages marquées `hint`                               | `grinders.csv` : `brand,model,year,kind,burrType,burrMm,adjustmentType,stepsPerRotation,makerMicronsPerStep,hintV60,hintEspresso,sourceUrl,verifiedOn` |
| C — Eaux          | JBK                          | photo de l'étiquette ou page marque pour chaque eau ; fiche fabricant pour chaque produit minéral ; recalcul GH/KH avec les formules C1 | Ca, Mg, Na, HCO₃ + résidu sec présents et sourcés                           | `waters.csv`, `mineral_products.csv`                                                                                                                   |
| D — Torréfacteurs | agent d'enrichissement + JBK | l'agent propose site / Instagram / ville ; validation manuelle ; dédoublonnage                                                          | site officiel joignable ; ville + pays exacts                               | `roasters.csv` : `name,city,country,website,instagram,lat,lng,verifiedOn`                                                                              |
| E — Équipements   | JBK                          | catalogue fabricant 2026 ; supprimer les modèles retirés                                                                                | nom exact du modèle                                                         | `equipment_catalog.csv` : `kind,brand,model,notes`                                                                                                     |
| F — Connaissances | JBK + agent curateur         | retrouver DOI / URL ; résumé en une phrase ; niveau de preuve                                                                           | DOI ou URL stable ; résumé relu                                             | `knowledge.json` : `id,citation,year,type,summary,usage,url,verifiedOn`                                                                                |
| G — Règles        | JBK                          | chaque règle liée à une entrée F ou marquée « pratique » ; tests unitaires sur les règles G3, G4, G7, G8                                | niveau de preuve renseigné ; tests verts                                    | `rules.json` + tests                                                                                                                                   |


**Gate avant 1.0** : aucune ligne « à vérifier » dans A, C1, F1–F3, F6–F7, F11–F12 et G7 (les éléments sur lesquels reposent recette suggérée, `TargetBand` et « Next time »). Les autres lignes peuvent rester « à vérifier » si elles sont masquées (feature flag) ou affichées avec « ≈ ».

**Licences et attribution** : les paramètres de recettes et les compositions d'eau sont des faits ; on cite l'auteur et la marque, on ne reprend ni texte ni tableau tiers verbatim. Open Food Facts (ODbL) impose l'attribution si on affiche ses données. Les plages Honest Coffee Guide / Beean servent de contrôle, pas de source à copier.