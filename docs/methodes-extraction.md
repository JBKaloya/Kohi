# Méthodes d'extraction — wording et classement

**Date** : 8 novembre 2026 · **Décisions** : JB, 8 novembre (13 h 49 à 14 h 15) · **Build** : 13

Ce document est la référence unique pour nommer et ranger les méthodes d'extraction, côté tasting comme côté brew. Un test (`MethodsDocTests`) vérifie que chaque cas de `TastingMethod` et chaque `BrewerType` y figure : tout nouveau cas doit d'abord être rangé ici.

---

## 1. La règle

Un seul classement, partagé par le tasting et le brew, en quatre familles. Le tasting ajoute **Other** pour tout ce qui n'entre nulle part.

| Ordre | Famille | Ce qu'elle regroupe | Pourquoi |
| --- | --- | --- | --- |
| 1 | **Hand brew** | Tout ce qui demande une opération manuelle : V60, Flat dripper, Chemex, AeroPress, French press, Immersion | Le critère est le geste, pas la percolation ou l'immersion |
| 2 | **Batch brew** | La machine à batch | Non manuel, à côté |
| 3 | **Espresso** | La machine espresso et la Moka | La Moka reste du côté espresso |
| 4 | **Cold brew** | Le cold brew | Famille à part, pour qu'on la découvre |
| — | **Other** (tasting seulement) | Texte libre | Timour s'en est servi ; le texte est conservé |

L'ordre est le même partout : sélecteur « How was it made? » du tasting, onglets « Which recipe? » et « With what » du brew.

Tous les libellés restent en anglais, comme le reste de l'app.

---

## 2. Les appareils (`BrewerType`)

| `BrewerType` | Libellé | Famille | `BrewMethod` enregistrée | Séquence par défaut |
| --- | --- | --- | --- | --- |
| `v60` | V60 | Hand brew | `v60` | percolation |
| `flat` | Flat dripper | Hand brew | `filter` | percolation |
| `chemex` | Chemex | Hand brew | `filter` | percolation |
| `aeropress` | AeroPress | Hand brew | `aeropress` | AeroPress |
| `immersionSwitch` | Immersion | Hand brew | `filter` | immersion |
| `frenchPress` | French press | Hand brew | `frenchPress` | immersion |
| `batch` | Batch | Batch brew | `filter` | batch |
| `espresso` | Espresso | Espresso | `espresso` | espresso |
| `moka` | Moka | Espresso | `moka` | moka |
| `coldBrew` | Cold brew | Cold brew | `coldBrew` | cold brew |

La séquence par défaut du minuteur dépend de l'appareil, pas de la famille (`DefaultSequence.make`). Le changement de classement ne la touche pas.

---

## 3. Les méthodes enregistrées (`BrewMethod`)

`BrewMethod` est ce qu'un brew et une recette enregistrent ; elle est fixée par une contrainte en base. Le classement n'y ajoute aucune valeur.

| `BrewMethod` | Libellé | Famille |
| --- | --- | --- |
| `v60` | V60 | Hand brew |
| `filter` | Pour Over | Hand brew, ou Batch brew avec l'appareil Batch |
| `aeropress` | AeroPress | Hand brew |
| `frenchPress` | French Press | Hand brew |
| `espresso` | Espresso | Espresso |
| `moka` | Moka | Espresso |
| `coldBrew` | Cold Brew | Cold brew |

**Le cas `filter`.** Un batch brew est enregistré `filter`, comme un Flat dripper, une Chemex ou une Immersion. La méthode seule ne sépare donc pas Hand brew de Batch brew. La famille d'un brew se lit dans cet ordre :

1. l'appareil quand il est connu (`BrewerType.family`) ;
2. sinon l'onglet que tu viens de choisir, s'il est compatible avec la méthode (`BrewSession.familyHint`) ;
3. sinon la méthode (`BrewMethod.family`) : `filter` sans appareil donne Hand brew.

Une recette `filter` apparaît donc dans Hand brew et dans Batch brew.

---

## 4. Le tasting (`TastingMethod`)

Le tasting ne stocke pas `TastingMethod` tel quel : chaque cas est traduit en `method`, `brewer`, `isBatch` et `methodNote`, synchronisés par `TastingRow`. Aucun cas ne demande de migration.

| `TastingMethod` | Libellé | Famille | `method` | `brewer` | `isBatch` |
| --- | --- | --- | --- | --- | --- |
| `handBrew` | Hand brew | Hand brew | `filter` | — | non |
| `v60` | V60 | Hand brew | `filter` | `v60` | non |
| `kalita` | Flat dripper | Hand brew | `filter` | `flat` | non |
| `chemex` | Chemex | Hand brew | `filter` | `chemex` | non |
| `aeropress` | AeroPress | Hand brew | `aeropress` | `aeropress` | non |
| `frenchPress` | French press | Hand brew | `frenchPress` | `frenchPress` | non |
| `batch` | Batch brew | Batch brew | `filter` | — | oui |
| `espresso` | Espresso | Espresso | `espresso` | `espresso` | non |
| `moka` | Moka | Espresso | `moka` | `moka` | non |
| `coldBrew` | Cold brew | Cold brew | `coldBrew` | `coldBrew` | non |
| `other` | Other | Other | — | — | non, texte dans `methodNote` |

