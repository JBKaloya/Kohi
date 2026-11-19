# Dictation evaluation set

One JSON file per Live narration. `phrases` is what Speech returned (word or
sentence, seconds from the start of the recording); `expected` is what was
actually done, written by the brewer. `confirmed` stays false until JB has
checked `expected` against the brew.

Real recordings come from Profile, Developer, "Share last dictations" (DEBUG
builds), or from the `dictations` bucket and `public.dictations` table. The
audio stays out of git; only the phrases and the expected steps live here.

`scripts/eval-narration.ts` sends the audio of a case (when `audio` names a
local file) to `brew-narration` and scores the steps it returns against
`expected`.
