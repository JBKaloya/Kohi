# Kohi — Dev brief #9 : la nouvelle carte Kohi devient le standard

**Statut** : prompt pour Cursor, version 9.1 · **Date** : 25 octobre 2026 · **Owner** : JBK (jbk studio)
**À lire avant** : `design-system.md` (§3 Couleur, Tuile, §9 Composants), `ai-poster-retired.md`, `Kohi/Design/KohiCard.swift`, `Kohi/Process/InkStampPipeline.swift`, `PackMark.swift`, `PackInk.swift`, `CardComposer.swift`, `App/CardLook.swift`.
**Référence visuelle** : `docs/card-lab/kohi-card-lab.html` (ouvrir dans un navigateur). C'est le prototype qui fait foi : les algorithmes de ce brief y tournent en JavaScript, sur la collection réelle et les marques tirées de `backstages/planche.png`.
**Fichiers livrés** (`docs/card-lab/`) : `OriginStickers.xcassets` (47 stickers prêts à l'emploi), `aroma-palette.json` (couleur par note), `card-terroir.json` (terre par origine, réglages process et torréfaction), `origin-stickers.json` (recettes des stickers, source des PNG), `card-art-vectors.json` (vecteurs de parité Swift ↔ prototype), `fixtures/marks/` (quatre marques réelles pour les tests de vectorisation), `src/` (sources du prototype et scripts de rendu), `kohi-card-lab.html`.

**9.1 — arbitrages JBK du 25 octobre** : la nouvelle carte **remplace** l'ancienne, elle n'est pas une option. L'ancien gabarit papier disparaît, la carte Kohi devient la face par défaut de la mosaïque, et **toute l'archive est régénérée** au premier lancement de la version (§9). Les stickers sont **embarqués en PNG**, pas dessinés au runtime (§6). La **vectorisation des symboles entre dans ce lot** (§5.2) : c'est elle qui rend les marques nettes à toute taille, et la régénération est le seul moment où l'on remesure toute l'archive. Les petites marques passent en **motif répété** (validé sur Blue Bottle) ; l'ange de Huabal sert de référence au gaufrage.

---

## 0. Constat

### 0.1 Ce qu'on a essayé, dans l'ordre

| Quand | Quoi | Où | Résultat |
|---|---|---|---|
| Août | Fiches papier dessinées en CoreGraphics pour peupler la grille | `Tools/GenerateSampleCards.swift`, `Resources/SampleCards` | Des objets de dev, pas un rendu |
| Sept. | Flyer IA « tampon caoutchouc » par carte (`gpt-image-2`, edge function `card-poster`) | `ai-poster-retired.md`, `Tools/PosterBench` | Beau, mais 1–2 min et ~0,22 $ par carte, réseau obligatoire. **Retiré.** |
| Oct. | Aperçu de la fiche colorée hors app | `Tools/PreviewFiche.swift` → `fiche-preview/`, `fiche-preview-v2/`, `backstages/planche.png` | Sur 13 vrais sachets : 12 « pas de symbole », titres lus par OCR illisibles (« Krywords: BP8C ») |
| Actuel (non commité, brief 7) | `KohiCard` gabarit papier + `InkStampPipeline` (PackMark par teinte, sinon Otsu ou edgeWork, portes, mot interdit) + `RoasterMarkCache` + `CardComposer` + `CardLook` | `Design/`, `Process/`, `App/` | Fiable et local, mais la carte reste de l'interface |

### 0.2 Pourquoi la carte actuelle fait « UI »

1. **Une seule couleur par carte, celle du titre.** Toute la surface est `Palette.paper`. Le titre prend l'encre mesurée (`PackInkReader.display`, v = 0,36) ou la famille de la roue × 0,62. Dans la mosaïque, seize cartes ont le même fond.
2. **Le symbole en tuile est une tache grise.** `KohiCard.shownPlacement` force `.watermark` en tuile, à 14 % en `multiply`, **sans teinte** (`stampImage(stamp, tint: false)`). Le « cœur gris » de la grille, c'est le trèfle de Klover, recadré et éteint.
3. **Le symbole est un bitmap binaire.** `PackMark.render` et `InkStampPipeline.raster` écrivent des pixels (26, 24, 21, 255) ou rien : aucun antialiasing. Agrandi en fond, il crénèle.
4. **Le titre disparaît quand `name` est vide.** `KohiCardContent.make` lit `card.name`, pas `card.displayName`. Résultat : six cartes « Geera, Jimma, Ethiopia » sans titre, alors que le design system prévoit la chaîne producteur → ferme → origine → torréfacteur.
5. **Le design system l'interdit.** « Le tampon d'encre […] est un traitement du scan, pas une couleur du paquet » et « La couleur vive des cartes scannées n'entre toujours pas dans le chrome ». La règle change (§7).

### 0.3 Ce qu'on garde

Tout est local et déterministe ; l'extraction existe (`PackInkReader`, `PackMark`, portes, refus des mots via OCR, *Choose area*) ; le cache par token de `CardComposer` ; les deux faces de `CardLook` (scan / kohi) ; le ratio 4:5 ; `ImageRenderer` pour composer la tuile. On ne rappelle aucun modèle d'image : la leçon des flyers tient. **Tout se génère sur l'appareil, en Swift** : CoreGraphics pour le fond et le symbole, Vision (déjà là pour l'OCR) pour les contours. 0 €, hors ligne.

