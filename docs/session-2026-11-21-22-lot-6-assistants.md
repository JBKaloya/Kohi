# Session des 21 et 22 nov. 2026 : lot 6, sécurité IA, assistants sur OpenAI

Ce document sert à la fois de compte rendu et de gabarit pour Cursor. Il dit ce qui a changé, pourquoi, ce qui a été mesuré et déployé, ce qui reste fragile et comment reprendre.

Il complète deux documents :
- **`docs/assistants-gemini-vs-openai.md`** : le plan multi-modèle, avec les résultats chiffrés et les décisions.
- **`/Users/jbkaloya/.claude/plans/ok-donc-l-j-ai-jazzy-pillow.md`** : le plan approuvé du lot 6, hors dépôt.

---

## 1. En une page

**Point de départ.** Les retours de Timour du 21 novembre ont donné 5 lots, faits dans Cursor et fusionnés sur `main`. L'audit de ces lots dans Claude Code a relevé :
- un résumé IA à environ 25 s ;
- pas d'échelle d'utilité sous le résumé ;
- des textes écrits en dur hors de `Copy` ;
- le blueprint pas à jour ;
- le pré-filtre « méthode du kit » perdu dans Brews ;
- un historique des migrations Supabase désynchronisé.

**Ce qui a été fait :**
- **Lot 6 côté app** (non commité) : délai de 12 s sur le résumé de comparaison, échelle d'utilité sous le résumé, textes des filtres déplacés dans `Copy`.
- **Historique des migrations réparé** : 0001 à 0038, sans trou ni ligne en trop. JB a lancé le SQL.
- **Garde d'authentification** sur les 8 fonctions IA (commit `c717f26`, venu de la branche d'une autre session). Les 8 fonctions sont déployées.
- **`compare-summary` réécrit** :
  - le serveur calcule les écarts notables et leur sens, et le modèle ne fait que les mettre en mots ;
  - plus de chiffres dans le texte, des trios plus courts ;
  - OpenAI d'abord, Gemini flash-lite en secours.
- **`ask` (Coffee Intelligence)** : OpenAI d'abord, Gemini flash-lite en secours. Le prompt est corrigé (les process comptent comme du café, pas d'id de source dans le texte) et les citations sont vérifiées par le serveur.
- **Évaluation sur données réelles** : les 19 dégustations de Timour, exportées en lecture seule dans `.private/`, et deux scripts de comparaison des modèles (`scripts/compare-real.ts`, `scripts/ask-duel.ts`).
- **Build TestFlight passé de 17 à 18** (non commité, non archivé).

**Mesures sur données réelles :**

| | Avant (Gemini, prompt d'origine) | Après (OpenAI d'abord) |
|---|---|---|
| Résumé : réponses | 14 / 15 | 15 / 15 |
| Résumé : latence médiane | 5,2 s | 1,1 s |
| Résumé : erreurs | 1 faux, 5 approximatifs | 0 faux, 1 égalité lue comme une tête |
| `ask` : réponses | 10 / 12 et 7 / 12 (503) | 12 / 12 |
| `ask` : réponses utiles | 5 / 12 (« the provided sources do not… ») | 12 / 12, 1 imprécision |

**Commité le 22 nov.** sur `lot-6-followups`, en 6 commits (`29f6cea` → `7d37b35`), mais **pas fusionné dans `main` ni poussé**. `main` local a 6 commits d'avance sur `origin/main`.

---

## 2. Branches et état git

### 2.1 Où est quoi (22 nov., fin de session)

| Branche | Tête | Contenu | Poussée ? |
|---|---|---|---|
| `origin/main` | `5c7fb67` (build 17) | Dernier état poussé | — |
| `main` (local) | `b044f00` | `origin/main` + les 5 lots Cursor + un correctif de filtres (6 commits) | **Non** |
| `lot-1-compare-three` … `lot-5-compare-summary` | — | Les 5 lots, déjà fusionnés dans `main` | Non, à supprimer après le push |
| `claude/vigilant-mendeleev-474b7a` | `c717f26` | Garde d'authentification des fonctions IA (autre session Claude) | Non |
| **`lot-6-followups`** (branche de travail) | `c717f26` | `main` + `c717f26` en avance rapide, **plus tout le travail de cette session, non commité** | Non |
| `origin/cursor/setup-supabase-env-5ab2` | `644108b` | Environnement Cloud Agent de Cursor (fuse-overlayfs, env Supabase) | Distante seulement |

Les 6 commits de `main` en avance sur `origin/main` :

```
b044f00 Filter lists hang under their pill …            (correctif de filtres, Cursor)
100e5b8 Testers can read a short AI summary …           (lot 5)
fa150bb One filter component for Tastings and Brews …   (lot 4)
2853581 The flavour wheel opens flat …                  (lot 3)
e8dd14e On the pack shows every note …                  (lot 2)
7e9eec1 Picking stops at three …                        (lot 1)
```

### 2.2 Fichiers non commités sur `lot-6-followups`