La valeur brute `kalita` est conservée : elle n'est jamais enregistrée, et seul le libellé devient « Flat dripper ».

**Relecture.** Un tasting enregistré se relit d'abord par `isBatch`, puis par l'appareil, puis par la méthode : `filter` sans appareil donne `handBrew`, `frenchPress` donne French press, `moka` donne Moka, `coldBrew` donne Cold brew. Avant le build 13, ces combinaisons étaient relues comme « aucune méthode », ou Other avec une note. Un ancien tasting en filtre sans dripper s'affiche désormais « Hand brew » ; c'est voulu (Q15).

### Le sélecteur

- Premier niveau, dans cet ordre : Hand brew, Batch brew, Espresso, Cold brew, Other.
- Second niveau, seulement après Hand brew (V60, Flat dripper, Chemex, AeroPress, French press) ou après Espresso (Machine, Moka).
- Sous Hand brew, il est facultatif : la famille seule veut dire « appareil non précisé ».
- Sous Espresso, la famille seule veut dire machine espresso : la puce **Machine** s'allume dès qu'on tape Espresso, et Moka la remplace. La puce dit « Machine » et non « Espresso » pour ne pas répéter la famille juste au-dessus ; l'affichage reste « Espresso ».
- Un nouveau tap sur le choix du second niveau revient à la famille seule (sous Espresso, à Machine) ; un nouveau tap sur la famille revient à « aucune méthode ».
- Other ouvre son champ de texte libre.

### L'affichage

Règle : « famille · appareil » quand un appareil est choisi, la famille seule sinon. Le résumé (`detailSummary`), la liste et le détail (`Tasting.methodLine`) suivent la même règle.

| Cas | Affiché |
| --- | --- |
| Hand brew seul | Hand brew |
| V60 | Hand brew · V60 |
| Flat dripper (ex-Kalita) | Hand brew · Flat dripper |
| Chemex | Hand brew · Chemex |
| AeroPress | Hand brew · AeroPress |
| French press | Hand brew · French press |
| Immersion (brew à la maison) | Hand brew · Immersion |
| Batch | Batch brew |
| Espresso | Espresso |
| Moka | Espresso · Moka |
| Cold brew | Cold brew |
| Other | le texte libre |

---

## 5. Le brew

- **Onglets** « Which recipe? » et « With what » : Hand brew, Batch brew, Espresso, Cold brew (`BrewKit.journeyTabs`).
- **Titre de la ligne matériel** (`kitTitle`) : « Dripper » pour Hand brew, Batch brew et Cold brew ; « Machine » pour Espresso. C'est l'interprétation retenue de « on parlerait plutôt de dripper », à reconfirmer.
- **Méthode de repli** d'un onglet sans matériel (`BrewKit.fallbackMethod`) : V60 pour Hand brew, `filter` pour Batch brew, Espresso, Cold brew.
- **Recettes express** : leur nom prend le libellé de la famille (« Hand brew · 8 Nov »). Les recettes déjà enregistrées gardent leur nom (« Pour Over · 8 Nov »).
- **Filtres de recettes** (`DripperChip` : V60, Flat, Chemex, AeroPress, Immersion, Espresso) : inchangés. Ils filtrent par méthode, pas par famille. Deux écarts sont assumés : la puce dit « Flat » et non « Flat dripper », et il n'y a pas de puce Batch, Cold brew ou Moka.
- **Le mot « Batch »** désigne aussi un format sur Today's settings (1 cup, 2 cups, Batch, Custom). Ce format est une quantité, pas une famille.

---

## 6. Les mots lus sur un menu

`TastingMethod(word:)` reconnaît, après pliage des accents et de la casse :

| Mots | Méthode | Famille |
| --- | --- | --- |
| espresso, expresso, ristretto | Espresso | Espresso |
| v60, hario, hariov60 | V60 | Hand brew |
| kalita, kalitawave, wave | Flat dripper | Hand brew |
| chemex | Chemex | Hand brew |
| aeropress | AeroPress | Hand brew |
| batch, batchbrew, filtre, filter, drip | Batch brew | Batch brew |

« filtre », « filter » et « drip » restent dans Batch brew : c'est ce que ces mots désignent d'ordinaire sur la carte d'un café (Q17, à reconfirmer).

---

## 7. L'ancien classement

Avant le build 13, le placard et les recettes rangeaient le matériel en trois familles, et le tasting n'avait pas de familles.

| Appareil | Avant (placard) | Maintenant |
| --- | --- | --- |
| V60, Flat dripper, Chemex | Pour Over | Hand brew |
| Batch | Pour Over | Batch brew |
| AeroPress, French press, Immersion | Immersion | Hand brew |
| Cold brew | Immersion | Cold brew |
| Espresso, Moka | Espresso | Espresso |

`BrewerFamily` n'est enregistré nulle part : il est recalculé à partir de l'appareil ou de la méthode. Le changement ne demande donc aucune migration de données.

---

## 8. Questions à reconfirmer

- **Q17** : « filtre », « filter » et « drip » restent dans Batch brew.
- **Titre « Dripper »** pour Batch brew et Cold brew dans « With what ».
