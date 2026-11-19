# Audio models for brew narration — audit (19 Nov 2026)

A Live note has to give two things: what was said, and **the second each step was said**. A model that transcribes well but gives no timings cannot place the steps by itself.

## The pipelines

| Pipeline | Transcription | Reading the steps | Timings |
|---|---|---|---|
| `gemini-audio` | Gemini listens to the audio | the same call | guessed by the model |
| `scribe+luna` | ElevenLabs Scribe v2, with keyterms | `gpt-5.6-luna` | each word's second, from Scribe |
| `scribe+gemini` | ElevenLabs Scribe v2, with keyterms | Gemini, text only | each word's second, from Scribe |
| `openai+luna` | OpenAI `gpt-transcribe`, with prompt and keywords | `gpt-5.6-luna` | estimated from the iPhone's words |

`NARRATION_PIPELINE` picks the one `brew-narration` runs (default `gemini-audio`). If it fails, Gemini listens to the audio instead. `narration-compare` runs all four, with no stand-in, for testers.

## Prices (November 2026)

| Model | Price | 3-minute note |
|---|---|---|
| Gemini 3.8 Flash, audio in | $0.75 / 1M input tokens (25 tokens per second of audio), $3.75 out; doubles on 1 Jan 2027 | about $0.006 |
| Gemini 3.5 Flash-Lite | $0.30 in, $2.50 out | about $0.003 |
| ElevenLabs Scribe v2 | $0.22 / hour, keyterms +20% | about $0.013 |
| OpenAI `gpt-transcribe` | $0.0045 / minute | about $0.014 |
| OpenAI `gpt-5.6-luna` (reading the steps) | $0.20 in, $1.20 out per 1M tokens | about $0.001 |

Comparing all four on one note costs about $0.04.

Public French word error rates (Open ASR leaderboard, read speech): Scribe v2 3.3%, Voxtral Small 4.1%, `gpt-transcribe` 4.8%. Gemini publishes none. A kitchen is not read speech, which is why the choice is made on real brews.

## Phase 1: the two real Live notes archived (19 Nov)

`scripts/eval-narration.ts --archived`, every pipeline on the same audio:

| Pipeline | Answered | Latency | $/note | What it heard on the 33 s note |
|---|---|---|---|---|
| `gemini-audio` | 2/2 | 4 to 29 s (3.8 Flash overloaded, Lite answered) | $0.0011 | full text; pours of the pattern stacked at 16 s |
| `scribe+luna` | 2/2 | 6 to 8 s | $0.0025 | full text; bloom 40 at 3 s, wait at 7 s, pour 80 at 19 s |
| `scribe+gemini` | 2/2 | 6 to 27 s | $0.0024 | full text; only bloom and wait |
| `openai+luna` | 2/2 | 8 to 9 s | $0.0027 | full text; times off by about 18 s (bloom at 21 s) |
| iPhone | — | — | free | "Et enfin je termine" only |

What it shows:
- **Every cloud model hears the whole note**, where the iPhone kept four words out of 33 s.
- **Scribe's timings are exact**, and Scribe answers in about 1.4 s. The time left is the reading of the steps.
- **`gpt-transcribe` writes as well, but without timings** it depends on what the iPhone heard: when the iPhone heard almost nothing, the steps land at the wrong seconds.
- **Reading the steps varies from one call to the next** on the same text (the "paliers de 40" pattern is sometimes expanded, sometimes not). That is what the testers' comparison has to settle.

No expected steps were confirmed for these notes, so there is no step score yet.

## Phase 2: testers compare on their own brews

On Debug and TestFlight builds, with **Compare transcriptions** on (Profile › Experimental AI) and dictations shared, every Live note is sent to `narration-compare`. The after-brew sheet then shows the iPhone's reading and the four others, blind and shuffled. The tester picks one or "None is right", and can say what they would change. The pick becomes the steps, with Undo. Each answer is a row in `narration_trials`, and each cloud version an `ai_events` row (`feature = narration-compare`).

The report, per tester and for everyone:

```
SUPABASE_URL=https://zeplgxxxbqiehwidrvmm.supabase.co SUPABASE_SERVICE_KEY=<secret key> \
  deno run --allow-net --allow-env scripts/narration-trials-report.ts [--since=2026-11-19]
```

## Phase 3: decide

After 15 to 20 brews each: set `NARRATION_PIPELINE` to the pipeline picked most often, keeping an eye on "none right", failures and latency. Then turn `narration-compare` off in `ai_flags`, or leave it on for testers to catch regressions.
