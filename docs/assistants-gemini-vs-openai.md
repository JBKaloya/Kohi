# Assistants : Gemini contre OpenAI, jugés par les testeurs (plan, 21 nov. 2026)

**État** : plan, rien n'est codé. Brewing (narration) est hors périmètre : il a déjà son comparatif (`docs/audio-models-audit.md`). Pas de modèle Claude pour l'instant.

## Premier résultat : le résumé de comparaison (22 nov. 2026)

**Le test.** 15 comparaisons tirées des 19 dégustations de Timour, exportées en lecture seule et lancées avec `scripts/compare-real.ts --provider=both`. Les deux modèles reçoivent les mêmes faits, calculés par le serveur, et le même prompt.

| | Gemini (flash-lite en repli) | OpenAI (gpt-5.6-luna) |
|---|---|---|
| Répondu | 14 / 15 (un 503) | 15 / 15 |
| Latence médiane / p90 | 6,6 s / 9,0 s | 1,6 s / 2,0 s |
| Erreurs de fond | 0 | 1 mineure (égalité lue comme une tête) |
| Coût par résumé | ~0,00023 $ | ~0,00014 $ |

gemini-3.8-flash n'a répondu à aucun appel. Les 6 s de latence de Gemini sont l'attente de ce modèle avant le repli.

**Décision de JB.** `compare-summary` passe à OpenAI d'abord (6 s), puis gemini-3.5-flash-lite en secours (5 s), sous le délai de 12 s de l'app. `provider: "openai"` ou `"gemini"` force un seul fournisseur, pour les comparaisons.

## Deuxième résultat : l'assistant `ask` (22 nov. 2026)

**Le test.** 12 questions avec `scripts/ask-duel.ts` : 9 sur l'infusion et les process, 1 hors sujet, et 2 posées depuis une comparaison des cafés de Timour. Mêmes sources et même prompt pour les deux modèles. On l'a lancé deux fois, avant et après la correction du prompt.

| | Gemini | OpenAI (gpt-5.6-luna) |
|---|---|---|
| Répondu, 1ᵉʳ passage | 10 / 12 (503) | 12 / 12 |
| Répondu, 2ᵉ passage | 7 / 12 (503) | 12 / 12 |
| Vraies réponses, 1ᵉʳ passage | 5 : les autres disent « the provided sources do not… » | 11 |
| Latence médiane / p90, 2ᵉ passage | 2,8 s / 6,0 s | 2,6 s / 3,0 s |
| Coût par réponse | ~0,0005 $ | ~0,00035 $ |

**Les défauts d'OpenAI au 1ᵉʳ passage, corrigés :**
- **Thermal shock refusé comme hors sujet.** Le prompt range désormais les process, origines, variétés, le repos et la conservation dans le café.
- **Un id de source inventé, présenté comme couvert par la base.** Le serveur ne garde que les citations présentes dans la base (`cited()`). Une réponse qui n'en garde aucune n'est plus « couverte ».

**Corrigé pour les deux modèles :**
- les ids de source dans le texte ;
- « the provided sources… » ;
- une réponse espresso à une question de pour-over.

**Ce qui reste.** Au 2ᵉ passage, OpenAI fait 0 signalement. Une imprécision lue à l'œil : dans la question 12, No. 2 est présenté comme « plus sucré », alors qu'il est le moins sucré des trois.

**Décision de JB.** `ask` passe à OpenAI d'abord (15 s), puis gemini-3.5-flash-lite en secours (20 s). Le choix du fournisseur est partagé avec `compare-summary`, dans `_shared/provider.ts`.

**Pour la suite.** La vague 2 (`suggested-correction`, `recipe-adapt`) reste sur Gemini. La couche commune `llm.ts` n'est pas écrite : chaque fonction appelle encore `generate` et `generateJSON` elle-même.

## Troisième résultat : la lecture des étiquettes, `card-vision` (22 nov. 2026)

**Le test.** 22 cafés réels (35 photos), toutes les faces envoyées en un appel, avec `scripts/scan-bench.ts`.

**Résultat.** Gemini lit 93 % des champs juste et OpenAI 94 %, mais Gemini a échoué sur 15 appels sur 33, et OpenAI sur aucun.

**Décision de JB.** `card-vision` passe à OpenAI d'abord (15 s), puis flash-lite (15 s).

Le détail est dans `docs/session-2026-11-21-22-lot-6-assistants.md`, §4 bis.

## Pourquoi