**Modifiés :**
```
.gitignore                                   + .private/
Kohi.xcodeproj/project.pbxproj               build 17 → 18
Kohi/AI/CompareSummary.swift                 délai de 12 s (withDeadline, DeadlineGate)
Kohi/App/Strings.swift                       textes des filtres dans Copy
Kohi/Compare/CompareView.swift               AIFeedbackScale sous le résumé
Kohi/Design/FilterPicker.swift               Copy.removeFilter
Kohi/Process/RecipeFilters.swift             Copy (facettes)
Kohi/Process/TastingFilters.swift            Copy (facettes, périodes, notes)
Kohi/Recipes/RecipesScreen.swift             Copy.noRecipeMatches
Kohi/Tastings/TastingsScreen.swift           Copy.noTastingMatches
KohiTests/CompareSummaryTests.swift          tests du délai
docs/blueprint/CHANGELOG.md                  échelle d'utilité, inventaire à synchroniser
supabase/functions/_shared/gemini.ts         generate(…, { attemptMs, models })
supabase/functions/_shared/openai.ts         generateJSON(…, { timeoutMs })
supabase/functions/ask/index.ts              OpenAI d'abord, citations vérifiées
supabase/functions/compare-summary/index.ts  faits calculés, OpenAI d'abord
```

**Nouveaux :**
```
docs/assistants-gemini-vs-openai.md
docs/session-2026-11-21-22-lot-6-assistants.md   (ce document)
scripts/compare-real.ts, scripts/compare-real_test.ts
scripts/ask-duel.ts, scripts/ask-duel_test.ts
supabase/checks/2026-11-21-{state,events,extras,repair,providers,testers,export-tastings}.sql
supabase/functions/_shared/provider.ts
supabase/functions/_shared/ask.ts, ask_test.ts
supabase/functions/_shared/compare-summary.ts, compare-summary_test.ts
```

**Jamais à commiter :**
- **`.private/`** (git-ignoré) : données de Timour et rapports.
- **`.env`** (git-ignoré, mode 600) : compte de test des scripts.
- **`Kohi/Resources/Supabase.plist`** (git-ignoré).

### 2.3 Écart prod ↔ dépôt

**Plus récent en prod que dans git :**
- `compare-summary` et `ask` tournent avec du code qui n'existe que dans l'arbre de travail.
- Les 8 fonctions déployées avec la garde d'auth correspondent à `c717f26`, qui n'est que dans des branches locales.

Le code déployé est commité sur `lot-6-followups` depuis le 22 nov., mais tant qu'il n'est ni fusionné dans `main` ni poussé, un redéploiement depuis `main`, un autre poste ou Cursor **écraserait la prod avec une version plus ancienne**. C'est la première chose à régler (voir §10).

---

## 3. Chronologie

**21 nov. :**
1. Analyse des retours du 21 novembre, puis plan.
2. Audit des 5 lots Cursor.
3. Plan du lot 6 approuvé. Choix de JB :
   - « You run the SQL » : je l'écris, JB le lance dans le dashboard ;
   - méthode du kit en chip visible.
4. Branche `lot-6-followups`.
5. **Phase 1, côté app** :
   - délai de 12 s ;
   - échelle d'utilité ;
   - `Copy` ;
   - chip de la méthode du kit, **implémenté puis retiré** : il cassait l'onglet Mine. La décision revient à JB.
6. **Phase 2, côté Supabase** :
   - `state.sql`, puis `extras.sql` : 0019 à 0038 absentes de l'historique, 14 versions datées en trop ;
   - `repair.sql` (lancé par JB), puis `state.sql` à nouveau : 0001 à 0038 « ok ».
7. **Déploiement de `compare-summary`**, après extraction de `_shared/compare-summary.ts` et un primaire limité à 6 s.
8. **Lecture des logs.** gemini-3.8-flash a échoué sur les 8 appels observés : 3 × 503 « high demand » et 5 timeouts.

**22 nov. :**

