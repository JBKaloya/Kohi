// compare-summary: what sets two or three compared coffees apart, in one or
// two plain sentences that name them by their number.
//
// The radar already shows every axis. This only says which differences are
// worth noticing, so a gap of one point on one axis is left out, and a
// summary that has nothing notable to say says they are close. The
// differences are worked out here (_shared/compare-summary.ts); the model
// only puts them into words.
//
// OpenAI writes it, and Gemini's light model takes over when OpenAI fails or
// is slow. A body can ask for `"provider": "openai"` or `"gemini"` alone: the
// beta compares the two on the same facts and the same prompt.
//
// Secrets:  OPENAI_API_KEY, GEMINI_API_KEY
// Optional: OPENAI_TEXT_MODEL, OPENAI_REASONING (see _shared/openai.ts),
//           GEMINI_MODEL, GEMINI_MODEL_FALLBACK (see _shared/gemini.ts)

import { generate, models } from "../_shared/gemini.ts";
import { generateJSON } from "../_shared/openai.ts";
import { requireUser } from "../_shared/auth.ts";
import {
  ATTEMPT_MS,
  BACKUP_MS,
  describe,
  OPENAI_FIRST_MS,
  OPENAI_MS,
  OPENAI_SCHEMA,
  PROMPT,
  provider,
  readSummary,
  SCHEMA,
  validSeries,
} from "../_shared/compare-summary.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

type Written =
  | { ok: true; summary: string; provider: string; model: string; inputTokens: number | null; outputTokens: number | null }
  | { ok: false; status: number; error: string; provider: string; model: string };

async function withOpenAI(facts: string, timeoutMs: number): Promise<Written> {
  const result = await generateJSON(PROMPT, facts, "compare_summary", OPENAI_SCHEMA, undefined, { timeoutMs });
  if (!result.ok) {
    return { ok: false, status: result.status, error: `model returned ${result.status}`, provider: "openai", model: result.model };
  }
  const summary = readSummary(result.text);
  if (!summary) return { ok: false, status: 502, error: "empty summary", provider: "openai", model: result.model };
  return {
    ok: true,
    summary,
    provider: "openai",
    model: result.model,
    inputTokens: result.inputTokens,
    outputTokens: result.outputTokens,
  };
}

async function withGemini(facts: string, options: { attemptMs: number[]; models?: string[] }): Promise<Written> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return { ok: false, status: 500, error: "function is not configured", provider: "gemini", model: "" };
  const result = await generate(apiKey, [{ text: PROMPT }, { text: facts }], {
    temperature: 0.2,
    responseMimeType: "application/json",
    responseSchema: SCHEMA,
    thinkingConfig: { thinkingLevel: "low" },
  }, options);
  if (!result.ok) {
    return { ok: false, status: result.status, error: `model returned ${result.status}`, provider: "gemini", model: result.model };
  }
  const summary = readSummary(result.text);
  if (!summary) return { ok: false, status: 502, error: "empty summary", provider: "gemini", model: result.model };
  return {
    ok: true,
    summary,
    provider: "gemini",
    model: result.model,
    inputTokens: result.usage.promptTokenCount ?? null,
    outputTokens: result.usage.candidatesTokenCount ?? null,
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const auth = await requireUser(req);
  if (!auth.ok) return auth.response;

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  const series = validSeries(body);
  if (!series) return json({ error: "two to three series" }, 400);

  const facts = describe(series);
  const started = Date.now();
  let written: Written;
  switch (provider(body)) {
    case "openai":
      written = await withOpenAI(facts, OPENAI_MS);
      break;
    case "gemini":
      written = await withGemini(facts, { attemptMs: ATTEMPT_MS });
      break;
    default: {
      written = await withOpenAI(facts, OPENAI_FIRST_MS);
      if (!written.ok) {
        console.error(`compare-summary: openai failed (${written.error}), gemini takes over`);
        // Straight to the light model: the primary has been the slow one.
        written = await withGemini(facts, { attemptMs: BACKUP_MS, models: [models().at(-1)!] });
      }
    }
  }

  if (!written.ok) {
    return json(
      { error: written.error, provider: written.provider, model: written.model },
      written.status === 429 ? 429 : 502,
    );
  }
  return json({
    summary: written.summary,
    provider: written.provider,
    model: written.model,
    inputTokens: written.inputTokens,
    outputTokens: written.outputTokens,
    latencyMs: Date.now() - started,
  });
});
