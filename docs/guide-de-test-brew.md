# Kohi — Guide de test : le parcours d'extraction

**Build** : 20 septembre 2026 · iPhone, iOS 18 minimum
**Durée** : 30 min, dont un vrai café
**Pour** : Timour

Ce guide ne couvre qu'une chose : **brasser**. Les cinq écrans entre « je veux un café » et « voilà ce que ça a donné ». Le reste de l'app (scan, archive, recettes, compte) est dans [le guide complet](guide-de-test.md) ; inutile d'y retourner.

Le parcours a été refait deux fois depuis la dernière version que tu as vue. Ce qui suit dit à chaque étape **ce qu'on a décidé et pourquoi** — parce que plusieurs choix sont discutables, et que c'est exactement là qu'on a besoin de toi.

Trois types de retour, à chaque parcours :

- **Clair ?** — est-ce que tu sais où tu es et quoi faire.
- **À modifier ?** — ce que tu changerais de place, de nom, de taille.
- **Incorrect ?** — un chiffre, une unité, une recette, une traduction qui est faux.

Et un quatrième bloc, **On hésite** : des questions qu'on se pose vraiment et sur lesquelles on n'a pas tranché. Ce sont celles qui nous serviront le plus.

À faire avec ton matériel et ton Option-O si possible. Si tu es bloqué plus de trente secondes, c'est un résultat : note-le et continue.

---

## Ce qui a changé depuis ta dernière session

| | Avant | Maintenant |
| --- | --- | --- |
| Familles | Filter / Espresso (deux onglets) | **Pour Over / Immersion / Espresso** (trois onglets) |
| AeroPress, presse | Sous Filter | Sous **Immersion** |
| Cold brew | Sous Filter | Sous **Immersion** |
| Format (1 cup…) | Sur le premier écran | Retiré du premier écran, dose/eau sur **Today's settings** |
| Recettes | Filtrées sur la méthode exacte | Filtrées par famille : V60 reste visible après un Chemex |
| Accessoires par étape | Absent | Chips d'accessoires dans chaque étape du builder |
| Rinçage | Confondu avec la première étape | **Bloc à part**, skippable, hors chrono et hors débit |
| Papier | Choisi sur Today's settings | Choisi sur **With what**, avec le reste du kit |
| Narrate | Reco live pendant le versement | **Fichier** enregistré, transcrit à la fin |
| Note vocale | Transcription brute | Lexique café local, puis passe d'orthographe IA |

---

## Parcours A — Quelle recette ?

*3 minutes. Le premier écran après « Log a brew ».*

### À faire

1. Ouvre un café et tape **Log a brew**.
2. L'écran dit **Which recipe?**. Regarde les trois onglets : **Pour Over**, **Immersion**, **Espresso**.
3. Bascule sur **Pour Over**. Vérifie que V60, Chemex et Kalita s'y trouvent.
4. Bascule sur **Immersion**. Vérifie que AeroPress et presse française s'y trouvent.
5. Choisis une recette dans **From the pros**.
6. Tape **Edit recipe** s'il apparaît (il apparaît si la recette est à toi). Sinon, tape **Build an express recipe**, donne un nom au café, sauvegarde, et tape **Edit recipe**.
7. Tape **Next**.

### Ce que tu devrais voir

Deux rails : famille (Pour Over / Immersion / Espresso), puis provenance (Last / Mine / From the pros). **Next** est toujours actif. Pas de dose, pas d'eau, pas de format ici — ces chiffres attendent Today's settings.

**Pour Over** : V60, Chemex, Kalita, flat dripper, Moccamaster, cold brew. **Immersion** : AeroPress, presse française, Switch. **Espresso** : espresso machines, moka. Changer de famille change aussi le kit en coulisses.

Si la recette sélectionnée est la tienne (Mine ou Express), **Edit recipe** apparaît en bas. From the pros n'a que **Build an express recipe**.

### Parti-pris

