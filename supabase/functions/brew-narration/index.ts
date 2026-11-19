// brew-narration: listens to the voice note of a Live brew and returns what
// was said, when, and the steps it describes.
//
// It runs second. The app has already transcribed the note on device and
// shown the steps it could read; this answer replaces them only while the
// brewer has not touched them, and the app checks every step against the
// length of the note and the water before it does.
//
// Secrets:  GEMINI_API_KEY (required)
// Optional: GEMINI_MODEL, GEMINI_MODEL_FALLBACK (see _shared/gemini.ts)

import { generate } from "../_shared/gemini.ts";

const PROMPT = `\
You are listening to someone narrating a coffee brew out loud while they \
make it, in French or English. The recording starts when the brew starts, \
so a time in the audio is the time in the brew.

Return:
- transcript: everything that was said, verbatim, in the speaker's language.
- utterances: each sentence with the second it began at.
- steps: the brew steps the narration describes, in order.

Steps:
- action is one of: bloom, pour, swirl, stir, wait, drawdown, press, steep, \
  rinse. Nothing else.
- at is the second, from the start of the recording, at which the step was \
  said. Take it from the audio, never from a number the speaker said.
- mass is the scale reading in grams after the step, so it always grows: \
  "bloom 40" then "encore 100" is 40 then 140. Null when no mass was said, \
  and always null for wait, drawdown, swirl and stir.
- A pattern describes several steps: "je verse par palier de 40, j'attends \
  20 secondes entre chaque, jusqu'à 200", said at 8 s after a 40 g bloom, is \
  four pours: 80 at 8, 120 at 28, 160 at 48, 200 at 68. Each pour has its own \
  at, the interval apart, even though it was all said at once. The waits \
  between the pours of a pattern are not steps. When no target is said, the \
  pattern ends on the water from the context.
- "Ça draine", "drawdown", "it's draining" is a drawdown at that second.
- A time spoken as a wait ("j'attends 20 secondes") is never a mass.
- note carries what was said about the step that is not its action or its \
  mass ("plus lent", "en spirale"), verbatim. Empty otherwise.
- Do not add a step that was not said. Small talk is not a step.

dose and water are grams, only when spoken. seconds is the total brew time, \
only when spoken.`;

const NULL_NUMBER = { type: "NUMBER", nullable: true } as const;

const SCHEMA = {
  type: "OBJECT",
  properties: {
    transcript: { type: "STRING" },
    utterances: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: { at: { type: "NUMBER" }, text: { type: "STRING" } },
        propertyOrdering: ["at", "text"],
      },
    },
    steps: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          at: { type: "INTEGER" },
          action: { type: "STRING" },
          mass: NULL_NUMBER,
          until: { type: "INTEGER", nullable: true },
          note: { type: "STRING" },
        },
        propertyOrdering: ["at", "action", "mass", "until", "note"],
      },
    },
    dose: NULL_NUMBER,
    water: NULL_NUMBER,
    seconds: { type: "INTEGER", nullable: true },
  },
  propertyOrdering: ["transcript", "utterances", "steps", "dose", "water", "seconds"],
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

type Context = {
  method?: string;
  dose?: number;
  water?: number;
  duration?: number;
  recipe?: string[];
  vocabulary?: string[];
};

function describe(context: Context): string {
  const lines: string[] = [];
  if (context.method) lines.push(`Method: ${context.method}`);
  if (context.dose) lines.push(`Dose: ${context.dose} g`);
  if (context.water) lines.push(`Water: ${context.water} g`);
  if (context.duration) lines.push(`Recording length: ${Math.round(context.duration)} s`);
  if (context.recipe?.length) lines.push(`Recipe followed: ${context.recipe.join("; ")}`);
  if (context.vocabulary?.length) lines.push(`Vocabulary: ${context.vocabulary.join(", ")}`);
  return lines.join("\n");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return json({ error: "GEMINI_API_KEY is not configured" }, 500);

  let body: { audio?: string; mime?: string; context?: Context };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (!body.audio) return json({ error: "missing audio" }, 400);

  const parts: unknown[] = [
    { inlineData: { mimeType: body.mime ?? "audio/mp4", data: body.audio } },
    { text: PROMPT },
  ];
  const context = describe(body.context ?? {});
  if (context) parts.push({ text: context });

  const started = Date.now();
  const result = await generate(apiKey, parts, {
    temperature: 0,
    responseMimeType: "application/json",
    responseSchema: SCHEMA,
    thinkingConfig: { thinkingLevel: "low" },
  });

  if (!result.ok) {
    return json({
      error: result.status === 429
        ? "model quota exhausted"
        : `model returned ${result.status}`,
    }, 502);
  }

  const { text, usage, model } = result;
  if (!text) return json({ error: "empty model response" }, 502);

  return json({
    fields: JSON.parse(text),
    model,
    inputTokens: usage.promptTokenCount ?? null,
    outputTokens: usage.candidatesTokenCount ?? null,
    latencyMs: Date.now() - started,
  });
});