Le 21 novembre au soir, sur 8 appels à `gemini-3.8-flash` relevés dans les logs de `compare-summary` (6) et `ask` (2), **aucun n'a répondu** :

- 3 ont reçu un 503 « This model is currently experiencing high demand » ;
- les 5 autres ont dépassé le temps alloué (6 s pour le résumé, 25 s pour `ask`).

C'est `gemini-3.5-flash-lite`, le secours, qui a tout servi. Pour `ask`, il n'est appelé qu'après 25 s d'attente. Les utilisateurs reçoivent donc déjà la réponse du modèle le moins fort, et en retard.

Le plan vise deux choses :

1. **Ne plus dépendre d'un seul fournisseur.** Quand Gemini sature, OpenAI répond, et l'inverse.
2. **Choisir le modèle de chaque assistant sur ce que disent les testeurs.** Les deux modèles répondent à la même demande, l'utilisateur voit les deux réponses à l'aveugle et dit laquelle est la plus précise.

C'est la méthode qui a servi pour la narration (`narration_trials`) : avec peu de testeurs, un duel à l'aveugle donne une réponse nette à chaque interaction. Un A/B au hasard demanderait des dizaines de notes par modèle avant de conclure.

## Périmètre

| Vague | Assistant | Fonction | Ce que le testeur juge |
|---|---|---|---|
| 1 | Coffee Intelligence (question libre) | `ask` | la réponse la plus juste et la mieux sourcée |
| 1 | Résumé de comparaison | `compare-summary` | le résumé qui dit le mieux ce qui distingue les cafés |
| 2 | Correction suggérée | `suggested-correction` | les trois gestes les plus pertinents |
| 2 | Variante de recette | `recipe-adapt` | la variante la plus sensée |

**Hors duel** : les lectures (`card-vision`, `field-extract`, `menu-extract`). Elles se jugent sur les faits, c'est-à-dire les champs gardés ou corrigés, déjà suivis par `ai_events.accepted`. Elles profitent seulement du repli vers OpenAI de l'étape 1, plus tard, s'il le faut.

## Modèles comparés

| Côté | Modèle principal | Secours |
|---|---|---|
| Google | `gemini-3.8-flash` (raisonnement `low`) | `gemini-3.5-flash-lite` |
| OpenAI | `gpt-5.6-luna` (raisonnement `low`), déjà branché dans `_shared/openai.ts` | — |

## Coûts

Prix publics en novembre 2026, en dollars par million de tokens, entrée puis sortie :

- `gemini-3.8-flash` : 0,75 / 3,75, **doublé au 1ᵉʳ janvier 2027** (1,50 / 7,50) ;
- `gemini-3.5-flash-lite` : 0,30 / 2,50 ;
- `gpt-5.6-luna` : 0,20 / 1,20.

Les tokens de raisonnement sont facturés comme de la sortie chez les deux fournisseurs.

Tokens mesurés le 21 nov. sur un appel réel, sans compter le raisonnement, que les fonctions ne remontent pas encore :

| Appel | Entrée | Sortie |
|---|---|---|
| `ask` | 952 | 58 |
| `compare-summary`, 2 cafés | 350 | 57 |

Coût par appel, avec 300 tokens de raisonnement comptés en plus pour les modèles qui raisonnent :

| Appel | `gemini-3.8-flash` (2026) | idem (2027) | `gemini-3.5-flash-lite` | `gpt-5.6-luna` |
|---|---|---|---|---|
| `ask` | 0,0021 $ | 0,0042 $ | 0,0004 $ | 0,0006 $ |
| `compare-summary` | 0,0016 $ | 0,0032 $ | 0,0002 $ | 0,0005 $ |
| **Duel `ask`** (Gemini + OpenAI) | **0,0027 $** | 0,0048 $ | | |

**Ordre de grandeur pour la bêta.** 10 testeurs × 10 duels par jour × 60 jours = 6 000 duels, soit environ **16 $** au tarif 2026. Le coût ne décide de rien ici : ce sont la disponibilité, la latence et la précision qui comptent. Le rapport l'affichera quand même, pour qu'il soit sous les yeux au moment de choisir le modèle de la version publique. Au tarif 2027, `gpt-5.6-luna` reviendra environ 7 fois moins cher que `gemini-3.8-flash`.

**Écart à corriger.** `ai_events` sous-estime aujourd'hui le coût Gemini : `candidatesTokenCount` ne compte pas `thoughtsTokenCount`.

## Ce que voit le testeur

