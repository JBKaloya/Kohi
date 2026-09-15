# Kohi — Dev brief #4 : corrections et simplification après le test 1

**Statut** : prompt pour Cursor, version 4.1 · **Date** : 15 septembre 2026 · **Owner** : JBK (jbk studio)
**Build testé** : 1.0 (3) du 14 septembre, iOS 18 minimum · **Testeur** : Timour, guide de test 9 parcours · **Sources** : retours Timour « Update 1 », commentaires JBK, capture du bug de sync.
**À lire avant** : `design-system.md`, `fonctionnalites.md`, `kohi-dev-brief-2.md` (2.1), `kohi-dev-brief-3.md` (3.1), manifeste.
**Fichiers livrés** : `grinders-seed.csv` (187 broyeurs), `drippers-seed.csv` (80 drippers avec famille et bypass), ce brief.
**Références UI (Mobbin, à consulter via le MCP Mobbin pour les specs exactes)** : stoic. — flux pas à pas ([https://mobbin.com/screens/031adb37-b0a4-4362-a7e6-10c535b883b8](https://mobbin.com/screens/031adb37-b0a4-4362-a7e6-10c535b883b8)) · Flighty — structure de texte et lignes de provenance ([https://mobbin.com/screens/eb6b86e6-d44e-476b-9b9d-846558f5114f](https://mobbin.com/screens/eb6b86e6-d44e-476b-9b9d-846558f5114f)) · Klarna — champs structurés ([https://mobbin.com/screens/01e73871-d148-43d6-9d03-23b22464b8b5](https://mobbin.com/screens/01e73871-d148-43d6-9d03-23b22464b8b5)). Détail en §9.

**4.1 — arbitrages JBK du 15 septembre** : le crash d'ajout de carte a été traité entre-temps (iOS 18) → on **vérifie** qu'il est réglé au lieu de le rouvrir ; ce qui dépend des éléments de Timour passe en **Plus tard** (§8) ; AKVO est un **système de filtration** (avec ses propres minéraux), pas un concentré → catégorie eau filtrée ; vocabulaire tranché : **For the pros**, **Suggested correction** ; le feedback IA devient une **échelle** avec un texte derrière, dicté ou tapé ; trois références UI (Mobbin) entrent dans le lot pour le flux de recette, l'onboarding, les blocs de texte et les champs (§9).

---



## 0. Cadre

Même ADN : **ne pas complexifier**. Ce lot est une phase de **structuration et de simplification** — on corrige ce qui casse, on clarifie ce qui se lit mal, on aplatit ce qui est empilé, et on rend l'intelligence native au lieu de la cacher derrière des interrupteurs. Chaque item est typé **Bug**, **Correction** ou **Amélioration**, et porte son origine (T = Timour, J = JBK).

Quatre principes pour ce lot, qui tranchent toutes les questions de détail :

1. **Un bloc d'information par étape.** Dans un parcours (recette → brew → minuteur → après), l'écran montre *ce qu'il faut faire maintenant*, en grand, et rien d'autre. Moins vertical, plus de focus, cibles tactiles ≥ 44 pt.
2. **Aplatir.** Chaque écran imbriqué en plus doit se justifier. Objectif : partir d'une recette et brasser en trois écrans, pas six.
3. **L'IA est native.** *Suggested correction*, comparaison, Ask : allumés par défaut, marqués `sparkles`, avec un fallback à règles. Et chaque sortie IA a un **bouton de feedback** — c'est ce qu'on veut apprendre.
4. **Dicter plutôt que taper**, partout où il y a du texte libre, y compris dans le feedback.

Ce que ce lot ne fait pas : le compositeur de recette à partir d'éléments (eau, dripper, torréfaction → recette IA — idée retenue, PRD plus tard), l'import depuis d'autres apps (toujours placeholder), la rosace du timer, le thème sombre, iPad.

---



## 1. P0 — Bloquants



### 1.1 Bug (T) — L'app plantait à chaque ajout de carte (parcours 2) — **à vérifier, corrigé entre-temps**

C'est le bug qui a invalidé la moitié du test : sans sauvegarde de carte, la feuille **Bring what you have** n'est jamais apparue (Timour a cru à un problème d'iOS), donc le parcours 3 s'est fait à la main depuis Profil, sans les trois questions. JBK l'a traité sur iOS 18 après le test ; ce lot **vérifie** au lieu de rouvrir.

- **Vérifier** : Demo → Use → New card → Save ; Photo → Use → Save ; vraie carte avec labels entre crochets sur une ligne (`[Process]Washed [Variety]Heirloom`) ; kit vide ; kit rempli. Sur iOS 18 *et* 26.
- **Blinder** : les suspects deviennent des tests de régression même si la cause est déjà connue — `SuggestedRecipe` avec kit vide, `RecipeScaling` avec `dose == nil`, `LabelValueParser` sur `[label]valeur` répétés, `FlavorMatcher` sur note vide, ingest sans `mask.png`. Aucun force unwrap dans `Card` → `SuggestedRecipe` → `RecipeScaling`.
- **Accepté quand** : 20 créations consécutives (Demo, Photo, carte réelle) sur iOS 18 et 26 sans crash ; puis **Bring what you have** apparaît 1,1 s après l'atterrissage, et les trois questions s'enchaînent.



### 1.2 Bug (T) — « Say it » plante

- **Suspects** : `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription` absents ou vides (crash immédiat à la demande d'autorisation) ; sur iOS 18, `SFSpeechRecognizer(locale:)` renvoie `nil` ou `supportsOnDeviceRecognition == false` et le code le déballe ; `AVAudioSession` sans catégorie `.record`.
- **Corriger** : chaîne d'autorisation explicite ; si la reconnaissance n'est pas disponible, le label devient « Dictation unavailable » en `inkMuted` et le clavier reste ; jamais de crash. Tester sur iOS 18 réel (pas seulement simulateur) et en langue FR et EN.
- **Accepté quand** : la phrase du guide (« 18 in, 250 of water, two forty-five, four stars ») remplit Dose, Water, Time, Rating sur iOS 18 et 26. La confirmation sur l'appareil de Timour attend sa version d'iOS (§8, *Plus tard*) ; les gardes se posent sans attendre.



### 1.3 Bug (T, capture) — Sync : `brews_recipe_id_fkey`

`insert or update on table "brews" violates foreign key constraint "brews_recipe_id_fkey"` — et « Pending 2 cards · 7 equipment · 1 water » reste bloqué derrière.

- **Cause** : un brew référence une **recette de référence embarquée** (bundle) qui n'existe pas dans la table `recipes` côté serveur ; et un échec sur un brew bloque tout le lot.
- **Corriger, modèle** : `brews.recipe_id` ne référence que les recettes de l'utilisateur (*Mine*), FK `ON DELETE SET NULL` ; nouvelle colonne `brews.recipe_ref text` pour une recette embarquée (`ref:hoffmann-v60-ultimate`) ; nouvelle colonne `brews.recipe_snapshot jsonb` (paramètres et étapes au moment du brew — durable même si la recette change). Migration SQL additive.
- **Corriger, outbox** : ordre de push par dépendance — équipement → eaux → torréfacteurs → cartes → recettes (*Mine*) → brews ; un échec est **par entité** (l'item reste dirty avec son message, les autres passent) ; retry avec backoff ; la ligne d'erreur de l'écran Compte nomme l'item.
- **Accepté quand** : l'appareil de Timour synchronise ; un brew sur recette de référence passe ; un brew invalide n'empêche pas les cartes de partir.



### 1.4 Bug (T) + Amélioration (J) — Ask ne répond à rien

Dans ce build la base de connaissances est vide, donc Ask dit « The base does not cover this one » — même aux quatre exemples proposés. JBK veut l'IA native : on corrige les deux.

- **Seed** : les 19 entrées de l'annexe F du PRD (citation, année, type, résumé d'une phrase, usage, URL) + les 16 recettes de référence + les règles G3/G4/G7 entrent dans `KnowledgeEntry`. C'est la base minimale ; elle grandit après.
- **Politique** : répondre depuis la base quand elle couvre, avec sources ; sinon répondre depuis la connaissance générale du café, réponse marquée `tag` « general » sans citation ; refuser seulement le hors-sujet. Ne jamais répondre « la base ne couvre pas » à une question de café.
- **Accepté quand** : les quatre exemples de l'écran Ask reçoivent une réponse utile (fixtures enregistrées, test), et « Why is my V60 sour? » cite une règle G7.



### 1.5 Bug (T) — *Suggested* est vide

- **Vérifier** l'éligibilité : cartes sans brew **ou** dont le dernier brew est ≤ 2/5 ; les six cartes d'exemple comptent si elles n'ont pas de brew ; la suggestion ne doit pas dépendre d'un broyeur déclaré (sans broyeur, la recette de référence est proposée telle quelle, sans « for your grinder »).
- **État vide** légitime : une phrase `Typography.body` `inkMuted` — « Every coffee has a brew. Scan a new one and it will show up here. » — jamais un écran blanc.



### 1.6 Correction (T) — Les équivalences de mouture sont introuvables

- Sur la fiche recette (Pros) et sur *Suggested recipe* de la carte : une rangée **For your grinder** (renommage de « In your terms », §2.3) : « ≈ 22 clicks · Comandante » si un broyeur est déclaré avec une plage pour cette méthode ; sinon « Add your grinder to see this in clicks » en `catalogueLabel`, tap → Profil › Your kit. La conversion utilise la plage déclarée (milieu pour *medium*, tiers pour *medium-fine*, etc.) — « ≈ » toujours.



### 1.7 Correction (T) — Pas de retour possible depuis une carte

Le glissement depuis le bord ne marche pas sur l'iPhone de Timour (transition zoom).

- Ajouter un retour explicite en haut à gauche de la fiche : `chevron.left` 10 pt + « COFFEES » en `catalogueLabel`, cible 44 pt. Garder le geste interactif de la transition zoom. Idem sur la fiche recette (« RECIPES ») et sur toute feuille poussée.

---



## 2. P1 — Corrections d'interface



### 2.1 Fiche carte (T)


| Constat                                                                                     | Correction                                                                                                                                                                                                                                     |
| ------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| La ligne « brewed » (date du café) n'aide pas à la lecture ; la date de torréfaction manque | La rangée **Roasted on** remplace « Date » dans la caption. La date d'ajout n'est plus affichée (elle trie la grille, c'est tout). « Date » reste en édition, sous *On the bag*, pour les cafés sans date de torréfaction                      |
| « Je ne vois pas le choix Place »                                                           | La rangée n'apparaît que si le lieu est rempli (voulu). En édition, **Bought at** sort du groupe replié et devient une section visible                                                                                                         |
| « Je ne trouve pas On the bag »                                                             | Plus de groupe replié dans *New card* / *Edit* : quatre sections toujours visibles avec un `catalogueLabel` — **CARD** · **ON THE BAG** · **BOUGHT AT** · **NOTE TO SELF**. Une feuille plus longue, mais qui se lit ; la dictée fait le reste |
| Brew row : « nom de la recette au lieu du broyeur et du TBT »                               | Rangée `BrewList` : ligne 1 = **nom de la recette** (ou méthode s'il n'y en a pas) + rating à droite ; ligne 2 = `dose · ratio · temp`. Ni broyeur ni temps total en rangée — ils sont dans la feuille                                         |




### 2.2 Feuille de brew (T, J)


| Constat                                            | Correction                                                                                                                                                                                                                             |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| « Dose » / « Out » ambigus pour le ratio           | Labels : **Coffee dose** (g) · **Water weight** (g) pour les méthodes filtre, **Beverage** (g) pour l'espresso ; le ratio se calcule sous les deux                                                                                     |
| « selected » trop discret                          | `checkmark` 10 pt `ink` sur toute rangée sélectionnée (recette, brew de comparaison, café, broyeur) ; le mot disparaît                                                                                                                 |
| Cibles trop petites                                | Audit : chips, dots, rails, rangées d'actions → zone tactile ≥ 44 pt (padding invisible), sans changer le rendu                                                                                                                        |
| Compare et Brew again cachés derrière l'appui long | Ouvrir un brew montre deux actions en tête de feuille, `catalogueLabel` : **Brew again** · **Compare**. L'appui long reste un raccourci. Compare propose **tous** les brews comparables (chip « Any coffee »), le même café par défaut |




### 2.3 Vocabulaire (T, J) — termes à revoir


| Aujourd'hui                                  | Proposition                                                                             | Pourquoi                                                                                                             |
| -------------------------------------------- | --------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Washed (bouton de scan)                      | **Whiten** + une ligne sous le bouton la première fois : « Whiter paper, sharper text » | « Washed » est un process de café, ici ça parle du scan                                                              |
| Next time                                    | **Suggested correction** (arbitré)                                                      | Nomme ce que c'est (Timour) ; devient un bloc avec trois mouvements (§4.1)                                           |
| In your terms                                | **For your grinder**                                                                    | Dit où on convertit                                                                                                  |
| Say it                                       | **Dictate** + `mic`                                                                     | Le mot standard ; « Say it » se lisait comme un slogan                                                               |
| Reference (onglet)                           | **For the pros** — en `catalogueLabel` : MINE · SUGGESTED · FOR THE PROS (arbitré)      | Dit qu'on accède aux recettes de pros ; l'attribution fait le reste                                                  |
| Surfaces (Profil)                            | **Features**                                                                            | Les interrupteurs de ce lot passent *on* par défaut ; la section reste pour le debug                                 |
| verified / partly verified / common practice | **supprimés de l'UI**                                                                   | Timour : le nom du créateur inspire la confiance, pas le niveau de preuve. On garde la donnée, on retire l'affichage |




### 2.4 Recettes — lisibilité (T, J)

- **Filtres par section, à la verticale** : une feuille *Filters* (depuis un `catalogueLabel` « Filters » en tête de *Pros*) avec un bloc par critère, chips à l'intérieur : **Dripper** (V60, flat, Chemex, AeroPress, immersion…), **Cup** (1 cup · 2 cups · batch), **Roast** (light · medium · dark), **Grinder** (les broyeurs cités par la recette de l'auteur, quand ils le sont), **Profile** (fruity · floral · sweet · bright · clean · body). Sous l'onglet, une ligne `tag` résume les filtres actifs. La rangée horizontale de chips disparaît.
- `Recipe.profileTags` et `Recipe.authorGrinder` s'ajoutent au modèle et aux 16 recettes (annexe A à compléter, *à vérifier*).
- **Mine** : « New recipe » en `catalogueLabel` (nom, méthode, paramètres, étapes) — le but est de **partir d'une recette**, pas seulement de sauver un brew. « Save as recipe » reste.
- Rangée de recette : nom · auteur ; sous-titre `method · dose · ratio · temp` ; rien d'autre.



### 2.5 Pours (T)

- Entre deux versements, le **temps de drainage compte** : les recettes de référence gagnent des étapes `drawdown` / `wait` explicites ; le minuteur les affiche comme des étapes (« Wait · drawdown to 1:45 »).
- Ligne finale **Total brew time** (« TBT ») sous les étapes, cible et réel.
- Base de comparaison : Filtru, pour la gestion des étapes et de la cible d'eau en temps réel (§3.2). On reprend le principe, pas l'écran.

---



## 3. P2 — Simplifier les parcours : un bloc par étape (J)



### 3.1 Inventaire des empilements


| Parcours aujourd'hui                                                                                                                | Écrans | Après                                             |
| ----------------------------------------------------------------------------------------------------------------------------------- | ------ | ------------------------------------------------- |
| Partir d'une recette : Recipes → bouton tasse → Which coffee (1/2) → Which recipe (2/2) → fiche café → feuille brew → Pours → Start | 6–7    | **Recette → Brew guidé → Après** : 3              |
| Brew again : fiche → appui long → menu → feuille brew → Pours                                                                       | 4      | fiche → **Brew again** (visible) → brew guidé : 2 |
| Kit : Profil → Your kit → Add → Edit                                                                                                | 4      | Profil → Add (la recherche *est* l'édition) : 2   |




### 3.2 Les trois écrans du parcours recette

**Écran 1 — Recette.** Une page, un bloc par section, dans l'ordre : **Parameters** (dose · water · ratio · temp · grind « for your grinder ») · **Steps** (rangées `t · action · mass`, drainage compris, TBT en pied) · **Brew this** : chips des cafés récents (les 5 derniers, `checkmark` sur le choisi) + un `catalogueLabel` « Another coffee… » → picker ; le bouton **Brew** (grand, `catalogueLabel` 15 pt, pleine largeur, 52 pt de haut) lance l'écran 2. Le sélecteur « Which coffee ? / Which recipe ? » en deux temps disparaît.

**Écran 2 — Brew guidé.** Plein écran papier, *un seul bloc visible* :

```
2 / 5                                       1:12
POUR                                        ← catalogueLabel
to 300 g                                     ← Typography.number, grand
now 168 g                                    ← cible instantanée, interpolée dans l'étape
────────────────── progression hairline ──────────────────
                                            next: wait · drawdown to 1:45
```

- Le bloc entier est la cible tactile : **tap = Next** (haptic `stepAdvance`) ; « Stop » en `catalogueLabel` en bas. Le bloc suivant dépasse en `inkMuted` sous le bloc courant — c'est tout ce qu'on voit.
- **Cible instantanée** : dans une étape de versement, `now = mass_start + (mass_target − mass_start) × (t − t_start) / (t_target − t_start)` ; c'est la lecture Filtru « où devrais-je en être », sans balance.
- **Avance automatique** : quand le temps théorique de l'étape est atteint, l'étape passe seule après 3 s (haptic `tick` doublé) ; un tap avant enregistre le réel. Réglage par recette (`autoAdvance`, on pour les recettes Pros), coupable dans le bloc (« manual »).
- Étapes d'attente : même bloc, « WAIT » + décompte.
- Fin : TBT réel vs cible, puis l'écran 3.

**Écran 3 — Après.** Une feuille, blocs : **Rating** · **Taste** (7 rails) · **Correction** (− · +) · **Comment** (dictée) · **Suggested correction** (§4.1) · **Save**. Rien d'autre ; les paramètres sont repliés sous un `catalogueLabel` « Parameters » pour correction.

### 3.3 Règles de mise en page des blocs

- Un bloc = `catalogueLabel` + contenu + 28 pt d'air. Pas de conteneur, pas de fond : le papier et l'espacement font le bloc.
- Ce qu'il faut faire maintenant en **grand** (style numérique du timer existant, 34 pt) ; le reste en `tag` `inkMuted`.
- Une action principale par écran, pleine largeur, 52 pt, texte en `catalogueLabel` 15 pt. Les actions secondaires restent des `catalogueLabel` 11 pt.
- Les feuilles imbriquées se remplacent par des chips inline quand le choix tient en ≤ 6 options (cafés récents, broyeurs, eaux).

---



## 4. P2 — L'IA native, et une boucle de feedback (J, T)



### 4.1 Suggested correction — trois mouvements, du plus doux au plus fort

Timour a raison sur le fond : « thin, but the extraction reads fine — more strength, same extraction » est une **lecture**, pas une correction. On garde la lecture (une ligne) et on ajoute **trois mouvements classés**, chacun **une seule variable**, du moins au plus drastique — l'utilisateur en choisit un, « une variable à la fois » tient.

**Entrées** : les 7 axes, la ligne Correction (− · +), le rating, tous les paramètres et étapes du brew, le kit et l'eau, la carte (roast level, process, notes déclarées), les brews précédents de ce café, et le **Comment** dicté (nouveau champ libre : ce que l'utilisateur a senti, en ses mots).

**Sortie** (JSON validé avant affichage) :

```json
{ "reading": "Thin body, extraction reads fine.",
  "target": "more body",
  "moves": [
    { "rank": 1, "variable": "grind", "change": "-2 clicks", "why": "Finer grind, more contact", "effect": { "body": "+", "clarity": "-" } },
    { "rank": 2, "variable": "steps", "change": "Add a 4th pour (split the last 100 g)", "why": "More agitation, longer contact", "effect": { "body": "+" } },
    { "rank": 3, "variable": "agitation", "change": "Stir after pour 2", "why": "Most drastic: changes the bed", "effect": { "body": "+", "bitterness": "+" } } ] }
```

**Mécanique** : les règles (G7 du PRD, plus les mouvements d'étapes — ajouter un versement, allonger le bloom, agiter au versement N — plus le mouvement **dripper** si l'utilisateur possède ≥ 2 drippers : *plus de clarté → bypass plus élevé ; plus de corps ou de sucrosité → bypass faible ou nul*, d'après `drippers-seed.csv`) produisent l'ensemble des mouvements **admissibles** ; le modèle choisit trois, les classe, les explique et les relie au Comment. Il ne peut pas inventer un mouvement hors ensemble. Sans IA (hors ligne, flag off) : la règle seule, un mouvement, comme aujourd'hui.

**Affichage** : bloc **Suggested correction** avec `sparkles` ; la lecture en `Typography.body` ; trois rangées `1 · Grind finer (−2 clicks)` avec `why` en `tag` ; tap → `checkmark` + « Use next time » pose ce seul changement sur le prochain *Brew again*. **Allumé par défaut.**

### 4.2 Le module de feedback

Sous **chaque** sortie IA (Suggested correction, réponse Ask, recette adaptée, résultat de dictée quand il a été corrigé) — une **échelle**, puis un texte (arbitré) :

```
HOW USEFUL WAS THIS?                                  ← catalogueLabel
NOT AT ALL   ·   A LITTLE   ·   USEFUL   ·   A LOT     ← quatre catalogueLabel, 44 pt de haut, checkmark sur le choisi
What would have helped? ______________________  DICTATE ← apparaît après un choix, DictationField, facultatif
```

- Quatre niveaux, pas cinq : pas de milieu où se réfugier. Le texte est ouvert quel que soit le niveau (un « A lot » commenté vaut autant qu'un « Not at all »).
- Écriture : `AIFeedback { id, aiEventId, feature, score: 1…4, comment?, createdAt }` — local, et poussé vers la table serveur `ai_feedback` (RLS, lecture par le propriétaire et par les comptes internes).
- Visibilité : flag `aiFeedback`, **on** pour les builds internes (JBK, Timour), on pour la bêta. Une rangée Compte › **Export AI feedback** (CSV) suffit pour les boucles d'évaluation ; le tableau de bord attendra.
- Le « Useful / Not useful » actuel d'Ask fusionne dans ce composant.



### 4.3 Dicter partout

Un seul composant `DictationField` (label `Dictate` + `mic` 10 pt, transcription on-device, repli clavier) enveloppe **tout** texte libre : Notes, Comment, Note to self, question Ask, feedback, nom de recette, ajout de torréfacteur, saveur custom, notes de mouture. Le surlignage 1,1 s et l'annulation par tap sont les mêmes que pour la dictée de brew.

### 4.4 Eau — mode Recipe (T)

- Quand *Source = Recipe*, la feuille se **réorganise** : **Base** (chips : *Distilled · RO · Tap · Filtered* — par défaut Distilled, minéraux à 0) → **Minerals** : recherche dans `MineralProduct` (Third Wave Water Classic / Medium / Dark / Espresso, Lotus, Apax Lab Tonik / Jamm / Lylac / Tanat, Aquacode, Perfect Coffee Water, AKVO Minerals) + dose (« 1 sachet / 1 L », « 2 ml / L ») → **What's in it** se remplit seul depuis la base (Ca · Mg · Na · HCO₃), l'utilisateur peut corriger.
- **AKVO** (akvowatersystems.com) est d'abord un **système de filtration** né dans un café polonais, qui promet une dureté et une minéralisation adaptées au café, et vend ses propres minéraux. Il entre donc à deux endroits : `FiltrationSystem` (nouvelle petite table : AKVO, Peak Water, BWT Bestmax / Besttaste, Brita…) comme attribut d'un profil *Filtered* (« Filtered with AKVO »), et `MineralProduct` pour *AKVO Minerals*. Compositions *à vérifier* ; un profil *Filtered* sans analyse ne remplit rien et le dit.
- Le label **ppm** remplace « TDS » sous *What's in it* (même unité ; Timour lit « ppm »).
- Les compositions par dose des produits sont **à vérifier** (annexe C3 : TWW connu, les autres partiels) ; un produit sans composition vérifiée ne remplit rien et le dit (« composition not on file yet »).



### 4.5 Recettes : 4:6 (T) — **Plus tard**

Timour conteste la recette 4:6 sans dire quoi. Identifié, pas traité dans ce lot (§8) : quand on saura ce qui paraît faux, re-vérification **à la source** (Tetsu Kasuya), puis une seule recette avec deux sélecteurs en chips — **Taste** : *standard* (60 / 60) · *sweeter* (moins d'eau au premier versement) · *brighter* (plus d'eau au premier versement) ; **Strength** : *balanced* (3 versements) · *stronger* (2) · *lighter* (1) — qui génèrent les étapes. Une recette, six variantes, plutôt que trois recettes.

---



## 5. Données — seeds livrés


| Fichier             | Contenu                                                                                                                                                            | Usage                                                                                                                                                | Statut                                                                                          |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `grinders-seed.csv` | 187 broyeurs (68 manuels, 119 électriques) de la liste de Timour, dédoublonnés, marques normalisées ; 7 lignes enrichies depuis l'annexe B (pas fabricant, meules) | `GrinderModel` pour la recherche dans l'onboarding et *Your kit* (Timour : « une base des broyeurs les plus connus pour ne pas faire ça à la main ») | noms *à vérifier*, plages vides tant que non vérifiées — rien ne s'affiche en « ≈ » sans donnée |
| `drippers-seed.csv` | 80 drippers avec **famille** (cone · flat · hybrid · no-bypass · immersion · cloth…) et **bypass** (high → very-low, variable, controlled), filtre, note           | `BrewerModel` : recherche dans *Your kit*, glyphe par famille, filtre *Dripper* des recettes, mouvement « change dripper » de §4.1                   | *à vérifier* ligne par ligne (quelques entrées douteuses : Osmotic Flow, Luca, UFO 2.0, Beasty) |


Règle inchangée : une ligne *à vérifier* ne pilote aucune suggestion chiffrée ; elle sert à nommer, chercher et classer.

---



## 6. Tests et critères d'acceptation

- P0 : les cinq acceptations de §1 (création ×20 sans crash, dictée iOS 18/26, sync Timour, Ask sur les quatre exemples, *Suggested* non vide ou état vide légitime).
- `RecipeDetailView` → `GuidedBrewView` → `AfterBrewSheet` : trois écrans, testés en UI test ; le sélecteur en deux temps n'existe plus.
- `GuidedBrewView` : cible instantanée correcte (test unitaire de l'interpolation), avance automatique après 3 s, tap avant enregistre le réel, TBT réel ≠ cible affiché.
- `SuggestedCorrection` : sortie JSON validée ; trois mouvements distincts, une variable chacun, ordonnés ; mouvement *dripper* seulement avec ≥ 2 drippers ; fallback règle sans réseau.
- `AIFeedback` : score 1…4 obligatoire, commentaire facultatif ; écrit localement et poussé ; export CSV non vide après un feedback.
- `DictationField` présent sur tous les champs listés en §4.3 (test d'inventaire).
- Vocabulaire : aucune occurrence de « Washed » (scan), « Next time », « In your terms », « Say it », « Reference », « Pros » seul, « verified » dans les vues (test grep sur `Localizable`) ; l'onglet dit « For the pros ».
- Snapshots light only : fiche carte (sections visibles), feuille brew (labels), filtres, bloc de brew guidé, Suggested correction, feedback.

---



## 7. Ordre d'exécution

1. **P0** dans l'ordre 1.1 → 1.3 → 1.2 → 1.4 → 1.5 → 1.6 → 1.7 (la crash carte débloque le test complet ; la sync débloque Timour).
2. **Seeds** (§5) : `GrinderModel`, `BrewerModel` + recherche.
3. **P1** (§2) : vocabulaire et fiche carte d'abord (petits, visibles), puis brew sheet, puis recettes, puis Pours.
4. **P2 parcours** (§3) : recette → brew guidé → après.
5. **IA native + feedback** (§4) : correction à trois mouvements, `AIFeedback` (échelle + texte), `DictationField`, eau Recipe et filtration.

5 bis. **Références UI** (§9) : `StepFlow`, `InsightBlock`, `FieldGroup` — d'abord sur l'onboarding et le parcours recette, puis sur le reste.
6. Mise à jour de `fonctionnalites.md`, `design-system.md` (§11 copy, §8 ordre de lecture, blocs) et du guide de test (parcours 4, 5, 7 réécrits ; préréglage *Surfaces* supprimé).

Puis un build 1.0 (4) pour Timour, avec le même guide.

---



## 8. Plus tard — identifié, en attente des éléments de Timour

Ces points restent dans le plan, marqués `TODO(timour)` dans le code, et ne bloquent pas le build 1.0 (4) :


| Point                                           | Ce qu'on attend                                                    | Ce qu'on fera                                                                                 |
| ----------------------------------------------- | ------------------------------------------------------------------ | --------------------------------------------------------------------------------------------- |
| Confirmation du fix « Say it » sur son appareil | modèle d'iPhone, version d'iOS                                     | test sur la même version ; si iOS 18, vérifier le chemin `SFSpeechRecognizer` on-device en FR |
| Recette 4:6                                     | ce qui lui paraissait faux (masses, temps, température, découpage) | §4.5                                                                                          |
| Mouvement *dripper* (§4.1)                      | ses drippers et son broyeur                                        | jeu de test réel pour la règle bypass                                                         |
| Broyeurs à ajouter                              | ceux qu'il a saisis en *Custom*                                    | compléter `grinders-seed.csv`                                                                 |




## 9. Références UI (Mobbin) — ce qu'on prend, et comment ça entre dans la grammaire

Trois écrans, choisis par JBK. Cursor utilise le **MCP Mobbin** sur les trois URLs de l'en-tête pour lire les specs exactes (espacements, corps, rythme) ; ce qui suit dit **ce qu'on retient** et **comment ça se traduit** en papier et encre. On s'inspire de la structure, jamais des couleurs, des icônes ou des conteneurs sombres.

### 9.1 stoic. — un flux pas à pas, une chose par écran → `StepFlow`

Ce qu'il fait bien : une **progression en segments fins** en haut, `‹` à gauche et `×` à droite, **une question en grand**, le contenu en dessous, et deux paires de boutons ronds en bas — actions secondaires à gauche (`+`, `Aa`), IA et **suivant** à droite. L'écran ne demande qu'une chose.

Traduction Kohi — `StepFlow`, le chrome commun de l'onboarding (*Bring what you have* → 1 / 3 → 3 / 3) et du parcours recette (§3.2) :


| Élément stoic.          | Kohi                                                                                                                                                                                                                                                                                                                                      |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Segments de progression | 3–5 filets hairline de 24 × 1 pt, espacés de 6 pt, centrés en haut ; le courant en `ink`, les autres `hairline`. Remplace « 1 / 3 »                                                                                                                                                                                                       |
| `‹` / `×`               | `chevron.left` 10 pt et `xmark` 10 pt, cibles 44 pt, `inkMuted`                                                                                                                                                                                                                                                                           |
| Question                | `Typography.value` 22 pt, `ink`, deux lignes max, alignée à gauche, 26 pt de marge                                                                                                                                                                                                                                                        |
| Boutons ronds en bas    | **à gauche** : `mic` (dictée) et, selon l'écran, `plus` — cercles 52 pt, filet hairline, glyphe `ink` ; **à droite** : `sparkles` (Ask, contextuel à l'écran) en cercle hairline, puis **Next** — cercle 52 pt **plein** `ink`, `chevron.right` `paper`. C'est le même vocabulaire que le bouton de scan : un seul bouton plein par écran |
| Skip                    | `catalogueLabel` « SKIP » sous les cercles, centré ; jamais un bouton                                                                                                                                                                                                                                                                     |


Pas de fond gris, pas d'ombre sous les cercles. Sur le brew guidé (§3.2), le bloc reste la cible tactile ; les cercles ne s'affichent que sur les écrans de saisie.

### 9.2 Flighty — un texte qui se lit en trois niveaux → `InsightBlock`

Ce qu'il fait bien : des **séparateurs de section** en pointillé avec un pictogramme et un label capitale ; puis, pour chaque item, un **titre** en gras, une **phrase** en gris, et une **ligne de provenance** en monospace capitale (« DERIVED FROM LIVE FLIGHTY DATA », « SOURCE: METAR • REPORTED 21M AGO ▾ »). On sait toujours d'où vient une affirmation.

Traduction Kohi — `InsightBlock`, le gabarit de **toute sortie IA ou déduite** (Suggested correction, réponses Ask, Insights, Compare) :

```
SUGGESTED CORRECTION ✦ ──────────────────────────────   ← catalogueLabel + sparkles + filet hairline (pas de pointillé)
Thin body, extraction reads fine.                        ← titre : Typography.value, ink
1 · Grind finer (−2 clicks) — more contact, more body.    ← corps : Typography.body, inkMuted
DERIVED FROM YOUR LAST 3 BREWS · RULE G7                 ← provenance : Typography.tag, capitales, inkMuted
```

- La ligne de provenance est **obligatoire** : `DERIVED FROM …` (déduit de tes données), `SOURCE: HOFFMANN 2019` (recette), `SOURCE: SCA WATER STANDARD` (Ask avec base), `GENERAL COFFEE KNOWLEDGE` (Ask hors base). C'est elle qui remplace les niveaux de preuve supprimés en §2.3 : on ne note plus la confiance, on nomme la source.
- Le chevron `▾` de Flighty devient un tap sur la ligne de provenance → détail (règle, brews utilisés, entrée de la base).
- Filet hairline plein, pas de pointillé ; pas de pictogramme : le `catalogueLabel` suffit.



### 9.3 Klarna — des champs structurés → `FieldGroup`

Ce qu'il fait bien : un **seul cadre** fin, des **cellules** séparées par des filets, **label au-dessus de la valeur**, et une **première rangée en deux colonnes** pour les paires courtes. Le formulaire se lit comme une fiche, pas comme une liste de lignes.

Traduction Kohi — `FieldGroup`, pour *New card* / *Edit* (sections CARD · ON THE BAG · BOUGHT AT), la feuille de brew (Parameters) et le kit :


| Élément Klarna                   | Kohi                                                                                                                                                                                      |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cadre                            | filet `hairline` 1 pt, rayon 8 pt, fond `paper` — c'est le premier conteneur de la grammaire ; il n'entre qu'en **édition**, jamais en lecture (la caption de la carte garde ses rangées) |
| Cellule                          | label `catalogueLabel` au-dessus, valeur `Typography.value` `ink`, placeholder `inkMuted` ; padding 14 / 12 ; filet hairline entre cellules                                               |
| Paires en deux colonnes          | **Coffee dose · Water weight**, **Temperature · Time**, **Roasted on · Roast level**, **Price · Bag** — deux cellules côte à côte séparées par un filet vertical                          |
| Titre + sous-titre de la feuille | titre `Typography.value` 22 pt, une ligne `body` `inkMuted` sous le titre (« Fill what the card doesn't say. »)                                                                           |
| Bouton plein bas de page         | on ne le reprend pas : **Save** reste un `catalogueLabel` en tête de feuille, comme partout dans Kohi ; le cercle plein est réservé aux flux `StepFlow`                                   |


Règle d'usage : un `FieldGroup` par section, jamais imbriqué, jamais plus de six cellules ; au-delà, on coupe en deux groupes. Dictée disponible sur la première cellule texte de chaque groupe (le micro de `StepFlow` ou `DictationField`).

### 9.4 Ordre d'application

1. `StepFlow` sur l'onboarding (3 questions) — petit, visible, mesure l'effet.
2. `StepFlow` sur le parcours recette (§3.2, écrans 1 et 3).
3. `InsightBlock` sur Suggested correction, puis Ask, Insights, Compare.
4. `FieldGroup` sur *New card* / *Edit*, puis la feuille de brew, puis le kit.

Mise à jour de `design-system.md` : §7 (nouveaux composants), §10 (cercle plein = action principale d'un flux), §11 (copy).

## 10. Annexes et reponses au questions

1. **For the pros** dit *pour qui* ; **From the pros** dirait *d'où ça vient*. Tu as tranché *From the pros* — on le garde tel quel, sauf si la nuance te fait changer d'avis.
2. **Échelle de feedback** : quatre niveaux sans milieu (« Not at all · A little · Useful · A lot »)
3. `FieldGroup` introduit un cadre en édition, premier conteneur de la grammaire-> le limiter à l'édition et ne jamais l'utiliser en lecture 

