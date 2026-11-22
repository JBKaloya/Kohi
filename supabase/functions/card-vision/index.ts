// card-vision: reads one or more photos of a coffee (the card, then other
// sides or pages) with a vision model and returns the structured fields. The
// model key stays server-side; the app only ever sees the JSON result.
//
// Body: { images: [{ image, mime }, …] } (up to four, the card first), or the
// single { image, mime } older builds send. OpenAI reads first and Gemini's
// light model takes over when it fails; `"provider": "openai"` or `"gemini"`
// reads with one alone, for the scan benchmark (scripts/scan-bench.ts).
//
// Secrets:   OPENAI_API_KEY, GEMINI_API_KEY
// Optional: OPENAI_TEXT_MODEL, OPENAI_REASONING (see _shared/openai.ts),
//           GEMINI_MODEL, GEMINI_MODEL_FALLBACK (see _shared/gemini.ts)

import { generate, models } from "../_shared/gemini.ts";
import { generateJSON } from "../_shared/openai.ts";
import { requireUser } from "../_shared/auth.ts";
import {
  ATTEMPT_MS,
  BACKUP_MS,
  OPENAI_FIRST_MS,
  OPENAI_MS,
  OPENAI_SCHEMA,
  type Photo,
  photos,
  PROMPT,
  SCHEMA,
  visionProvider,
  withoutNulls,
} from "../_shared/card-vision.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

type Read =
  | { ok: true; fields: Record<string, unknown>; provider: string; model: string; inputTokens: number | null; outputTokens: number | null }
  | { ok: false; status: number; error: string; provider: string; model: string };

async function withOpenAI(images: Photo[], timeoutMs: number): Promise<Read> {
  const result = await generateJSON(
    PROMPT,
    images.length > 1 ? `${images.length} photos of the same coffee, the card first.` : "One photo.",
    "coffee_label",
    OPENAI_SCHEMA,
    undefined,
    { timeoutMs, images },
  );
  if (!result.ok) {
    const error = result.status === 429 ? "vision model quota exhausted" : `vision model returned ${result.status}`;
    return { ok: false, status: result.status, error, provider: "openai", model: result.model };
  }
  try {
    const fields = withoutNulls(JSON.parse(result.text)) as Record<string, unknown>;
    return { ok: true, fields, provider: "openai", model: result.model, inputTokens: result.inputTokens, outputTokens: result.outputTokens };
  } catch {
    return { ok: false, status: 502, error: "unreadable model response", provider: "openai", model: result.model };
  }
}

async function withGemini(images: Photo[], options: { attemptMs: number[]; models?: string[] }): Promise<Read> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return { ok: false, status: 500, error: "GEMINI_API_KEY is not configured", provider: "gemini", model: "" };
  const result = await generate(apiKey, [
    ...images.map((image) => ({ inlineData: { mimeType: image.mime, data: image.data } })),
    { text: PROMPT },
  ], {
    temperature: 0.1,
    responseMimeType: "application/json",
    responseSchema: SCHEMA,
    // Gemini 3 replaced thinkingBudget with discrete levels; "low" is
    // the recommended setting for extraction and keeps latency in check.
    thinkingConfig: { thinkingLevel: "low" },
  }, options);
  if (!result.ok) {
    const error = result.status === 429 ? "vision model quota exhausted" : `vision model returned ${result.status}`;
    return { ok: false, status: result.status, error, provider: "gemini", model: result.model };
  }
  if (!result.text) return { ok: false, status: 502, error: "empty model response", provider: "gemini", model: result.model };
  try {
    return {
      ok: true,
      fields: JSON.parse(result.text),
      provider: "gemini",
      model: result.model,
      inputTokens: result.usage.promptTokenCount ?? null,
      outputTokens: result.usage.candidatesTokenCount ?? null,
    };
  } catch {
    return { ok: false, status: 502, error: "unreadable model response", provider: "gemini", model: result.model };
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "POST only" }, 405);
  }

  const auth = await requireUser(req);
  if (!auth.ok) return auth.response;

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  const images = photos(body);
  if (!images) {
    return json({ error: "missing image" }, 400);
  }

  const started = Date.now();
  let read: Read;
  switch (visionProvider(body)) {
    case "openai":
      read = await withOpenAI(images, OPENAI_MS);
      break;
    case "gemini":
      read = await withGemini(images, { attemptMs: ATTEMPT_MS });
      break;
    default:
      read = await withOpenAI(images, OPENAI_FIRST_MS);
      if (!read.ok) {
        console.error(`card-vision: openai failed (${read.error}), gemini takes over`);
        // Straight to the light model: the primary has been the slow one.
        read = await withGemini(images, { attemptMs: BACKUP_MS, models: [models().at(-1)!] });
      }
  }

  if (!read.ok) {
    return json({ error: read.error, provider: read.provider, model: read.model }, 502);
  }
  // The usage figures ride along at the top level, next to the fields, so
  // builds that decode the fields alone keep working and newer ones can log
  // what the call cost.
  return json({
    ...read.fields,
    provider: read.provider,
    model: read.model,
    inputTokens: read.inputTokens,
    outputTokens: read.outputTokens,
    latencyMs: Date.now() - started,
  });
});