**La recette d'abord, les quantités après.** L'écran ne pose qu'une seule question : *laquelle* ? Le *combien* vient à l'écran 4 (Today's settings), où la recette se rescale selon ce que tu tapes.

**Trois familles, pas deux.** AeroPress et presse française ne sont pas du « Pour Over » — ce sont des immersions. Les regrouper corrigeait la confusion que tu avais signalée.

**Deux rails plutôt qu'une liste unique.** Famille et provenance sont deux questions différentes. Les fondre en une liste classée nous obligeait à arbitrer à ta place.

---

## Parcours B — Avec quoi

*3 minutes.*

### À faire

1. Depuis A, tape **Next**. Tu es sur **With what?**.
2. Vérifie l'onglet actif : il doit correspondre à la famille choisie à l'écran précédent (Pour Over / Immersion / Espresso).
3. Tape **Change** sur **Dripper**. Parcours la liste, choisis autre chose.
4. Reviens : l'onglet et la méthode doivent avoir suivi ton choix.
5. Tape **Change** sur **Grinder**, puis sur **Filter**.
6. Si tu as déclaré des accessoires dans Profile, vérifie qu'une rangée **Accessories** apparaît avec des chips multi-sélectionnables.
7. Bascule sur **Espresso**. Regarde ce que deviennent les rangées.
8. Rebascule sur **Pour Over**.

### Ce que tu devrais voir

Trois rangées, toujours les trois : **Dripper** (ou **Machine** côté espresso), **Grinder**, **Filter**. Chacune ouvre le même catalogue : **From your kit** en haut, puis le reste groupé par sous-famille, puis **Add manually**.

Côté espresso, les papiers sont des **disques** de portafiltre, pas des cônes. Sur une moka ou une presse, la rangée Filter reste visible et dit *« No paper for a Bialetti Moka Express »* — elle ne disparaît pas.

Choisir un dripper change la méthode du brew. Choisir un V60 doit te ramener sur Filter, même si tu étais sur Espresso.

### Parti-pris

**Une affordance ne disparaît jamais sur une condition calculée.** La rangée Filter reste à l'écran avec sa raison, plutôt que de s'évanouir quand le matériel ne prend pas de papier. Une rangée absente se lit comme un bug ; une rangée qui explique se lit comme une réponse.

**Le kit est regroupé ici, pas dispersé.** Dripper, grinder, papier : trois choses de la même nature (des objets que tu possèdes) sur un seul écran. Ce qui change d'un café à l'autre est à l'écran suivant.

**Un seul catalogue pour les trois.** Même grammaire, même recherche, même « Add manually », qu'on cherche un dripper ou un papier.

### Questions

1. **Clair ?** Les trois rangées suffisent, ou il manque quelque chose que tu poses sur le comptoir ?
2. **À modifier ?** « Dripper » devient « Machine » côté espresso. Bon mot dans les deux cas ?
3. **Incorrect ?** Ton matériel est-il dans le catalogue, au bon nom, avec la bonne sous-famille ? Note ce qui manque.

---

## Parcours C — Les réglages du jour

*3 minutes. C'est l'écran de ta question sur les clics.*

### À faire

1. Tape **Next**. Tu es sur **Today's settings**.
2. Si une recette est attachée, tu vois `RECIPE · nom · EDIT`. Tape **Edit**. La feuille de séquence s'ouvre.
   - Change le nom de la recette.
   - Change la dose. Vérifie que l'eau ne bouge pas toute seule.
   - Change une masse d'étape. Si la dernière masse ne correspond plus à l'eau, un bouton **Rescale steps** apparaît.
   - Tape **Save**. La ligne Recipe sur Today's settings montre le nouveau nom.
3. Lis la ligne de rappel en bas : `with … · …`. Tape **Change** pour la déplier.
4. Regarde **Water** : profil et température dans le même bloc.
5. Va sur le rail de mouture. Fais glisser. Tape le nombre à droite et change-le au clavier.
6. Si tu vois **Set your range**, tape dessus et déclare ta plage pour cette méthode.
7. Sors, va dans **Profile › Convert a setting** et regarde ce qu'il te propose.

### Ce que tu devrais voir

Trois blocs : le kit en rappel, l'eau, la mouture. Le papier **n'est plus ici** — il est resté à l'écran précédent.

Si ton broyeur a une plage déclarée pour la méthode, le rail est en **clics** avec le nombre à droite et un µm indicatif dessous. Sinon, sept crans (Fine → Coarse) et **Set your range**.

### Parti-pris

**Eau et température ensemble, mouture à part.** L'eau et sa température sont une seule décision ; la mouture en est une autre, et c'est celle que tu ajustes le plus souvent. D'où le rail seul, avec de la place.

**On n'invente pas un nombre de clics.** Toute traduction affichée porte son fondement : *from your calibration*, *from your ranges*, *from range*, *from maker step* — et toujours un `≈`. Un chiffre déduit d'une plage publiée et un chiffre issu de ta propre calibration ne valent pas la même chose, et les afficher pareil serait la chose la plus trompeuse qu'on puisse faire ici.

### Questions

1. **Clair ?** Le rail en sept crans quand il n'y a pas de plage — tu comprends que c'est une position relative, pas une valeur ?
2. **À modifier ?** En éditant une recette : est-ce que tu savais où chercher ce bouton ? Et **Rescale steps** — tu comprends sans explication ce qu'il fait ?
3. **Incorrect ?** Si tu vois un µm indicatif, est-il crédible pour ton broyeur ?

### On hésite

> **Une table de correspondance entre broyeurs.** C'est ta question, et voilà où on en est exactement.
>
> La machinerie existe : Kohi sait traduire un réglage d'un broyeur vers un autre, par quatre chemins (ta calibration, tes plages déclarées, la plage publiée pour la méthode, les µm/cran du fabricant). Il y a même un convertisseur dans **Profile › Convert a setting**.
>
> Mais la base est presque vide. Sur **187 broyeurs** référencés : **8** déclarent un type de réglage (clics / dial / stepless), **5** ont des µm par cran — J-Ultra 8 µm, K-Ultra 20, X-Ultra 12,5, K2 18, KINGrinder K6 16 — et **aucun** n'a de plage par méthode. **L'Option-O Lagom n'a ni type de réglage, ni µm par cran.** C'est pour ça que tu tombes sur sept crans et « Set your range » plutôt que sur des clics.
>
> Trois options, dis-nous laquelle vaut le coup :
>
> 1. **Seeder les plages des 15–20 broyeurs les plus courants** (Comandante C40, 1Zpresso J/K/X, Timemore C2/C3, Baratza Encore, Fellow Ode, Niche Zero, Option-O, DF64, EK43…) avec une plage indicative par méthode. Rapide, mais ce sont des chiffres d'internet, pas des mesures — et ils seraient affichés à côté des tiens.
> 2. **Ne rien seeder, mais rendre « Set your range » beaucoup plus visible**, une fois, au moment où tu déclares ton broyeur. Deux nombres à donner, et ensuite tout marche pour *toi*.
> 3. **Une table de comparaison consultable**, hors parcours d'extraction, dans Profile : « 22 clics sur ton J-Ultra ≈ 8,5 sur un Comandante », avec la marge affichée. Utile pour lire une recette d'internet, mais ça n'aide pas Kohi à pré-remplir.
>
> **Ce dont on a besoin de toi** : ta plage Option-O pour V60 et pour espresso (le réglage le plus fin et le plus grossier que tu utilises vraiment), et ton avis sur la 1 — est-ce qu'une plage approximative vaut mieux que pas de plage, ou est-ce que ça décrédibilise le reste ?

---

## Parcours D — Pendant l'extraction

*10 minutes. À faire en brassant réellement, téléphone posé.*

### À faire

1. Tape **Brew**.
2. Premier bloc : **Rinse**. Rince ton papier, puis tape le bloc. Ou tape **Skip** si tu ne rinces pas. Note **quand** le chrono démarre.
3. Suis la séquence. Tape le bloc pour passer au suivant. Laisse une étape s'avancer toute seule.
4. Pendant un versement, regarde `to 300 g` / `now 168 g` et le tag de débit.
5. Tape **Narrate**. Dis à voix haute ce que tu fais, **en français**, y compris un écart : *« finalement je fais des versements de 40 au lieu de 50 »*.
6. Continue le brew en parlant. Tape à nouveau pour arrêter, ou laisse tourner.
7. **Refais un brew plus tard en anglais**, avec un mot technique dedans (*bloom*, *V60*, *Cafec*, *clicks*).
8. Termine par **Stop**, ou laisse la séquence finir.

### Ce que tu devrais voir

Un seul bloc à l'écran à la fois. Le rinçage est **hors chrono** : le temps ne part qu'en quittant ce bloc, et le rinçage ne compte ni dans le temps total ni dans le débit.

Narrate enregistre un **fichier**. Il continue si tu verrouilles le téléphone, si tu prends un appel, si tu branches des AirPods. Le texte n'apparaît qu'à la fin, sur It's done.

### Parti-pris

**Narrate est un enregistrement, pas une reconnaissance en direct.** La reco live pendant qu'on verse coupait dès qu'on posait le téléphone, et vidait la batterie. Un fichier transcrit à la fin est moins impressionnant mais ne rate rien.

**Le rinçage est une étape à part entière.** Il a une masse, il prend du temps, et il ne fait pas partie de l'extraction. Le compter dans le temps total faussait tous les débits.

**Le timer garde le temps, la narration garde la masse.** Si tu dis « 40 au lieu de 50 », c'est la masse dite qui gagne, mais le temps enregistré par le chrono qui reste. Le chrono sait mieux quand ; toi tu sais mieux combien.

### Questions

1. **Clair ?** Bouilloire en main, téléphone posé : est-ce que tu vois ce qu'il faut faire *maintenant*, sans te pencher ?
2. **À modifier ?** L'avance automatique après 3 s — trop tôt, trop tard, pile ?
3. **Incorrect ?** Relis la transcription sur It's done. Quels mots sont faux ? Cite ce que tu as dit et ce qui s'est écrit — surtout les mots de café.

### On hésite

> **L'écran du brew est trop chargé.** On en est conscients. En ce moment il porte : l'action, la masse cible, la masse instantanée, l'agitation, la barre de progression, auto/manual, « next: … », le tag de débit en direct, Narrate, son chrono, Skip, et Stop. C'est beaucoup pour un écran qu'on regarde du coin de l'œil avec une bouilloire pleine.
>
> Ce qu'on envisage de retirer du champ pendant le versement : le tag de débit (il est déjà recalculé à la fin), « next », auto/manual. Resteraient l'action, les deux masses, le chrono, Narrate, Stop.
>
> **Dis-nous ce que tu as réellement regardé** pendant le café, et ce que tu n'as jamais lu. On coupera là-dedans.

> **La transcription et l'orthographe.** Deux passes maintenant : un lexique café local (gratuit, sur le téléphone — `v 60` → V60, `aero press` → AeroPress, plus les noms de ton matériel), puis une passe IA qui ne corrige *que* l'orthographe, avec ton vocabulaire en contexte. Elle ne réécrit pas, ne résume pas, ne change pas les chiffres.
>
> La question : est-ce que ça suffit, ou est-ce qu'il faudrait la laisser reformuler franchement (« Boeing, moi je fais juste, par contre plutôt j'ai… » → une phrase lisible) ? Reformuler lit mieux, mais ce n'est plus ce que tu as dit.

