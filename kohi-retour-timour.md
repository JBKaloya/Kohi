# Retour à Timour — parcours d'extraction, build 6

Ce qui suit répond aux commentaires du 26 septembre. Trois colonnes : corrigé, existait déjà mais mal montré, maintenu et pourquoi. Rien ici n'est un engagement sur le LABO ni sur le contournement du parcours.

## Corrigé

- **Brew again** est un bouton plein sur It's done, et un bouton sur la ligne du café. L'appui long reste un raccourci.
- **La correction choisie part avec le café suivant.** Si tu as pris « grind coarser », le prochain café s'ouvre déjà décalé, avec la ligne « Applied from your last brew » et Keep · Undo. Pas de fenêtre modale.
- **Saisie de l'eau.** Taper 250 par-dessus 300 ne fait plus défiler de ratios intermédiaires. Le nombre est pris au moment où tu quittes le champ.
- **Le scroll des rails.** Glisser pour faire défiler ne déplace plus le point sur l'axe. Un tap choisit, un drag assez long déplace.
- **Un café rouvert est en lecture.** Les rails sont verrouillés, avec « Saved · tap Edit to change ».
- **Le papier ajouté à la main reste.** Il n'est plus retiré quand tu changes de dripper s'il est encore compatible, et un papier incompatible reste visible, marqué « not for this dripper ». Le bandeau dit « Added to your papers ».
- **Supprimer un café** se fait par un glissement sur la ligne, avec Undo pendant cinq secondes.
- **Le rinçage ne lance plus le chrono.** Le 3-2-1 part après le rinçage, ou au premier bloc si tu passes. Un tap saute le décompte. En mode Cues, le décompte est remplacé par le repère de l'étape.
- **L'attente se lit comme une attente.** Masse qui descend, « next pour at 1:15 », pas de débit, pas de masse cible.
- **Auto, Manual, Cues** sont un choix sur Today's settings. Cues montre le repère (temps, masse, un texte, une odeur). Pas de détection par la caméra.
- **L'écran Total brew time** dure une seconde, ou un tap.
- **Pendant un versement**, il reste l'action, les deux masses, l'horloge, le prochain versement en grand, Narrate et Stop. Le débit en direct, le libellé auto/manual et la barre fine sont partis. Les débits restent dans la courbe.
- **Les accessoires** apparaissent sur le rinçage (« Switch closed · WDT ») et comme un tag d'étape (« with Melodrip »). Rien à saisir pendant le café.
- **Le nom de la recette** est le premier champ, avec « Name this recipe ».
- **Le format** (1 cup, 2 cups, Batch, Custom) vit sur Today's settings, pas sur l'écran du choix de recette. La recette garde ses masses nominales. Une ligne « Scaled from 250 g → 500 g » apparaît quand l'eau du jour diffère, avec Reset. Le rinçage n'est jamais mis à l'échelle. Au-delà de cinq fois, ou en dessous d'un cinquième, Kohi dit « Too far from the recipe — edit the recipe instead » et ne recalcule pas en silence. Brew reste disponible.
- **Read** s'ouvre après Save : courbe, correction figée au moment de Save, comparaison, TDS et rendement, Brew again, Done. It's done reste l'écran où tu décris. La correction ne bouge plus tant que tu ne réenregistres pas. Sans note, la comparaison dit « Add a rating to compare later ». Read se rouvre depuis la ligne du café.
- **Log your range** est le libellé quand tu déclares un broyeur. Les plages publiées (1Zpresso, Comandante, Baratza, Fellow, Niche, Mahlkönig, Wilfa, Timemore) s'affichent en « ≈ · from … ». Ta plage gagne toujours. K-Plus, K-Max et K-Pro n'ont pas de plage : le tableau publié compte en points de 10 clics, ces trois-là en 90 clics par tour. Une plage fausse vaudrait moins que l'absence.
- **La note de dégustation** est lue avant d'entrer dans les règles. « manque de douceur, trop peu de complexité » donne deux intentions, avec la ligne « Understood: … ». Rien n'entre dans le diagnostic sans être passé par cet écran.
- **Les graphiques** portent une légende. La couleur n'apparaît que lorsque deux séries se superposent, et seulement la paire déjà utilisée pour comparer deux cafés. Une série seule reste encre.
- **L'eau en mode recette** propose une dose. Third Wave Water Classic à 50 ppm : un stick fait environ 150 ppm dans 3,8 L, donc « mix 1 part with 2 parts pure water ». Un produit dont la composition n'est pas au dossier le dit, et laisse la saisie manuelle. Lotus n'est pas calculé : la fiche décrit quatre concentrés, pas une dose unique.
- **La transcription** se corrige sur It's done. En dessous, « What we understood » reprend les écarts (« au lieu de », « plutôt que », « finalement », « instead of », « rather than », « actually »).
- **Le sélecteur de méthode** a quitté le constructeur de recettes. La méthode est choisie avant.
- **UFO** est une forme de filtre à part. L'angle n'est pas tranché.
- **Les broyeurs** du catalogue sont groupés Manual / Electric.
- **L'eau du robinet** ne propose plus Change à chaque café. Une eau en bouteille ou en recette, si.

## Existait déjà, mal montré

- **Narrate** était déjà le nom de la dictée. On l'a laissé, et on a rendu la transcription éditable pour que la reformulation ait une source que tu peux corriger.
- **Today's settings** était déjà le nom de l'écran des quantités. On l'a laissé : c'est le seul endroit où « aujourd'hui » veut dire la dose de cette tasse.
- **La provenance** (« From your timer », « From your timer · narration ») existait en petites capitales sous le bloc. Elle est reformulée et placée comme un tag, plus « Default sequence, not confirmed » quand tu n'as pas chronométré.
- **La comparaison de deux cafés** avait déjà deux couleurs. On a étendu la même paire aux autres graphiques à deux séries, et écrit la règle : pas de troisième couleur, pas de couleur sur une série seule.

## Maintenu, voilà pourquoi

- **« Vocal assistant » et « Calibrate ».** Narrate dit ce que tu fais (tu racontes le café). Calibrate promettrait une mesure que Kohi ne fait pas. Log your range dit que tu notes ta plage, pas que l'app l'a mesurée.
- **Le format n'est pas revenu sur l'écran du choix de recette.** Choisir la recette d'abord, les quantités ensuite, évite de figer une taille avant de savoir ce que tu brasses. Le format est sur Today's settings, et l'eau du jour met la recette à l'échelle sans la réécrire.
- **Les familles de l'écran A** (pour over, immersion, espresso) restent. « Filter » comme nom de méthode devenait le même mot que le papier : la méthode s'appelle maintenant Pour Over. Filter reste le papier.
- **K-Plus, K-Max, K-Pro sans plage publiée.** Le tableau 1Zpresso compte des points de 10 clics. Ces trois broyeurs ont 90 clics par tour. Appliquer le tableau tel quel donnerait une plage fausse. Trois broyeurs sans plage valent mieux.
- **Pas de détection visuelle.** Une odeur ou « quand la croûte casse » est un repère que tu lis, pas quelque chose que la caméra décide.

## Plus tard

Le LABO et un éventuel contournement du parcours ne sont pas dans ce build. La fiche 4:6 n'a pas été retravaillée.

## Ce qu'il me manque de ton côté

1. La version d'iOS sur laquelle tu as testé.
2. Le modèle de ton Option-O, et la plage que tu utilises vraiment.
3. Le détail que tu voulais sur la 4:6.
4. Les drippers que tu as, pour ne pas te faire parcourir un catalogue qui n'est pas le tien.
5. L'angle que tu retiens pour l'UFO.
