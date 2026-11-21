// compare-summary: what sets two or three compared coffees apart, in one or
// two plain sentences that name them by their number.
//
// The radar already shows every axis. This only says which differences are
// worth noticing, so a gap of one point on one axis is left out, and a
// summary that has nothing notable to say says they are close.
//
// Secrets:  GEMINI_API_KEY
// Optional: GEMINI_MODEL, GEMINI_MODEL_FALLBACK (see _shared/gemini.ts)

import { generate } from "../_shared/gemini.ts";

const PROMPT = `\
You compare two or three coffees for Kohi, a coffee journal.

Each one has a number (1, 2, 3), a title, seven taste axes scored 0 to 10 \
(an axis that was not scored is absent), its main flavours and a rating out \
of 5 when there is one.

Write one or two short sentences that say what sets them apart. Rules:
1. Name each coffee by its number: "No. 1", "No. 2".
2. Only notable differences: two points or more on an axis, a flavour one has \
   and the others lack, a clear gap in rating. Leave the rest out.
3. If nothing differs notably, say they are close and name the one thing \
   that differs most.
4. Plain English. No jargon, no marketing adjectives, no exclamation marks.
5. Never invent an axis, a flavour or a rating that is not given.`;

const SCHEMA = {
  type: "OBJECT",
  properties: { summary: { type: "STRING" } },
  required: ["summary"],
};

type Series = {
  number: number;
  title: string;
  detail?: string;
  axes: Record<string, number>;
  flavors?: string[];
  rating?: number | null;
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return json({ error: "function is not configured" }, 500);

  let body: { series?: Series[] };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  const series = (body.series ?? []).slice(0, 3);
  if (series.length < 2) return json({ error: "two to three series" }, 400);

  const started = Date.now();
  const result = await generate(apiKey, [
    { text: PROMPT },
    { text: `Coffees:\n${JSON.stringify(series)}` },
  ], {
    temperature: 0.2,
    responseMimeType: "application/json",
    responseSchema: SCHEMA,
    thinkingConfig: { thinkingLevel: "low" },
  });

  if (!result.ok) {
    return json(
      { error: `model returned ${result.status}`, model: result.model },
      result.status === 429 ? 429 : 502,
    );
  }

  const { text, usage, model } = result;
  if (!text) return json({ error: "empty model response" }, 502);

  const parsed = JSON.parse(text);
  const summary = typeof parsed.summary === "string" ? parsed.summary.trim() : "";
  if (!summary) return json({ error: "empty summary" }, 502);

  return json({
    summary,
    model,
    inputTokens: usage.promptTokenCount ?? null,
    outputTokens: usage.candidatesTokenCount ?? null,
    latencyMs: Date.now() - started,
  });
});