---

## Parcours E — It's done

*5 minutes. L'écran le plus discuté.*

### À faire

1. Arrivé sur **It's done**, ne touche rien pendant dix secondes. Regarde ce qui se remplit tout seul.
2. Lis **Summary** puis **What you did** : la transcription y est, puis les étapes avec leurs masses.
3. Regarde la **courbe de versement**.
4. Donne un **Rating**.
5. Déplie **Taste** et bouge trois curseurs. Vérifie que la page ne part pas en biais quand tu glisses.
6. Ajoute deux **Flavors** dans *In your cup*.
7. Renseigne **Correction** : − · + sur acidité, amertume, corps.
8. Lis enfin **Suggested correction**. Choisis un mouvement.
9. **Save**.

### Ce que tu devrais voir

De haut en bas : complétude, Summary, ce que tu as fait, la courbe, rating, taste, flavors, correction, comment, suggestion, TDS / yield / save as recipe, date, Save.

Les curseurs de taste doivent glisser sans emmener la page avec eux. La page ne doit pas pouvoir se balader latéralement.

### Parti-pris

**Save marche avec un rating seul.** Tout le reste est optionnel. Une pastille dit ce qui manque, elle ne bloque rien.

**Le radar montre le brew précédent en dessous, jamais comme valeur par défaut.** Un tracé pré-rempli te ferait valider l'avis de l'app au lieu de donner le tien.