---

## 1. Le principe : chaque carte est un petit paysage

Lu de bas en haut, comme les dégradés de la planche de références (Sahara, vert, mer) :

| Champ de la carte | Devient | Règle | Si vide |
|---|---|---|---|
| `country` | **La terre** (bas de carte, sous l'étiquette) + **le sticker** | Une teinte de sol par code ISO, deux tons de paysage (`card-terroir.json`). Sticker par code ISO (`OriginStickers.xcassets`). | Terre torréfiée neutre ; sceau de process |
| `tastingNotes` (3 max, `faceNotes`) | **Trois masses de couleur** au milieu | Note → couleur d'arôme (`aroma-palette.json`) | Les tons de la terre, l'encre du sachet en tête |
| `altitude` | **Le ciel** (haut) | 900 m → 0 %, 2 200 m → 100 % d'air. Bas : brume chaude `#F4DDB7`. Haut : air froid `#EAF1EF`. Teinté à 18 % par la note la plus claire. | 50 % |
| `process` | **L'énergie** du champ | Lavé : net, clair. Nature : chaud, dense. Honey : halo doré. Fermentations : saturé, tourbillon. Wet-hulled : grain lourd. | Réglage moyen |
| `roastLevel` | **La valeur** | +0,07 (super light) → −0,10 (dark) de L OKLab | +0,02 (light) |
| encre mesurée (`StampFile.ink*`) | **Un accent** vif au bord | Teinte du `PackInk`, S 0,72, V 0,84 | Rien |
| symbole extrait | **Le relief** derrière l'étiquette | Vectorisé (§5.2), puis gaufrage, encre, trame ou motif (§5.4) | Le fond porte seul la carte |
| `card.id` | **La graine** | FNV-1a 32 de l'UUID → positions, rotation et côté du sticker. Jamais d'aléatoire au rendu. | — |

Les couleurs vives vivent **dans l'objet**. Le chrome reste encre et papier. L'étiquette de la carte est du papier Kohi.

---

## 2. Architecture

### 2.1 Nouveaux fichiers

| Fichier | Rôle |
|---|---|
| `Kohi/Process/CardArt.swift` | Struct pure `nonisolated`, `Sendable`, `Equatable`. `CardArt.make(_ card: CoffeeCard, ink: StampFile?) -> CardArt` : graine, blobs, réglages process, ciel, encre du titre, côté et rotation du sticker, cinq tirages pour le symbole. `static let version = 1`. |
| `Kohi/Process/CardSeed.swift` | `fnv1a32(_:)` et `Mulberry32` (§3.1). |
| `Kohi/Process/OKLab.swift` | Conversions sRGB ↔ OKLab (§3.2). |
| `Kohi/Process/AromaPalette.swift` | Charge `aroma-palette.json`. `color(forNote:)` : d'abord `FlavorMatcher` (ids de la roue), puis plus long synonyme contenu dans la note (« Winey Blueberry » → blueberry). |
| `Kohi/Process/Terroir.swift` | Charge `card-terroir.json` : terre par ISO, process, torréfaction, ciel. `classify(process:)` (§3.4). |
| `Kohi/Design/CardBackdrop.swift` | `static func render(_ art: CardArt, mark: MarkShape?, treatment: SymbolTreatment, size: CGSize) -> (image: CGImage, textTone: TextTone)?` et `static func field(_ art: CardArt, size: CGSize) -> CGImage?` (le champ seul, pour le placeholder). 100 % CoreGraphics, hors main thread, sans Metal (§4). |
| `Kohi/Process/GrainTexture.swift` | Tuile 256 × 256 générée une fois, graine fixe `20261025`, gardée en mémoire. |
| `Kohi/Process/MarkVectorizer.swift` | Masque antialiasé → contours Vision → `MarkShape` normalisé (§5.2). |
| `Kohi/Design/SymbolLayer.swift` | Rasterise le `MarkShape` à la taille voulue, puis les quatre traitements (§5.4). |
| `Kohi/Design/OriginStickerImage.swift` | Nom d'asset d'une carte : `Stickers/origin-<iso>`, sinon `Stickers/seal-<process>`, sinon `nil` (§6). |
| `Kohi/App/CardStandard.swift` | Version du standard, migration de `CardLook`, passe de régénération (§9). |
| `OriginStickers.xcassets` | Depuis `docs/card-lab/`, glissé dans le projet, target Kohi. |
| `Kohi/Resources/Reference/aroma-palette.json`, `card-terroir.json` | Depuis `docs/card-lab/`, **ajoutés au target** (vérifier le `project.pbxproj`, comme `filters.json`). |

### 2.2 Fichiers modifiés

- **`KohiCard`** : nouvelle composition (§8). **L'ancien gabarit est supprimé** : papier uni, cercles ISO et score, filigrane gris à 14 %, cadre de 150 pt en pied de fiche. Pas d'option pour y revenir. La règle « Tile never draws a sticker » disparaît.
- **`KohiCardPlaceholder`** : affiche le **champ seul** de la carte (`CardBackdrop.field`, ~2 ms) et le titre, plus jamais du papier blanc. Une tuile en attente a déjà ses couleurs.
- **`KohiCardContent`** : `designVersion = 3`. Le titre suit `card.displayName` quand `name` est vide. `cacheToken` reçoit `CardStandard.version`, le traitement du symbole et la mise en page. `circles` n'est plus affiché (le sticker remplace le code ISO) ; le score reste sur la fiche.
- **`CardComposer.draw`** : rend `CardBackdrop` (CGImage) puis pose l'étiquette et le sticker via `ImageRenderer`. Même cache, même file d'attente. Écrire la nouvelle tuile **puis** supprimer les `kohi-tile-*.png` dont le token n'est plus le bon.
- **`CardLookStore`** : défaut `.kohi` au lieu de `.scan` ; migration unique (§9.2).
- **`InkStamp` / `StampStyle`** : `StampStyle` devient `SymbolStyle { auto, emboss, ink, halftone, pattern, none }`. Décodage rétrocompatible : `"sticker"` → `.auto`, `"watermark"` → `.emboss`. `InkStamp.Placement` reste comme signal pour le mode auto. `InkStamp.pipelineVersion = 3`.
- **`PackMark.render`, `InkStampPipeline.raster` / `measured`** : sortie antialiasée (§5.1), puis vectorisation (§5.2), dans `measure`.
- **`StampFile`** : `+ vectorVersion: Int?` (nil = pas de forme vectorielle, repli bitmap).
- **`CardFiles`** : `+ stampShapeJSON(_:)` → `stamp-shape.json`, lecture et écriture.
- **Fiche, section Style** : *Symbol* : Auto · Emboss · Ink · Halftone · Pattern · None. *Choose area* et *Redo* restent et revectorisent.
- **Profil** (là où vit *Cards* aujourd'hui) : *Card layout* : Label (défaut) · Full bleed. Le choix *Cards* (Kohi / Scans) reste, avec Kohi par défaut.
- **`design-system.md`** : §7.

Rien n'est synchronisé : tout se déduit des champs, comme les tuiles. La colonne `coffee_cards.poster` et les `poster.heic` restants ne sont pas touchés.

---

## 3. Algorithmes (à porter tels quels depuis le prototype)

### 3.1 Graine

Entrée : `card.id.uuidString.lowercased()` en UTF-8. **Jamais `hashValue`** (aléatoire à chaque lancement).

```swift
nonisolated enum CardSeed {
    static func fnv1a32(_ s: String) -> UInt32 {
        var h: UInt32 = 0x811c9dc5
        for b in s.utf8 { h ^= UInt32(b); h = h &* 0x01000193 }
        return h
    }
}

nonisolated struct Mulberry32 {
    private var a: UInt32
    init(seed: UInt32) { a = seed }
    mutating func unit() -> Double {
        a = a &+ 0x6D2B79F5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
    /// (unit − 0.5) × 2 × amplitude
    mutating func jitter(_ amplitude: Double) -> Double { (unit() - 0.5) * 2 * amplitude }
}
```

**L'ordre des tirages fait partie du contrat** (sinon la carte change d'une version à l'autre) : terre (x, rot) → bande de terroir (côté, rot) → ciel (x, rot) → choix de la composition → pour chaque note (x, y, sx, sy, rot) → encre si présente (côté, décalage, y) → blob de process si présent (x, y, rot) → côté du sticker → rotation du sticker → cinq tirages du symbole. `card-art-vectors.json` donne la graine, les trois premiers tirages et deux couleurs du champ pour cinq cartes : c'est le test de parité.

### 3.2 OKLab

On mélange en OKLab : un dégradé entre un rose et un vert n'y passe pas par le gris.

```swift
nonisolated enum OKLab {
    static func fromSRGB(_ r: Double, _ g: Double, _ b: Double) -> SIMD3<Double> {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (lr, lg, lb) = (lin(r), lin(g), lin(b))
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s]
    }
    static func toSRGB(_ lab: SIMD3<Double>) -> (Double, Double, Double) {
        let l = pow(lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z, 3)
        let m = pow(lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z, 3)
        let s = pow(lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z, 3)
        func enc(_ c: Double) -> Double {
            let v = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(max(c, 0), 1 / 2.4) - 0.055
            return min(1, max(0, v))
        }
        return (enc(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                enc(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                enc(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }
}
```

### 3.3 Les blobs

Coordonnées normalisées : `x` de 0 à 1 sur la largeur, `y` de 0 (haut) à 1 (bas). Les distances verticales sont multipliées par 1,25 (ratio 4:5). `h` = part d'air (altitude).

| Rôle | x | y | σx | σy | rot | poids | couleur |
|---|---|---|---|---|---|---|---|
| Terre | 0,5 ± 0,15 | 1,06 + 0,06 h | 0,78 | 0,30 | ± 0,4 | 1,15 | `ground` |
| Bande de terroir | 0,08 ou 0,92 | 0,90 | 0,28 | 0,18 | ± 0,6 | 0,50 | `tone1` |
| Ciel | 0,5 ± 0,2 | −0,10 | 0,85 | 0,18 + 0,26 h | ± 0,3 | 0,5 + 0,75 h | ciel (§1) |
| Note 1, 2, 3 | composition ± 0,06 | composition ± 0,06 | 0,20 + 0,12 r | 0,18 + 0,12 r | ± 1,5 | 1,00 · 0,86 · 0,74 | couleur d'arôme |
| Encre du sachet | 0,06–0,18 ou 0,82–0,94 | 0,16–0,56 | 0,12 | 0,12 | 0 | 0,62 | HSV(teinte, 0,72, 0,84) |
| Process (honey, fermentation) | 0,2–0,8 | 0,45–0,75 | `extraBlob.sigma` | × 0,9 | ± 1 | `extraBlob.weight` | `extraBlob.color` |

Compositions des notes (une tirée par carte) : `[(0.28,0.36),(0.74,0.52),(0.38,0.72)]`, `[(0.72,0.32),(0.26,0.54),(0.66,0.76)]`, `[(0.50,0.38),(0.18,0.66),(0.84,0.64)]`, `[(0.30,0.28),(0.72,0.44),(0.50,0.70)]`. Moins de trois notes : on complète avec `tone1`, `tone2`. Aucune note : `tone1`, `tone2`, mélange `tone1`/`ground` à 45 % ; l'encre du sachet remplace la première si elle existe. Process `natural` : `a += 0.012`, `b += 0.0072` sur les notes.

### 3.4 Le champ

```swift
func color(u: Double, v: Double) -> SIMD3<Double> {
    var x = u, y = v
    if process.warp > 0 {
        x += process.warp * (Noise.fbm(u * 2.2 + 3.1, v * 2.2, warpSeed) - 0.5) * 2
        y += process.warp * (Noise.fbm(u * 2.2, v * 2.2 + 5.3, warpSeed + 1) - 0.5) * 2
    }
    if process.swirl > 0 {                       // fermentations
        let dx = x - 0.5, dy = (y - 0.55) * 1.25, r = (dx * dx + dy * dy).squareRoot()
        let a = process.swirl * exp(-r * r * 6)
        x = 0.5 + dx * cos(a) - dy * sin(a)
        y = 0.55 + (dx * sin(a) + dy * cos(a)) / 1.25
    }
    var sum = SIMD3<Double>(repeating: 0), total = 0.0
    for b in blobs {
        let dx = x - b.x, dy = (y - b.y) * 1.25
        let rx = (dx * b.cos + dy * b.sin) / b.sx, ry = (-dx * b.sin + dy * b.cos) / b.sy
        let w = pow(b.weight * exp(-0.5 * (rx * rx + ry * ry)), process.sharpness)
        sum += w * b.lab; total += w
    }
    let e = 1e-4
    var lab = (sum + e * blobs[0].lab) / (total + e)
    lab.x += lightness + 0.03 * (1 - v) * h - 0.02 * v      // lightness = roastLightness − process.darken
    lab.y *= chroma; lab.z *= chroma                       // process (× 0,7 si décaféiné)
    return lab
}
```

`warpSeed = seed % 9973`. Bruit de valeur (identique au prototype) :

```swift
nonisolated enum Noise {
    static func hash(_ ix: Int, _ iy: Int, _ s: Int) -> Double {
        func u(_ v: Int) -> UInt32 { UInt32(truncatingIfNeeded: v) }
        var h = (u(ix) &* 374761393) ^ (u(iy) &* 668265263) ^ (u(s) &* 1442695041)
        h = (h ^ (h >> 13)) &* 1274126177
        return Double(h ^ (h >> 16)) / 4_294_967_295
    }
    static func value(_ x: Double, _ y: Double, _ s: Int) -> Double {
        let ix = Int(floor(x)), iy = Int(floor(y)), fx = x - floor(x), fy = y - floor(y)
        let ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy)
        let a = hash(ix, iy, s), b = hash(ix + 1, iy, s), c = hash(ix, iy + 1, s), d = hash(ix + 1, iy + 1, s)
        return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uy
    }
    static func fbm(_ x: Double, _ y: Double, _ s: Int) -> Double {
        0.65 * value(x, y, s) + 0.35 * value(x * 2.03 + 11.1, y * 2.03 + 7.7, s + 7)
    }
}
```

Classement du process (sur la chaîne normalisée, minuscules, sans accents), dans cet ordre : `anaer|carbon|macera|thermal|co ?ferm|infus|lactic|yeast|koji|experimental|double` → fermentation ; `wet ?hull|giling` → wet-hulled ; `honey|miel|pulped|semi ?wash` → honey ; `natur|dry|sun ?dried` → nature ; `wash|lavad|lave|fully` → lavé ; sinon inconnu.

Altitude : les nombres de 3 ou 4 chiffres de la chaîne ; une plage « 1800-1900 » donne la moyenne.

### 3.5 Encre du titre

Première note reconnue (sinon encre du sachet à V 0,5, sinon terre) ramenée à **L = 0,36** en OKLab, chroma plafonné à 0,13. Le titre reste lisible sur le papier de l'étiquette et rime avec le fond.

---

## 4. Le rendu du fond (`CardBackdrop`)

1. **Champ basse définition** : 96 × 120 pixels évalués par `CardArt.color(u:v:)` (11 520 pixels, ~8 blobs). Un dégradé n'a pas de détail : la basse définition est la bonne.
2. **Agrandissement** dans un `CGContext` 1080 × 1350 (tuile 360 pt @3x), `interpolationQuality = .high`.
3. **Symbole** (§5), dessiné ici pour que le grain passe aussi dessus.
4. **Grain** : `ctx.setBlendMode(.overlay)`, `ctx.setAlpha(process.grainOverlay)` (0,30 lavé → 0,58 wet-hulled), `ctx.draw(GrainTexture.tile, in: rect, byTiling: true)`, tuile mise à l'échelle `W / 720`. La tuile : bruit quasi gaussien autour de 128 (± 52) et 1,2 % de projections à ± 70 (l'aérographe).
5. **Vignette** : dégradé radial `multiply`, transparent à 35 % de la largeur, `rgba(60, 40, 25, 0.22)` au bord.
6. **Ton du texte** : luminance moyenne du champ sur `x < 0,75`, `y < 0,36`. Au-dessus de 0,42 → texte encre, sinon papier. Ne sert qu'à la mise en page *Full bleed* et au choix clair/sombre de la trame et du motif.

Pas de Metal, pas de `MeshGradient`, pas de shader : `ImageRenderer` et les tests de snapshot restent sans surprise, et le rendu tourne hors main thread dans `CardComposer`.

### 4.1 Du prototype à CoreGraphics

Le prototype n'utilise que des opérations Canvas 2D qui ont leur équivalent direct :

| Canvas 2D (prototype) | CoreGraphics |
|---|---|
| `globalCompositeOperation = 'multiply' / 'screen' / 'overlay'` | `ctx.setBlendMode(.multiply / .screen / .overlay)` |
| `'destination-out'` (trous, gaufrage) | `.destinationOut` |
| `'source-in'` (teinter un masque) | `.sourceIn`, ou `ctx.clip(to: rect, mask: cgImage)` puis `fill` |
| `globalAlpha` | `ctx.setAlpha(_:)` |
| `createPattern(tile, 'repeat')` | `ctx.draw(tile, in: rect, byTiling: true)` |
| `drawImage` agrandi, `imageSmoothingQuality = 'high'` | `ctx.interpolationQuality = .high` |
| `createRadialGradient` (vignette) | `ctx.drawRadialGradient(_:startCenter:startRadius:endCenter:endRadius:options:)` |
| `ImageData` du champ 96 × 120 | buffer RGBA → `CGContext(data:…)` → `makeImage()` |

---

## 5. Le symbole du sachet

La chaîne complète, une fois par carte, dans `InkStampPipeline.measure` (déjà sur `StampLane`, hors main thread) :

```
scan → PackMark (teinte) ou darkness (Otsu / edgeWork) → portes + refus des mots (OCR)
     → masque antialiasé (§5.1) → MarkVectorizer (§5.2) → stamp-shape.json  (+ stamp.png en repli)
```

### 5.1 Antialiaser le masque

Dans `PackMark.render` et `InkStampPipeline.raster` / `measured` : découper le symbole, **suréchantillonner × 2 à × 4** pour que le côté long atteigne au moins 512 px, flouter le masque (σ ≈ 1,5 px à cette échelle), puis seuil doux : `alpha = clamp((f − 0.35) / 0.30)`. On garde la couleur (26, 24, 21) et l'alpha devient continu. Les portes (couverture, aire, composantes, mots) ne changent pas et se calculent avant.

### 5.2 Vectoriser (dans ce lot)

**Pourquoi** : en fond, une marque est dessinée à 100–135 % de la largeur de la carte, en tuile @3x comme en fiche. Un bitmap de quelques centaines de pixels y flotte ; un tracé reste net à toute taille. Le coût est payé une fois, à la mesure.

```swift
nonisolated struct MarkShape: Codable, Equatable, Sendable {
    static let version = 1
    var version: Int
    /// Largeur / hauteur du crop.
    var aspect: Double
    /// Polygones fermés, coordonnées 0…1, origine en haut à gauche. Remplissage even-odd (les trous sont des contours).
    var contours: [[SIMD2<Float>]]

    /// Coins adoucis : courbe quadratique par les milieux des segments.
    func path(in rect: CGRect) -> CGPath
}

nonisolated enum MarkVectorizer {
    static func vectorize(_ mask: CGImage) -> MarkShape?
}
```

1. **Entrée** : le masque antialiasé de §5.1, posé en encre sur blanc (Vision attend un dessin sombre sur fond clair).
2. **Vision** : `VNDetectContoursRequest` avec `detectsDarkOnLight = true`, `contrastAdjustment = 1.0`, `maximumImageDimension = 1024`, via `VNImageRequestHandler(cgImage:)`.
3. **Tous les contours, trous compris** : parcourir `observation.contourCount` et `observation.contour(at:)`. Chaque contour → `polygonApproximation(epsilon: 0.002)`.
4. **Nettoyage** : écarter les contours de moins de 4 points ou dont la boîte fait moins de 0,04 % de l'aire. Si le total dépasse 4 000 points, refaire avec `epsilon: 0.004` ; s'il dépasse encore, renvoyer `nil`.
5. **Repère** : Vision travaille origine en bas à gauche, on stocke origine en haut à gauche (`y = 1 − y`).
6. **Stockage** : `stamp-shape.json` à côté de `stamp.png` (qu'on garde comme repli et pour *Choose area*). `StampFile.vectorVersion = MarkShape.version`.
7. **Rendu** : `path(in:)` puis `ctx.fillPath(using: .evenOdd)`, antialiasing actif. Les coins sont adoucis : `move(to: milieu(dernier, premier))`, puis pour chaque point `addQuadCurve(to: milieu(pᵢ, pᵢ₊₁), control: pᵢ)`. Ça garde la main du dessin d'origine et efface l'escalier des pixels.
8. **Repli** : si `vectorize` renvoie `nil`, le bitmap antialiasé sert, avec le même traitement.
9. **Pas de vectorisation** pour les logos de bibliothèque (`source == .library`) : ils ne vont pas en fond.

Ordre de grandeur : 30 à 80 ms par marque sur iPhone 13, une seule fois par carte.

### 5.3 Placement

Forme posée dans un calque W × H : largeur `W × (1.00 + 0.35 r0)`, hauteur plafonnée à `1.05 H`, centre `(0.56 + 0.18 r1, 0.30 + 0.14 r2)`, rotation `(r3 − 0.5) × 0.45` rad. Le symbole déborde volontairement du bord et vit au-dessus de l'étiquette. `SymbolLayer` rasterise la forme **à la taille de destination**, puis applique le traitement.

### 5.4 Les quatre traitements (`o = max(2, 0.0055 W)`)

| Traitement | Recette |
|---|---|
| **Emboss** (gaufrage, comme la carte Balbosté ; référence : l'ange de Huabal) | `hl` = masque − masque décalé (+o, +o) ; `sh` = masque décalé − masque. Face : blanc `screen` 0,07. `hl` : `#FFFAF0` `screen` 0,55. `sh` : `#2A1C12` `multiply` 0,50. |
| **Ink** (sérigraphie) | Passe décalée (+1,4 o, −o) dans l'encre du sachet (sinon la note 2), `multiply` 0,28. Passe principale dans la note 1 à L 0,30 (chroma × 0,6), trouée par la tuile de grain (`destinationOut` 0,5), `multiply` 0,62. |
| **Halftone** (trame) | Grille de pas `max(5, 0.016 W)`. Rayon du point `0.52 × pas × √alpha`. Fond clair : note 1 à L 0,32, `multiply` 0,75. Fond sombre : `#FFF3DF`, `screen` 0,70. |
| **Pattern** (motif répété ; référence : Blue Bottle) | Symbole à 15 % de W, pas × 1,55, rangées décalées, rotation −0,21 rad. Fond clair : `#3A2A20` `multiply` 0,20. Fond sombre : `#FFF6E6` `screen` 0,17. Rasteriser la forme une fois à la taille du motif, puis la répéter. |

### 5.5 Auto

- Pas de symbole, ou logo de bibliothèque (`source == .library`, une favicon carrée de 256 px avec son fond) → **rien** en fond.
- Marque minuscule (`areaRatio` < 0,02 du sachet, ou côté long du crop d'origine < 160 px) → **Pattern**. C'est le cas de la bouteille Blue Bottle et du trèfle de Klover (~1 % du sachet, comme le note déjà `PackMark.areaFloor`) : même vectorisée, une marque minuscule se lit mieux répétée qu'agrandie.
- Dessin au trait (couverture < 0,30) → **Emboss** si `r4 < 0.55`, sinon **Ink**.
- Marque pleine → **Emboss** si `r4 < 0.60`, sinon **Halftone**.

### 5.6 Dynamique

Sur la fiche, le gaufrage suit l'inclinaison déjà mesurée par `CardObject` / `Motion.Object` : décaler `hl` et `sh` de ± o selon le tilt, pour que la lumière glisse sur le relief comme le sheen. En tuile, figé.

---

## 6. Les stickers d'origine

### 6.1 Règle

**Un pays = un sticker, toujours le même.** Le sticker ne dépend que du code ISO. La carte ne choisit que le **côté** (droite 68 %, gauche 32 %) et la **rotation** (± 9°). Sans pays, la carte porte le **sceau de son process** (Washed, Natural, Honey, Fermented, Wet-hulled). Sans pays ni process : rien, le fond suffit (*Three Africas* dans le prototype).

### 6.2 Embarqués, pas dessinés au runtime

L'ensemble est fini (42 origines, 5 sceaux) : les pré-rendre revient à les générer, en plus stable, et sans police à embarquer.

- **Livré** : `docs/card-lab/OriginStickers.xcassets`, 47 PNG 480 × 480 avec transparence (256 couleurs, ~1,5 Mo), espace de noms `Stickers/`. Rendus depuis le prototype avec Archivo et DM Serif Display.
- **Intégration** : glisser le catalogue dans le projet, target Kohi. `Image("Stickers/origin-\(iso.lowercased())")` ; sceaux : `Image("Stickers/seal-\(key)")` avec `washed`, `natural`, `honey`, `anaerobic`, `wethulled`. `OriginCode.alpha2(for:)` donne l'ISO, `Terroir.classify(process:)` la clé du sceau.
- **Taille d'affichage** : 40 % de W en tuile (144 pt pour 360 pt), 32 % en fiche. 480 px couvrent @3x.
- **Modifier une recette** : `origin-stickers.json` et `docs/card-lab/src/stickers.js` sont la source ; `node src/render-stickers.js` rerend les 47 PNG (voir `src/README.md`).

### 6.3 Plus tard

- Port natif des recettes (`Canvas` + `Path`, primitives de `src/stickers.js`) : seulement pour des variantes, par exemple des rubans de région.
- Remplacement illustré : un asset `Stickers/origin-<iso>` dessiné à la main remplace simplement le PNG, sans toucher au code.

---

## 7. Design system : ce qui change dans `design-system.md`

- **§3 Couleur**, remplacer « La couleur vive des cartes scannées n'entre toujours pas dans le chrome » par : « **La couleur vit dans l'objet carte** (fond, relief, sticker), **jamais dans le chrome**. Le chrome reste encre et papier. L'étiquette d'une carte Kohi est du papier : texte encre, filet hairline. »
- **Tuile**, remplacer le paragraphe *Deux faces* : « **Kohi cards** (défaut) est un paysage : terre de l'origine en bas, notes au milieu, ciel de l'altitude en haut, grain d'impression ; le symbole du sachet en relief ; une étiquette papier (torréfacteur, titre, lieu) ; le sticker de l'origine collé sur le coin de l'étiquette. Même café, même carte : tout se déduit des champs et de l'identifiant. **Scans** reste l'objet nu, à un tap. »
- **Illustration**, ajouter : « Les stickers d'origine sont des assets générés depuis des recettes en code. Un pays, un sticker. »
- **Cartes sans nom** : `KohiCard` applique la même chaîne que `displayName`.

---

## 8. Mise en page de la carte

Toutes les mesures en part de la largeur `W` de la carte, pour que tuile et fiche partagent un gabarit.

**Label (défaut)** — étiquette papier `#FBF8F2` en bas : marges 5 %, rayon 2,2 %, padding 4 % / 4,4 %, ombre légère, filet intérieur encre à 8 %.
- Tuile : torréfacteur en mono 3,4 % (uppercase, tracking 0,14 em, `inkMuted`) ; titre Angusta 10,6 %, **deux lignes au plus** ; filet hairline ; lieu · altitude à 4 %.
- Fiche : + process · variété (`inkMuted`), *Notes* en label catalogue puis les trois notes, pied mono (*ROASTED … · FROM THE PACK*).
- Sticker : posé sur le coin haut de l'étiquette (~65 % au-dessus). La ligne du torréfacteur laisse 30 % de place côté sticker ; sticker à gauche → torréfacteur aligné à droite.

**Full bleed (option)** — texte directement sur le fond en haut à gauche, titre 14 %, couleur selon le ton (§4, point 6) ; sticker en bas, côté de la graine.

Coins de la carte : 5 % de W (comme `min(18, w × 0.05)` aujourd'hui).

---

## 9. La nouvelle carte devient le standard

### 9.1 Une seule version de la carte

`CardStandard.version = 3` résume tout ce qui change l'image : `KohiCardContent.designVersion`, `CardArt.version`, `InkStamp.pipelineVersion`, `MarkShape.version`, et la version du catalogue de stickers. Monter l'un d'eux monte le standard, change les tokens, et relance la régénération. Il n'y a plus d'ancien gabarit à maintenir.

### 9.2 La carte Kohi par défaut

- `CardLookStore` : défaut `.kohi`.
- Migration unique (`UserDefaults` `display.standard` < 3) : `global = .kohi`. Les choix par carte (`display.cardLooks`) sont gardés : ce sont des décisions explicites.
- Une carte sans scan reste en Kohi (inchangé). Le scan reste à un tap sur la fiche.

### 9.3 Régénérer toute l'archive

`CardRegeneration` démarre dans `RootView.task`, une fois la grille affichée :

1. **Ordre** : les cartes visibles d'abord, puis le reste par date d'ajout. L'archive d'exemple (`SampleArchive`) suit le même chemin.
2. **Pour chaque carte, une à la fois** (`StampLane`, priorité `.utility`) :
   - `InkStampPipeline.backfill` remesure, puisque `pipelineVersion` 2 ≠ 3 : nouveau masque, vectorisation, `stamp-shape.json`. Le **style** et la **zone choisie** (`manualRect`) sont conservés, comme aujourd'hui.
   - `CardComposer.tile(for:)` rend la nouvelle tuile, puis supprime les `kohi-tile-*.png` d'un autre token.
3. **Reprise** : une carte est faite quand `stamp.json` est en version 3 et que la tuile du token courant existe. Si l'app passe en arrière-plan ou se ferme, la passe reprend au lancement suivant, là où elle s'était arrêtée. Une fois tout fait, on note `display.standard = 3` et la passe ne tourne plus.
4. **Pendant la passe** : une tuile pas encore rendue montre son **champ seul** (`KohiCardPlaceholder`, §2.2) et son titre, puis la tuile complète arrive en fondu `Motion.quick`. Pas de papier blanc, pas de barre de progression : la mosaïque se colore.
5. **Les nouvelles cartes** : mesurées et rendues au standard dès l'enregistrement, comme aujourd'hui via `CardTile.task`.
6. **Autres appareils** : les tuiles ne sont pas synchronisées ; chaque appareil régénère de son côté. Le rendu est déterministe, donc le résultat est identique partout.

Ordre de grandeur : ~40 cartes × (décodage du scan + mesure + vectorisation + tuile) ≈ 0,2 à 0,3 s par carte, soit 10 à 15 s en tâche de fond pour une archive comme celle d'aujourd'hui.

---

## 10. Tests et critères d'acceptation

- **Parité** : pour les cinq cartes de `card-art-vectors.json`, la graine et les trois premiers tirages sont identiques au bit près ; `fieldAtCenter` et `fieldAtTop` à ± 2/255 par canal.
- **Déterminisme** : `CardArt.make` deux fois sur la même carte → égal ; deux lancements de l'app → même PNG de tuile (comparer les octets).
- **Palette** : « Winey Blueberry » → blueberry ; « Lemon Grass » → lemongrass ; « Cacao Nibs » → chocolate ; « Stonefruits » → stone fruit ; « Crisp Apple » → apple ; note inconnue → ignorée, pas de couleur inventée.
- **Repli** : sans notes → tons de la terre ; sans pays → terre neutre + sceau ; sans pays ni process → aucun sticker ; nom vide → titre `displayName`.
- **Stickers** : deux cafés kenyans → le même asset ; les 42 codes de `OriginCode` et les 5 sceaux ont leur image dans le catalogue (test qui parcourt la liste).
- **Vectorisation** (fixtures `docs/card-lab/fixtures/marks/` : trèfle, ange, carte de Panama, bouteille) : `vectorize` ne renvoie pas `nil` ; moins de 4 000 points ; la forme rasterisée recouvre le masque d'origine à IoU ≥ 0,95 ; les trous du trèfle et de la carte restent des trous (even-odd). Un masque vide ou du bruit → `nil` et repli bitmap.
- **Symbole** : marque minuscule → Pattern ; favicon de bibliothèque → aucun fond ; *Choose area* puis *Redo* → nouveau `stamp-shape.json`.
- **Standard et migration** :
  - Installation neuve → face Kohi par défaut. Installation existante avec `display.cards = scan` → Kohi une fois ; une carte réglée sur Scan reste en Scan.
  - `stamp.json` v2 avec `style: "sticker"` → `.auto` ; `"watermark"` → `.emboss` ; `manualRect` conservé après la passe.
  - Après la passe sur l'archive d'exemple : chaque carte a `stamp.json` en version 3 et exactement une tuile `kohi-tile-*` (celle du token courant).
  - Passe interrompue après trois cartes → reprise à la quatrième au lancement suivant. Deuxième lancement après une passe complète → `renderCount == 0`.
- **Performance** (iPhone 13) : tuile neuve < 40 ms hors décodage du scan et hors vectorisation ; vectorisation < 80 ms ; mosaïque de 40 cartes à 60 i/s en scroll pendant la passe.
- **Réseau** : `cardRenderingDoesNotCallTheNetwork` reste vert.
- **Snapshots** : les six cartes d'exemple × tuile / fiche × Label / Full bleed ; le placeholder (champ seul).

---

## 11. Ordre d'exécution

1. `CardSeed`, `OKLab`, `AromaPalette`, `Terroir`, `CardArt` (pur) + tests de parité. Rien de visible.
2. `CardBackdrop` + `GrainTexture` + catalogue de stickers, branchés dans `KohiCard` et `CardComposer`. Regarder la mosaïque sur la vraie archive, sans symbole.
3. Symbole : masque antialiasé, `MarkVectorizer`, `SymbolLayer` (quatre traitements), *Style → Symbol*. Tests sur les fixtures.
4. Standard : suppression de l'ancien gabarit, placeholder au champ seul, `CardLook` par défaut et migration, `CardRegeneration`, `CardStandard.version = 3`. **C'est cette étape qui régénère l'archive : elle passe en dernier pour que la passe ne tourne qu'une fois en vrai.**
5. *Full bleed*, gaufrage qui suit l'inclinaison, `design-system.md`.

## 12. Plus tard

- Rubans de région sous le sticker (Yirgacheffe, Huila, Nyeri) : variante par région, toujours déterministe, via le port natif des recettes.
- Sticker *blend* quand le champ pays en cite plusieurs.
- Partage de la carte en image (story) : la carte est déjà un objet fini.