Le duel est réservé aux testeurs (Debug et TestFlight), derrière un nouveau switch **Compare assistants**, dans Profile › Experimental AI. Côté serveur, le flag s'appelle `ai-duel` dans `ai_flags`.

Exemple dans Coffee Intelligence :

1. **La question part aux deux modèles en même temps.** Deux cartes, **Réponse A** et **Réponse B**, dans un ordre tiré au hasard, sans nom de modèle. Chacune apparaît dès qu'elle arrive, et la latence fait partie de ce qu'on compare.
2. **Sous les deux réponses : « Laquelle est la plus précise ? »** Quatre choix : A, B, Les deux se valent, Aucune. Un commentaire facultatif en une ligne permet de dire ce qui ne va pas.
3. **La conversation continue** avec la réponse choisie. Avec « Les deux se valent » ou « Aucune », elle continue avec A.
4. **Si un modèle échoue ou dépasse 12 s**, l'autre réponse s'affiche seule, et l'échec est enregistré au compte du modèle fautif. Aucun vote n'est demandé.
5. **En mode duel, le duel remplace l'échelle d'utilité.** Hors duel, l'échelle reste comme aujourd'hui.

Pour le résumé de comparaison, c'est la même logique, avec deux résumés sous le radar. « Ask about this comparison » part avec le résumé choisi.

Pour les autres utilisateurs, ou si le switch est coupé, un seul modèle répond, avec un repli vers l'autre fournisseur s'il échoue (étape 1).

## Ce qui est gardé

Une ligne par duel, dans une nouvelle table `ai_duels` (migration 0039). Le modèle est `narration_trials` :

- `feature` (`ask`, `compare-summary`…) ;
- `input` (jsonb) : la question, le contexte, les cafés comparés ;
- `candidates` (jsonb), un objet par réponse : `{ slot, provider, model, ok, output, latency_ms, input_tokens, output_tokens, reasoning_tokens, cost_usd, failure }` ;
- `shown_order` : quel fournisseur était A, lequel était B ;
- `chosen` : `gemini`, `openai`, `equal`, `none`, ou null si le testeur a fermé sans voter ;
- `comment`, `app_build`, `created_at`.

L'accès est privé à chaque compte, avec la même règle d'accès (RLS) que les autres tables. C'est la seule table qui garde le texte des questions et des réponses. Elle n'existe que pour la bêta et sera vidée à la fin, ce qu'une ligne dans Profile dit aux testeurs. Chaque réponse produit aussi sa ligne `ai_events`, avec la `feature` de l'assistant et le modèle réel, pour que les tableaux existants restent justes.

## Étapes

### 0. Préalables

- **Fusionner la branche de sécurité.** `c717f26`, sur `claude/vigilant-mendeleev-474b7a`, exige une session sur les 8 fonctions et touche `ask` et `compare-summary`. Elle doit entrer avant tout le reste.
- **Correctif immédiat pour `ask`.** Ses temps d'essai passent à 8 s puis 30 s, comme `compare-summary`. Il protège les utilisateurs pendant que le reste se construit.
- **Mesurer la disponibilité de Luna sur nos propres données.** Dans `narration_trials`, on compte les échecs et la latence des pipelines `*+luna`.

### 1. Une couche commune aux deux fournisseurs

`supabase/functions/_shared/llm.ts`, avec un seul appel :

```ts
call({ provider, model, system, input, schema, attemptMs })
  → { ok, text, provider, model, latencyMs, inputTokens, outputTokens, reasoningTokens, costUsd, failure }
```

- **Schéma écrit une seule fois.** On garde le format Gemini déjà écrit dans chaque fonction, et une fonction pure `toOpenAISchema()` le traduit :
  - les types passent en minuscules ;
  - `nullable` devient `["x", "null"]` ;
  - toutes les propriétés deviennent `required` ;
  - `additionalProperties: false`.
- **Prompt.** Le premier texte va dans `system` chez OpenAI, le reste dans `user`. Chez Gemini, rien ne change.
- **Tokens et coût.** La couche lit aussi les tokens de raisonnement : `thoughtsTokenCount` chez Gemini, `completion_tokens_details.reasoning_tokens` chez OpenAI. La table de prix quitte `narration-pipelines.ts` pour un fichier partagé, `_shared/prices.ts`.
- **Repli d'un fournisseur à l'autre.** Pour un appel normal, l'ordre est :
  1. `gemini-3.8-flash`, 6 s ;
  2. `gpt-5.6-luna`, 15 s ;
  3. `gemini-3.5-flash-lite`, 20 s.

  Il est configurable par des secrets (`ASSISTANT_CHAIN`) pour pouvoir le changer sans déploiement.