**La suggestion propose au maximum trois mouvements, une variable chacun.** Pas une liste de conseils : trois choses classées, du plus doux au plus fort. Hors ligne, une seule, issue de la règle.

### Questions

1. **Clair ?** Après Save, la ligne du brew sur la fiche porte-t-elle bien le nom de la recette, jamais celui du dripper ?
2. **À modifier ?** Les sept axes de Taste : utilisable, ou du travail ? Et la ligne Correction (− · +) fait-elle doublon avec eux ?
3. **Incorrect ?** La suggestion te paraît-elle juste pour le café que tu viens de boire ? Écris ce qu'elle a proposé, et ce que toi tu aurais changé.

### On hésite

> **Couper l'écran en deux.** C'est la piste qu'on préfère aujourd'hui, et on veut ton avis avant de la construire.
>
> L'écran mélange deux moments qui n'ont rien à voir. D'abord **tu décris** : ce que tu as fait, ce que tu as goûté, ta note. Ensuite **l'app analyse** : la courbe, la suggestion de correction, le TDS, la comparaison. Aujourd'hui les deux sont empilés, et la suggestion apparaît pendant que tu es encore en train de remplir tes axes — c'est-à-dire qu'elle se met à jour sous tes doigts, à partir de données incomplètes.
>
> La proposition : **It's done** ne garde que le feedback (résumé, ce que tu as fait, rating, taste, flavors, correction, comment) et **Save**. Le retour de l'app — suggestion, courbe, comparaison, insights — arrive **après**, sur un écran ou un bloc qui s'ouvre au moment où tu sauves. Un temps pour dire, un temps pour lire.
>
> Le risque : un écran de plus dans un parcours qui en a déjà cinq, et une suggestion qu'on ne voit plus si on ferme trop vite.
>
> **Dis-nous** : à quel moment tu as lu la suggestion pendant ton test ? Avant ou après avoir tout rempli ? Et est-ce que tu l'aurais cherchée si elle n'avait pas été là ?