9. **Question de JB : comparer plusieurs modèles**, Gemini contre OpenAI seulement (« pas de Claude pour l'instant »). Plan dans `docs/assistants-gemini-vs-openai.md`.
10. **Étape 0** :
    - fusion de la branche sécurité (`c717f26`) en avance rapide ;
    - délais courts pour `ask` ;
    - requête `providers.sql` ;
    - **déploiement des 8 fonctions.**
11. **Test dans l'app par JB.** Compare est vide, ce qui est attendu : les cafés n'ont ni brew ni goût.
12. **Données réelles.** Je refuse de me connecter avec le compte de Timour. On passe par un export en lecture seule (`testers.sql`, `export-tastings.sql`) vers `.private/tastings.json`, et par un compte de test pour les scripts.
13. **`compare-real.ts`, 1ʳᵉ passe (Gemini, prompt d'origine)** :
    - 8 satisfaisants, 5 approximatifs, 1 faux, 1 sans résumé ;
    - captures rendues avec les vrais composants de l'app dans `.private/compare-screens/`.
14. **Écarts calculés côté serveur** (`differences()`, `describe()`), puis déploiement : 15/15 justes, mais des chiffres recopiés dans le texte.
15. **Style** : faits sans chiffres, 3 axes au plus, 2 saveurs au plus, puis déploiement. Trios encore longs.
16. **Duel Gemini contre OpenAI sur le résumé**, puis déploiement de l'option `provider`. Résultat : OpenAI 15/15 à 1,6 s, Gemini 14/15 à 6,6 s.
17. **Décision de JB : OpenAI d'abord.**
    - Changements : `provider.ts`, 2 axes par trio, pas de nom de café, saveurs en minuscules.
    - Déploiement, puis vérification : 15/15 à 1,1 s.
18. **`ask` passe à OpenAI d'abord**, avec `scripts/ask-duel.ts`, puis déploiement. Duel :
    - OpenAI 12/12 avec 2 défauts : thermal shock refusé, citation inventée ;
    - Gemini 10/12, et 5 non-réponses.
19. **Corrections du prompt et `cited()`**, puis déploiement. Duel : OpenAI 12/12 sans signalement, Gemini 7/12.
20. **Vérification dans le simulateur : impossible.** L'app n'est pas connectée (401 sur toutes les fonctions IA), et il n'y a aucune dégustation.
21. **Build 17 → 18**, puis ce document.

---

## 4. Changements, par zone

### 4.1 App iOS (non commité)

| Fichier | Changement | Pourquoi |
|---|---|---|
| `Kohi/AI/CompareSummary.swift` | `withDeadline(_:_:)` et `DeadlineGate`. `summary(of:)` abandonne après `deadline = 12` s, enregistre un `AIEvent` avec `failure: "timeout"` et masque le bloc. | Un shimmer qui reste dit plus sur le réseau que sur le café. Un appel qui ignore l'annulation ne peut plus retenir le radar. |
| `Kohi/Compare/CompareView.swift` | `AIFeedbackScale(eventID:feature: .compareSummary, store:)` sous le texte, si `.aiFeedback` est actif | Même usage que dans `AskSheet`. Sans elle, pas de mesure d'utilité du résumé. |
| `Kohi/App/Strings.swift` | `Copy.filterPeriod … filterProfile`, `periodThisMonth/ThreeMonths/ThisYear`, `ratingFourAndUp`, `ratingFive`, `noTastingMatches`, `noRecipeMatches`, `removeFilter(_:)` | Textes écrits en dur par les lots 4 et 5 (règle du design system) |
| `FilterPicker`, `RecipeFilters`, `TastingFilters`, `RecipesScreen`, `TastingsScreen` | Ces fichiers utilisent `Copy` | Idem. Le texte affiché ne change pas, donc les snapshots non plus. |
| `KohiTests/CompareSummaryTests.swift` | Une opération lente renvoie `DeadlineExceeded`, une rapide sa valeur | Tests du délai |
| `Kohi.xcodeproj/project.pbxproj` | `CURRENT_PROJECT_VERSION` 17 → 18 (Debug et Release de la cible app) | Build TestFlight |

**Retiré :** le chip « méthode du kit » dans Brews (`RecipeFilters.seeded`). Il cassait Mine et attend une décision de JB.

**Non fait :**
- `docs/blueprint/inventory.yaml` (seul le CHANGELOG le note) ;
- synchronisation Figma : le connecteur n'est pas authentifié.

### 4.2 Fonctions edge Supabase

**Architecture actuelle des deux assistants :**

```
app ──(JWT utilisateur)──► compare-summary / ask
                              │ requireUser()          _shared/auth.ts      401 / 503
                              │ provider(body)         _shared/provider.ts  "openai-first" | "openai" | "gemini"
                              ├─ withOpenAI()  ──►     _shared/openai.ts    generateJSON(system, user, name, schema, model, { timeoutMs })
                              └─ withGemini()  ──►     _shared/gemini.ts    generate(key, parts, config, { attemptMs, models })
```

**`_shared/provider.ts`** (nouveau) :
- `provider(body)` renvoie `"openai"` ou `"gemini"` si le corps le demande exactement, sinon `"openai-first"`.
- Le choix est partagé par les deux fonctions.

**`_shared/openai.ts`** :
- 6ᵉ paramètre `options.timeoutMs` (30 s par défaut). `narration-pipelines.ts` ne change pas.

**`_shared/gemini.ts`** :
- `generate(..., { attemptMs, models })` : `models` permet d'appeler flash-lite directement.
- Par défaut rien ne change : `GEMINI_MODEL` (sinon gemini-3.8-flash), puis `GEMINI_MODEL_FALLBACK` (sinon gemini-3.5-flash-lite), avec 25 s puis 90 s.

#### `compare-summary`

**`_shared/compare-summary.ts`** (nouveau) :
- **`PROMPT`** : faits donnés, sens conservé, « much » seulement si le fait le dit, pas de chiffres, pas de titres, 35 mots, anglais simple.
- **`differences(series)`** :
  - **Axes** : écarts d'au moins 2 points (`NOTABLE_AXIS`) sur les axes notés par toutes les séries, du plus grand au plus petit. 3 axes au plus (`MOST_AXES`), 2 pour un trio (`MOST_AXES_TRIO`).
  - **Note** : écart d'au moins 1 (`NOTABLE_RATING`).
  - **Saveurs** propres à une seule série.
  - **`close`** et **`slight`** : tous les axes à 1 point ou moins, et l'axe qui diffère le plus.
- **`describe(series)`** : les faits en mots, sans chiffre.
  - « much » à partir de 4 points (`LARGE_AXIS`), « slightly » pour l'écart unique de deux cafés proches.
  - Classement d'un trio (« highest / in between / lowest »).
  - 2 saveurs au plus, en minuscules. « no flavours noted » n'est pas envoyé.
- **`validSeries`** (2 ou 3 séries) et **`readSummary`**.
- **`SCHEMA`** pour Gemini et **`OPENAI_SCHEMA`** strict pour OpenAI.
- **Délais** :
  - par défaut : `OPENAI_FIRST_MS = 6000`, puis `BACKUP_MS = [5000]`, soit moins des 12 s de l'app ;
  - un fournisseur forcé : `OPENAI_MS = 15000` pour OpenAI, `ATTEMPT_MS = [6000, 20000]` pour Gemini.

**`compare-summary/index.ts`** :
- `requireUser`, puis `validSeries`, puis `describe`, puis `withOpenAI`, et `withGemini` (flash-lite seul) en cas d'échec.
- La réponse : `{ summary, provider, model, inputTokens, outputTokens, latencyMs }`.

#### `ask`

**`_shared/ask.ts`** :
- **`PROMPT`**, réécrit en 9 règles :
  - process, origines, variétés, repos et conservation comptent comme du café ;
  - le texte ne mentionne jamais les sources ;
  - pas d'id de source ni de crochets dans le texte ;
  - on répond pour la méthode demandée ;
  - depuis une comparaison, on nomme les cafés par leur numéro.
- **`SCHEMA`** et **`OPENAI_SCHEMA`** : tag `["string", "null"]`, tous les champs requis.
- **`input(sources, context, question)`** : l'ordre de lecture du modèle.
- **`cited(parsed, sources)`** : ne garde que les ids présents dans les sources. « Couvert » exige au moins une source retrouvée.
- **Délais** : `OPENAI_FIRST_MS = 15000`, `BACKUP_MS = [20000]`, `OPENAI_MS = 30000`, et `ATTEMPT_MS = [8000, 30000]` pour Gemini forcé.

**`ask/index.ts`** :
- `requireUser`, recherche plein texte dans `knowledge` (8 entrées, repli sur les 8 premières), puis `input`, puis OpenAI d'abord, puis `cited`.
- La réponse :
  ```
  { answer, isCovered, citations, tag, sources: [{ id, title, source }], provider, model, inputTokens, outputTokens, latencyMs }
  ```
- `tag` vaut null quand la réponse est couverte, `"general"` si une réponse couverte a perdu ses citations.

#### Les 8 fonctions

Toutes passent par `requireUser` (`c717f26`).

| Fonction | Modèle aujourd'hui | Dernier déploiement |
|---|---|---|
| `compare-summary` | **OpenAI d'abord**, flash-lite en secours | 22 nov., 4 fois |
| `ask` | **OpenAI d'abord**, flash-lite en secours | 22 nov., 2 fois |
| `suggested-correction` | Gemini 3.8, puis flash-lite (25 s / 90 s) | 22 nov. (garde d'auth) |
| `recipe-adapt` | Gemini 3.8, puis flash-lite | 22 nov. |
| `card-vision` (scan) | Gemini 3.8, puis flash-lite | 22 nov. |
| `field-extract` | Gemini 3.8, puis flash-lite | 22 nov. |
| `brew-narration` | Pipelines de narration (Gemini, OpenAI selon le pipeline) | 22 nov. |
| `narration-compare` | Pipelines de narration | 22 nov. |

### 4.3 Base Supabase et opérations

Toutes les requêtes de `supabase/checks/` sont lancées par JB dans l'éditeur SQL du dashboard.

| Fichier | Type | Statut |
|---|---|---|
| `2026-11-21-state.sql` | Lecture : historique des migrations, effets de 0036 à 0038 | Lancé deux fois |
| `2026-11-21-extras.sql` | Lecture : versions en trop, effets de 0019 à 0035 | Lancé |
| `2026-11-21-repair.sql` | **Écriture** dans `supabase_migrations.schema_migrations` seulement, en transaction avec contrôle final | **Lancé.** L'historique va de 0001 à 0038 sans rien d'autre. |
| `2026-11-21-events.sql` | Lecture : `ai_events` de compare-summary et ask | Disponible |
| `2026-11-21-providers.sql` | Lecture : échecs et latence par modèle (ai_events, narration_trials) | **Pas lancé** |
| `2026-11-21-testers.sql` | Lecture : comptes avec dégustations | Lancé |
| `2026-11-21-export-tastings.sql` | Lecture : export JSON des dégustations d'un testeur | Lancé pour Timour |

**Secrets présents** (noms seulement) : `OPENAI_API_KEY`, `GEMINI_API_KEY`, `ELEVENLABS_API_KEY` et les clés Supabase. Pas de `GEMINI_MODEL` ni de `OPENAI_TEXT_MODEL` : les valeurs par défaut s'appliquent.

**Compte de test des scripts** : créé par JB, identifiants dans `.env` (`KOHI_SMOKE_EMAIL`, `KOHI_SMOKE_PASSWORD`). Les scripts se connectent avec. Le mot de passe est faible : à changer ou à supprimer après la bêta.

### 4.4 Scripts d'évaluation (Deno)

**`scripts/compare-real.ts`** : le résumé sur de vraies dégustations.
```bash
deno run --allow-net --allow-read --allow-write --allow-env scripts/compare-real.ts .private/tastings.json [--limit=15] [--provider=app|gemini|openai|both] [--dry-run]
```
- **Lit l'export** comme l'app : `axes()` reprend `TasteProfile`, y compris l'ancien format 1–5, `flavorName()` reprend la roue et les saveurs personnalisées, `ratingPoints()` reprend `HalfRating`.
- **Choisit 15 comparaisons** (`choose`) : 60 % de paires éloignées, des trios, 20 % de paires proches, chaque dégustation 3 fois au plus, jamais deux fois le même jeu de cafés.
- **Contrôles** (`checks`) :
  - un café non nommé par son numéro ;
  - un axe cité pour un écart de moins de 2, sauf un écart unique annoncé « slight » ;
  - une saveur absente des dégustations ;
  - deux cafés proches non dits proches ;
  - **le sens** (`direction`) : un café dit plus haut ou plus bas à tort, y compris les égalités (« No. 2 and No. 3 ») et les « than No. n ».
- **`session()`** est exporté : JWT ou compte de test.
- **Rapport** dans `.private/compare-real-<stamp>[-duel].md`.

**`scripts/ask-duel.ts`** : `ask` sur 12 questions.
```bash
deno run --allow-net --allow-read --allow-write --allow-env scripts/ask-duel.ts [--provider=app|gemini|openai|both]
```
- **Les questions** : 9 sur l'infusion et les process, 1 hors sujet, 2 avec le contexte Compare des cafés de Timour (même format que `CompareSummary.context`).
- **Contrôles** :
  - un refus manqué, ou une question de café refusée ;
  - une réponse couverte sans citation, une citation hors des sources ;
  - plus de 2 paragraphes, plus de 180 mots, un point d'exclamation ;
  - « the provided sources… », un id de source dans le texte ;
  - une réponse depuis Compare sans numéro de café.
- **Rapport** dans `.private/ask-duel-<stamp>.md`.

**Tests :**
```bash
deno test supabase/functions/_shared/     # 36 tests
deno test --allow-read scripts/           # 10 tests
deno check supabase/functions/*/index.ts scripts/*.ts
```

### 4.5 Documents

- **`docs/assistants-gemini-vs-openai.md`** : le plan multi-modèle, avec deux sections de résultats (résumé, `ask`) et les décisions de JB.
- **`docs/blueprint/CHANGELOG.md`** : l'échelle d'utilité et l'inventaire à synchroniser.
- **Ce document.**

---

## 5. Déploiements en production

Tous les déploiements ont été confirmés par JB juste avant, avec `supabase functions deploy <fn> --use-api` (pas de Docker sur ce poste).

| Quand | Quoi | Effet |
|---|---|---|
| 21 nov. | `compare-summary` | Module partagé, primaire limité à 6 s |
| 22 nov. | Les 8 fonctions | Garde d'auth (`c717f26`), délais de `ask` 8 s / 30 s |
| 22 nov. | `compare-summary` | Écarts calculés côté serveur |
| 22 nov. | `compare-summary` | Faits sans chiffres, 3 axes, 2 saveurs |
| 22 nov. | `compare-summary` | Option `provider` (duel) |
| 22 nov. | `compare-summary` | **OpenAI d'abord**, 2 axes par trio, pas de titres |
| 22 nov. | `ask` | **OpenAI d'abord** |
| 22 nov. | `ask` | Prompt corrigé, `cited()` |

**Écriture SQL en prod** : `repair.sql` seulement, sur l'historique des migrations.

---

## 6. Mesures

### 6.1 `compare-summary` sur les 19 dégustations de Timour (15 comparaisons)

| Passe | Fournisseur | Répondu | Médiane / p90 | Jugé à la main |
|---|---|---|---|---|
| 1. Prompt d'origine, données brutes | Gemini (flash-lite à chaque fois) | 14 / 15 | 5,2 s / 10,8 s | 8 ✓, 5 ≈, 1 ✗ (deux affirmations inversées), 1 sans résumé |
| 2. Écarts calculés | Gemini | 15 / 15 | 0,9 s / 7,9 s | 15 ✓, mais des chiffres recopiés (« 7 compared to 5 ») |
| 3. Sans chiffres, 3 axes | Gemini | 15 / 15 | 0,9 s / 8,2 s | 15 ✓, trios longs (No. 11 en 4 phrases) |
| 4. Duel | Gemini / OpenAI | 14 / 15, 15 / 15 | 6,6 s / 9,0 s contre 1,6 s / 2,0 s | Égalité sur le fond, une imprécision OpenAI (égalité lue comme une tête) |
| 5. Chemin de l'app, OpenAI d'abord | OpenAI | 15 / 15 | **1,1 s / 1,5 s** | 15 ✓, la même imprécision sur l'égalité (No. 11), 126 caractères en médiane |

gemini-3.8-flash n'a répondu à **aucun** appel de la session. Sa latence de 6 à 12 s est l'attente du primaire avant le repli.

### 6.2 `ask` (12 questions)

| Passe | Gemini | OpenAI |
|---|---|---|
| 1. Prompt d'origine | 10 / 12, 5 non-réponses (« the provided sources do not… »), espresso pour une question de pour-over | 12 / 12, thermal shock refusé, une citation inventée, des ids dans le texte |
| 2. Prompt corrigé, `cited()` | 7 / 12 (5 × 503), 1 « provided sources » | **12 / 12, 0 signalement**, 2,6 s / 3,0 s |

Imprécision repérée à la lecture : à la question 12, OpenAI présente No. 2 comme « plus sucré », alors qu'il est le moins sucré des trois.

### 6.3 Coûts mesurés

Tokens renvoyés par les fonctions, tarifs de nov. 2026.

| | Gemini 3.5 flash-lite (0,30 / 2,50 $ par M) | gpt-5.6-luna (0,20 / 1,20 $ par M) |
|---|---|---|
| Un résumé | ~0,00023 $ | ~0,00014 $ |
| Une réponse `ask` | ~0,0005 $ | ~0,00035 $ |

Le comptage de Gemini exclut les tokens de réflexion (`thoughtsTokenCount`), son coût réel est donc plus haut. Les tarifs de gemini-3.8-flash doublent au 1ᵉʳ janvier 2027.

---

## 7. Décisions prises par JB

1. **SQL** : Claude écrit les requêtes dans `supabase/checks/`, JB les lance et colle le résultat.
2. **Méthode du kit en chip visible** dans Brews. Implémenté puis retiré parce qu'il cassait Mine. **À retrancher.**
3. **Comparaison de modèles** : Gemini contre OpenAI seulement, pas de Claude pour l'instant.
4. **Vraies données** : pas de connexion au compte de Timour. On passe par un export en lecture seule dans `.private/`.
5. **Compte de test** pour les scripts, enregistré dans `.env` (« ne plus me les redemander »).
6. **Calcul des écarts côté serveur**, puis le style « en mots ».
7. **OpenAI d'abord** pour `compare-summary`, puis pour `ask`.
8. **Égalité sur les trios** : laissée telle quelle (« Fine as is »).
9. **Build TestFlight 18.**

---

## 8. Limites connues

### Produit et IA

- **Il faut être connecté.** Depuis `c717f26`, toute fonction IA refuse un appel sans session (401). Sign in with Apple est facultatif dans l'app, donc un testeur non connecté n'a plus aucune IA, sans message qui l'explique. L'app retombe sur son comportement d'échec.
- **Aucune vérification en direct dans l'app depuis les déploiements.** Le simulateur n'est pas connecté et n'a aucune dégustation. Les scripts appellent les mêmes fonctions déployées, mais l'affichage réel (shimmer, échelle d'utilité, AskSheet avec sources) n'a pas été vu.
- **Les égalités dans les trios** : « No. 2 and No. 3 higher than No. 1 » peut devenir « No. 2 has the highest acidity ».
- **`ask` peut confondre les scores d'une comparaison** (question 12 : « sweeter » pour le moins sucré). Le contexte Compare est donné brut, sans faits calculés.
- **`ask` cherche par plein texte en anglais** sur `knowledge` (8 entrées). Sans correspondance, il retombe sur « les 8 premières », pas sur le sujet. Une question en français trouve mal.
- **Pas de délai côté app pour `ask`.** Il dépend du délai par défaut d'URLSession (60 s), alors que le serveur peut prendre jusqu'à 35 s (15 + 20).
- **Les 6 autres fonctions restent sur gemini-3.8-flash en primaire, avec 25 s avant le repli.** Le scan (`card-vision`), l'extraction de champs, la correction suggérée et l'adaptation de recette subissent la même indisponibilité.
- **`ai_events` ne stocke pas le fournisseur**, seulement le modèle (assez pour distinguer `gpt-5.6-luna` de `gemini-…`). Il n'enregistre pas non plus qu'il y a eu repli.
- **Pas de duel dans l'app** : table `ai_duels`, écran A/B et rapport (étapes 2 à 4 du plan) ne sont pas commencés. Les comparaisons se font par script, jugées par Claude et JB, pas par les testeurs.

### Évaluation

- **Les contrôles des scripts sont des heuristiques** (expressions régulières). Ils ont eu des faux positifs (« Bitter » comme saveur, égalités) et en ont raté (une inversion avant `direction`). Le jugement final reste à l'œil.
- **Un seul testeur** (Timour, 19 dégustations, scores serrés entre 4 et 7). À élargir avant de généraliser.
- **Les questions de `ask` sont écrites par Claude**, pas tirées de vraies questions : `ai_events` ne garde pas le contenu.

### Technique et opérations

- **Commité sur `lot-6-followups`, mais ni fusionné ni poussé** : la prod est en avance sur `main` (voir §2.3).
- **Suite iOS complète pas relancée** depuis la fusion de `c717f26` et les derniers changements côté app. Seule la compilation a été vérifiée. Il y a 12 échecs de snapshots antérieurs, sans lien.
- **Blueprint** : `inventory.yaml` n'est pas mis à jour, Figma n'est pas synchronisé.
- **Bug du scan (lot 2) pas reproduit** sur une carte de plus de 6 notes.
- **Supabase CLI 2.22.6** (3.2.0 disponible). Sans Docker, il faut `--use-api`.
- **Historique des migrations** : aucune règle n'empêche une nouvelle dérive. Une migration appliquée par le dashboard ou l'API crée une version datée.
- **Le build 18 n'est ni archivé ni envoyé** sur App Store Connect.

### Données personnelles

- **`.private/tastings.json`** contient les dégustations de Timour (noms de cafés, lieux, dates, notes). Le dossier est git-ignoré. **Prévenir Timour** et supprimer le dossier quand l'évaluation est finie.

---

## 9. Ce qu'on pourrait encore optimiser

Par ordre de rapport effort / gain.

1. **Commit, push, déploiement aligné** : figer la prod dans git (§10).
2. **Secret `GEMINI_MODEL=gemini-3.5-flash-lite`** : sans code, les 6 fonctions restées sur Gemini sautent le primaire indisponible et ses 25 s d'attente. C'est réversible en supprimant le secret. À confirmer avec `providers.sql`.
3. **`_shared/llm.ts`** : `withOpenAI` et `withGemini` existent en double dans `ask` et `compare-summary`. Une seule fonction `call({ provider, system, input, schema, timeouts })` et un `toOpenAISchema()` (plan, étape 1) rendraient la vague 2 triviale.
4. **Vague 2 sur OpenAI d'abord** : `suggested-correction`, `recipe-adapt`, puis `field-extract` et `card-vision` (vision : vérifier le support image et le coût de gpt-5.6-luna avant).
5. **Fournisseur et repli dans `ai_events`** : colonnes `provider` et `fell_back`, plus les tokens de réflexion de Gemini, pour un coût réel.
6. **Délai côté app pour `ask`** : réutiliser `CompareSummary.withDeadline`, avec environ 40 s.
7. **Message « Connectez-vous pour Coffee Intelligence »** quand la fonction répond 401, au lieu d'un silence.
8. **Contexte Compare calculé pour `ask`** : passer les faits de `describe()` en plus des scores bruts, pour éviter « sweeter » à l'envers.
9. **Égalités explicites dans `describe()`** : « No. 2 and No. 3 tied highest ».
10. **Recherche de `ask`** : configuration `simple` ou multilingue, repli par `topic` plutôt que « les 8 premières », plus tard des embeddings si la base grossit.
11. **Duel dans l'app** (plan, étapes 2 à 4) : `ai_duels`, réponse A/B à l'aveugle, rapport. C'est le seul moyen d'avoir l'avis des testeurs plutôt que le nôtre.
12. **Contrôles des scripts plus robustes** : passer d'expressions régulières à une vérification structurée, en faisant renvoyer au modèle les faits qu'il cite. Ou un deuxième modèle juge, avec relecture humaine.
13. **Règle de migration** : `supabase db push` seulement, ou renommer la version datée juste après une application par le dashboard. À écrire dans les règles Cursor (§11).

---

## 10. Reste à faire

**Bloquant, dans cet ordre :**
- [x] **Commits sur `lot-6-followups`** (22 nov. : `29f6cea` app, `c9dfea8` compare-summary, `a8aaf2e` ask, `b553e6b` scripts et SQL, `45c9cf5` docs, `7d37b35` build 18), dans le style du dépôt (phrases complètes en anglais), découpés par sujet :
  1. lot 6 côté app (délai, échelle d'utilité, `Copy`) ;
  2. `compare-summary` (faits calculés, OpenAI d'abord) et ses tests ;
  3. `ask` (OpenAI d'abord, prompt, `cited`) et ses tests ;
  4. scripts d'évaluation et `supabase/checks/` ;
  5. docs ;
  6. build 18.
- [ ] Relancer **`Tools/run-tests.sh both`**, en notant les 12 échecs de snapshots antérieurs, ainsi que les tests Deno.
- [ ] **Fusion dans `main`**, puis **push de `main`** après confirmation de JB : 6 commits plus `c717f26` plus ceux du lot 6.
- [ ] Supprimer les branches fusionnées : `lot-1…5`, `claude/vigilant-mendeleev-474b7a`, puis `lot-6-followups`.
- [ ] **Archiver et envoyer le build 18** depuis Xcode (Product › Archive, puis Distribute › TestFlight).

**Vérifications :**
- [ ] Se connecter dans le simulateur, puis :
  - poser une question à Coffee Intelligence (sources affichées, pas d'id dans le texte) ;
  - comparer deux dégustations avec goût (résumé en moins de 2 s, échelle d'utilité).
- [ ] Lancer `supabase/checks/2026-11-21-events.sql` : voir `gpt-5.6-luna` dans `ai_events`, et les éventuels `timeout`.
- [ ] Lancer `supabase/checks/2026-11-21-providers.sql`.
- [ ] Reproduire le bug du scan (carte de plus de 6 notes, idéalement l'éthiopien de Timour).
- [ ] Contrôles visuels : 4ᵉ tuile refusée, roue à plat, filtre « 4★ and up ».

**Décisions de JB :**
- [ ] Chip de la méthode du kit : comment le réintroduire sans casser Mine.
- [ ] Le secret `GEMINI_MODEL` (§9, point 2).
- [ ] La vague 2 sur OpenAI.
- [ ] Le duel dans l'app (étapes 2 à 4 du plan).
- [ ] Ce qu'on fait des données de Timour : prévenir Timour, supprimer `.private/` à la fin.

---

## 11. Gabarit pour Cursor (et les prochaines sessions)

### 11.1 Règles du projet à respecter

- **Design system** : `docs/design-system.md`. Couleurs par `Palette`, polices par `Typography`, animations par `Motion`, haptique par `Haptic`, et **tout texte visible dans `Copy`** (`Kohi/App/Strings.swift`).
- **Swift** : isolation MainActor par défaut, `nonisolated` pour les types hors UI. Stores JSON `@Observable`. Tests en Swift Testing plus SnapshotTesting. Le simulateur de référence est l'**iPhone 16 sous iOS 18.2**.
- **Aucun test supprimé.** Les snapshots ne bougent que si le rendu change exprès.
- **Commits** : seulement à la demande de JB. Messages en phrases complètes en anglais, qui disent ce que la personne voit ou ce qui change (voir `git log`).
- **Prod Supabase** : chaque déploiement et chaque écriture SQL est **confirmé par JB juste avant**. Le SQL est écrit dans `supabase/checks/AAAA-MM-JJ-<sujet>.sql`, en lecture seule sauf mention contraire, et c'est **JB qui le lance**.
- **Secrets** : ne jamais afficher l'URL ni les clés de `Kohi/Resources/Supabase.plist`, ni le contenu de `.env`. Ne pas lire de jeton dans le trousseau.
- **Données personnelles** : jamais de connexion au compte d'un testeur. Export en lecture seule vers `.private/` (git-ignoré). Prévenir le testeur.
- **Concurrence** : Cursor et Claude Code travaillent parfois **dans le même checkout**. Vérifier `git status` avant d'écrire, ne pas laisser de fichier temporaire dans `KohiTests/` (synchronisé par Xcode, donc compilé).

### 11.2 Commandes

```bash
# App
Tools/build.sh                                  # compile pour le simulateur
Tools/run-tests.sh                              # iOS 18.2
Tools/run-tests.sh both                         # iOS 18.2 et 26.2
Tools/run-tests.sh 18 CompareSummaryTests       # un seul suite

# Fonctions edge
deno test supabase/functions/_shared/
deno check supabase/functions/*/index.ts
supabase functions deploy <fonction> --use-api  # après accord de JB ; pas de Docker ici
supabase secrets list                           # noms seulement

# Évaluation sur vraies données (session : .env)
deno run --allow-net --allow-read --allow-write --allow-env scripts/compare-real.ts .private/tastings.json [--provider=app|both]
deno run --allow-net --allow-read --allow-write --allow-env scripts/ask-duel.ts [--provider=app|both]
deno test --allow-read scripts/
```

### 11.3 Pièges rencontrés

- **`supabase functions deploy`** échoue sans Docker : ajouter `--use-api`.
- **`supabase migration list --linked`** demande le mot de passe de la base. Passer par `state.sql` dans le dashboard.
- **Une migration appliquée par le dashboard ou l'API** est enregistrée sous une version datée, d'où la dérive de l'historique. Utiliser `supabase db push`.
- **zsh** : `$B:path` est une substitution. Écrire `"${B}":path`.
- **Deno** : un tableau littéral de chaînes devient un type union (`"gemini" | "openai"`). Annoter `string[]` ou `Map<string, …>`.
- **Découpage de phrases** : `.split(".")` coupe « No. 2 ». Utiliser `/\.(?!\s?\d)/`.
- **Gemini** :
  - `usage.candidatesTokenCount` exclut la réflexion ;
  - gemini-3.8-flash est souvent indisponible (503 « high demand », timeouts) ;
  - pour un utilisateur qui attend, ne jamais laisser 25 s au primaire.
- **OpenAI** : le schéma JSON strict exige toutes les propriétés en `required`, `additionalProperties: false`, et `["type", "null"]` pour une valeur nulle.
- **Les modèles recopient ce qu'on leur donne.** Des chiffres dans les faits finissent dans le texte, « no flavours noted » aussi. Ne donner que ce qu'on accepte de voir écrit.
- **Les modèles se trompent sur l'arithmétique** (sens d'un écart, seuil de 2 points). Calculer côté serveur, et ne laisser au modèle que la rédaction.

### 11.4 Gabarit d'itération sur une fonction IA

À suivre pour la vague 2 ou tout nouveau prompt.

1. **Isoler les règles pures** dans `supabase/functions/_shared/<fonction>.ts` : prompt, schémas Gemini et OpenAI, calculs, lecture de la réponse, délais. Les tester dans `<fonction>_test.ts`. `index.ts` ne garde que `Deno.serve`, l'auth et les appels.
2. **Calculer côté serveur** tout ce qui est un fait (écarts, sens, seuils, citations valides). Le modèle ne fait que rédiger.
3. **Fournisseur** : `provider(body)` (`_shared/provider.ts`), OpenAI d'abord puis flash-lite, et la somme des délais sous le délai de l'app. Un test le garantit, comme dans `compare-summary_test.ts`.
4. **Évaluer sur de vraies données** :
   - export en lecture seule (`supabase/checks/…-export-*.sql`) vers `.private/` ;
   - script `scripts/<fonction>-real.ts` ou `-duel.ts` avec `--provider=both`, des contrôles automatiques et un rapport Markdown dans `.private/` ;
   - un jugement à l'œil de chaque sortie, consigné dans le doc du plan.
5. **Itérer** : corriger le prompt ou les faits, `deno test`, déployer (après accord), relancer le script, comparer avec la passe précédente.
6. **Consigner** dans `docs/assistants-gemini-vs-openai.md` : le tableau des résultats, les défauts corrigés, ce qui reste et la décision de JB.

### 11.5 Modèle de consigne pour Cursor

```
Contexte : docs/session-2026-11-21-22-lot-6-assistants.md (§8 limites, §9 optimisations, §11 règles).
Tâche : <point du §9 ou du §10>.
Contraintes : design system (Copy, Palette, Typography, Motion, Haptic) ; aucun test supprimé ;
pas de commit ni de déploiement sans mon accord ; SQL dans supabase/checks/, que je lance ;
jamais de secret affiché ; vérifier git status avant d'écrire (checkout partagé avec Claude Code).
Fini quand : tests Deno et Tools/run-tests.sh verts ; pour une fonction IA, le script
d'évaluation relancé et ses résultats consignés dans docs/assistants-gemini-vs-openai.md.
```

---

## 12. Index des fichiers de la session

| Fichier | Rôle |
|---|---|
| `docs/assistants-gemini-vs-openai.md` | Plan multi-modèle, résultats, décisions |
| `docs/session-2026-11-21-22-lot-6-assistants.md` | Ce document |
| `supabase/functions/_shared/provider.ts` | Choix du fournisseur |
| `supabase/functions/_shared/compare-summary.ts` (+ `_test`) | Faits, prompt et délais du résumé |
| `supabase/functions/_shared/ask.ts` (+ `_test`) | Prompt, schémas, `input`, `cited` et délais de `ask` |
| `supabase/functions/_shared/gemini.ts` | `models` en option |
| `supabase/functions/_shared/openai.ts` | `timeoutMs` en option |
| `supabase/functions/compare-summary/index.ts` | OpenAI d'abord, puis flash-lite |
| `supabase/functions/ask/index.ts` | OpenAI d'abord, puis flash-lite, citations vérifiées |
| `supabase/checks/2026-11-21-*.sql` | État, réparation, événements, fournisseurs, testeurs, export |
| `scripts/compare-real.ts` (+ `_test`) | Évaluation du résumé sur vraies dégustations |
| `scripts/ask-duel.ts` (+ `_test`) | Évaluation de `ask` |
| `Kohi/AI/CompareSummary.swift` | Délai de 12 s |
| `Kohi/Compare/CompareView.swift` | Échelle d'utilité |
| `Kohi/App/Strings.swift` | Textes des filtres |
| `Kohi.xcodeproj/project.pbxproj` | Build 18 |
| `.private/` (git-ignoré) | `tastings.json`, rapports `compare-real-*.md` et `ask-duel-*.md`, images `compare-screens/` |
| `.env` (git-ignoré) | Compte de test des scripts |