- **Duel.** `ask` et `compare-summary` acceptent `"provider": "gemini" | "openai"`. Le modèle est alors imposé, sans repli : l'échec fait partie de la comparaison, comme pour `narration-compare`.
- **Robustesse.** On corrige au passage le `JSON.parse` non protégé de `ask`, le même défaut que celui corrigé dans `compare-summary`.
- **Tests Deno** :
  - traduction de schéma, sur les quatre schémas réels ;
  - ordre de repli ;
  - calcul du coût avec raisonnement ;
  - lecture d'une réponse vide ou invalide.

  `scripts/smoke-ai.ts` gagne des cas `provider: openai` et affiche le coût.

### 2. Base de données

Migration `0039_ai_duels.sql`, qui contient :

- la table `ai_duels` et sa règle d'accès ;
- l'index `(feature, created_at)` ;
- le flag `ai-duel` dans `ai_flags`.

Elle est appliquée avec `supabase db push`, pour que l'historique reste propre cette fois.

### 3. App

- **`AIFeature.aiDuel`** : réservé aux testeurs et expérimental, comme `compareSummary`.
- **`Kohi/AI/AIDuel.swift`.** C'est la logique du duel, sur le modèle de `NarrationCompare` :
  - les deux appels sont lancés en parallèle, avec 12 s maximum chacun (`withDeadline`) ;
  - le tirage A/B est fait au hasard ;
  - il construit la ligne à envoyer ;
  - une file d'attente gère le hors-ligne, comme `AIFeedbackStore`.
- **`Kohi/AI/AIDuelView.swift`** : les deux cartes, le choix et le commentaire. Les textes passent par `Copy`, le reste suit `Palette`, `Typography` et `Motion` ; le choix déclenche un `Haptic.selection`.
- **Intégration** :
  - dans `AskSheet`, le duel remplace la réponse unique quand le switch est actif ;
  - dans `CompareView`, le bloc résumé devient un duel.
- **Tests** :
  - le tirage couvre bien les deux ordres ;
  - un échec affiche l'autre réponse sans vote ;
  - « Aucune » et « Les deux se valent » sont enregistrés ;
  - la ligne envoyée ne contient que ce qui est prévu ;
  - snapshots de la carte duel : en attente, une réponse, deux réponses, un échec.

### 4. Lire les résultats

`scripts/assistant-duels-report.ts` reprend la forme de `narration-trials-report.ts`. Pour chaque assistant et chaque modèle, il donne :

- la part de victoires, en excluant « égales » et « aucune » ;
- la part de « aucune » ;
- la part d'échecs ;
- la latence médiane et p90 ;
- le coût moyen ;
- puis tous les commentaires.

Une requête SQL équivalente se trouve dans `supabase/checks/` pour le dashboard.

### 5. Vague 2

`suggested-correction` et `recipe-adapt` passent au duel avec la même mécanique. Leur sortie est structurée : trois gestes, ou une recette. La carte affiche donc la proposition elle-même, pas un texte libre.

## Décider

Après **au moins 30 duels votés par assistant**, l'assistant passe au modèle préféré si les trois conditions suivantes sont réunies :

- il gagne au moins 60 % des duels tranchés ;
- il échoue dans moins de 5 % des cas ;
- sa latence p90 reste sous 8 s pour ce qui s'affiche à l'écran.

À défaut, on garde le modèle le moins cher des deux, compte tenu du tarif 2027. Le choix se règle par secret, sans build. Ensuite, le duel reste allumé pour les testeurs afin de repérer les régressions quand un fournisseur publie un nouveau modèle.

## Risques

- **Biais de longueur.** La réponse la plus longue paraît souvent la plus précise. Les deux modèles reçoivent la même consigne de longueur, et le rapport compare la longueur moyenne des réponses gagnantes et perdantes.
- **Citations de `ask`.** Un modèle qui cite des sources absentes de la base doit perdre. Le serveur ne garde que les citations qui existent dans `knowledge`, pour les deux fournisseurs.
- **Peu de testeurs.** Le rapport donne les chiffres par testeur, pour qu'une seule personne très active ne décide pas pour tout le monde.
- **Le texte des testeurs.** Il est gardé le temps de la bêta seulement, et ils le savent.