---

## Parcours F — Le deuxième café (optionnel)

*5 minutes. Seulement si tu as fait D et E.*

### À faire

1. Rouvre le même café, tape **Brew again**.
2. Regarde ce qui est déjà rempli — et notamment si le mouvement que tu avais choisi a été appliqué.
3. Refais le café, note-le, **Save**.
4. Ouvre un brew et tape **Compare**.

### Ce que tu devrais voir

**Brew again** repart de la dernière extraction, **déjà ajustée** de la correction que tu avais acceptée. C'est le geste central de l'app : deuxième café, un seul paramètre a bougé.

### Questions

1. **Clair ?** As-tu compris que l'ajustement était déjà appliqué, ou découvert par hasard ?
2. **À modifier ?** Faudrait-il le dire explicitement (« grind 2 clics plus fin, comme tu l'avais choisi ») ?
3. **Incorrect ?** L'ajustement appliqué correspond-il à ce que tu avais choisi ?

---

## Pour finir

À répondre d'une traite, sans relire le guide.

1. **Combien de gestes entre « je veux un café » et « je verse » ?** Trop, juste, pas assez ? Où aurais-tu voulu sauter une étape ?
2. **Quel écran rouvrirais-tu demain matin sans qu'on te le demande ?** Et lequel tu ne veux plus voir ?
3. **Qu'est-ce qui manque ?** Un geste cherché qui n'existe pas, une information attendue quelque part et absente.

Et le vocabulaire, parce que l'app est en anglais et que les mots ont été choisis un par un :

> `What you're doing` · `With what` · `Today's settings` · `Narrate` · `What you did` · `Rinse` · `Set your range` · `For your grinder` · `Suggested correction` · `Brew again`
>
> Lesquels te font hésiter, même une seconde ?

---

## Signaler un problème

```
Écran          : Today's settings
Appareil       : iPhone 15 Pro, iOS 26.1
Ce que j'ai fait : tapé Filter après une moka
Attendu        : les recettes V60 apparaissent
Obtenu         : rien ne bouge
Bloquant ?     : oui
```

Une capture vaut trois paragraphes. Une vidéo de trois secondes en vaut dix.

**Connu, pas la peine de le signaler** : le minuteur n'a pas de cadran circulaire ; pas de thème sombre ; pas d'iPad ; la recette 4:6 n'a pas été retravaillée.

**Build 6.** Le rinçage ne lance plus le chrono : un 3-2-1 part après. L'attente se lit comme une marée, pas comme un versement. Today's settings choisit Auto, Manual ou Cues, et le format (1 cup, 2 cups, Batch, Custom) avec une ligne « Scaled from » quand l'eau du jour diffère de la recette. Save ouvre Read (courbe, correction figée, comparaison). Brew again est un bouton, et la correction choisie est déjà appliquée, avec Keep et Undo. Le papier ajouté reste dans la liste. Un swipe supprime un café, avec Undo. La transcription se corrige avant Save.

---

## Annexe — Le clavier dans Steps (11 novembre)

### Reproduction sur simulateur

iPhone 16, iOS 18.2, clavier logiciel (Simulator > I/O > Keyboard > Connect Hardware Keyboard désactivé). Lancement de debug, sans toucher l'écran :

- `SIMCTL_CHILD_KOHI_KEYBOARD=sheet` ouvre Steps au-dessus de la grille, comme depuis une recette (RecipeEditSheet, BrewScopeView express ou New recipe, copie depuis RecipeDetailSheet) ;
- `SIMCTL_CHILD_KOHI_KEYBOARD=after` ouvre It's done dans le parcours, puis Steps depuis « Edit » de What you did.

Dans les deux cas, le champ At de la dernière étape prend le focus.

| | Feuille seule | Depuis It's done |
| --- | --- | --- |
| Avant | ![](keyboard-repro/avant-feuille.png) | ![](keyboard-repro/avant-its-done.png) |
| Après | ![](keyboard-repro/apres-feuille.png) | ![](keyboard-repro/apres-its-done.png) |

### Ce qu'on a vu, avant correction

- Le champ en cours colle à la barre du clavier : Note, Cue et la suite de l'étape sont cachés dessous.
- `fieldKeyboardClearance()` ne faisait rien : `Motion.Field.keyboardClearance` vaut 0, et les champs At, Until, Note et Cue ne signalaient pas leur focus.
- Faire défiler ne fermait pas le clavier ; un pavé numérique (Dose, Water, Mass) n'a pas de touche Retour, Done était la seule sortie.
- Done existait bien, une seule fois dans les deux contextes (pas de doublon avec la barre de StepFlow observé) — mais petit et gris, il ne se lisait pas comme une touche.
- Le total « Last pour » et l'avertissement « Steps reach … » étaient en bas du contenu, invisibles sans tout faire défiler.

### Corrigé

- Défiler ferme le clavier (`scrollDismissesKeyboard(.interactively)`), un tap sur le fond aussi.
- Le champ At ou Until en cours remonte au tiers haut, le reste de l'étape visible dessous.
- Le total et l'avertissement sont en pied de feuille, toujours visibles, et s'effacent tant que le clavier est ouvert.
- Done est à l'encre, cible de 44 pt, partout où `keyboardDoneButton()` est utilisé.

### À valider sur appareil (JB)

Le simulateur ne peut pas taper pour nous ici. À vérifier à la main : Done ferme bien le pavé numérique dans les quatre chemins ; le défilement interactif ne gêne pas le glisser des compteurs ; un tap sur une chip pendant l'édition fait ce qu'il doit (sélection, pas seulement fermeture du clavier).
