// ask: answers a coffee question from a curated knowledge base, with the
// source named in the answer.
//
// The base is the annexes of the PRD, stored in `public.knowledge` and served
// here as the only material the model is allowed to draw on. That is the whole
// design: an answer that cannot be traced to an entry is not returned, because
// a confident sentence about extraction that nobody wrote is exactly the kind
// of thing this app should not produce.
//
// OpenAI answers first, and Gemini's light model takes over when it fails or
// is slow (_shared/provider.ts). A body can ask for `"provider": "openai"` or
// `"gemini"` alone, for the beta's model comparisons.
//
// Secrets:  OPENAI_API_KEY, GEMINI_API_KEY, SUPABASE_URL,
//           SUPABASE_SERVICE_ROLE_KEY
// Optional: OPENAI_TEXT_MODEL, OPENAI_REASONING (see _shared/openai.ts),
//           GEMINI_MODEL, GEMINI_MODEL_FALLBACK (see _shared/gemini.ts)

import { createClient } from "jsr:@supabase/supabase-js@2";
import { generate, models } from "../_shared/gemini.ts";
import { generateJSON } from "../_shared/openai.ts";
import { requireUser } from "../_shared/auth.ts";
import {
  ATTEMPT_MS,
  BACKUP_MS,
  cited,
  input,
  OPENAI_FIRST_MS,
  OPENAI_MS,
  OPENAI_SCHEMA,
  PROMPT,
  provider,
  readAnswer,
  SCHEMA,
} from "../_shared/ask.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const auth = await requireUser(req);
  if (!auth.ok) return auth.response;

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return json({ error: "function is not configured" }, 500);
  }

  let body: { question?: string; topic?: string; context?: string; provider?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  const question = body.question?.trim();
  if (!question) return json({ error: "missing question" }, 400);

  const supabase = createClient(supabaseUrl, serviceKey);
  // Full-text over the base. Small enough that a keyword search beats
  // embeddings on both latency and predictability; revisit when it is not.
  let query = supabase
    .from("knowledge")
    .select("id, title, body, source, topic")
    .textSearch("search", question, { type: "websearch", config: "english" })
    .limit(8);
  if (body.topic) query = query.eq("topic", body.topic);

  let { data: sources, error } = await query;
  if (error) {
    console.error(`knowledge search failed: ${error.message}`);
    return json({ error: "knowledge base unavailable" }, 502);
  }
  // A question phrased unlike the base still deserves the base: fall back to
  // the topic, or to the most recent entries, rather than answering blind.
  if (!sources?.length) {
    const fallback = await supabase
      .from("knowledge")
      .select("id, title, body, source, topic")
      .limit(8);
    sources = fallback.data ?? [];
  }
  if (!sources.length) {
    // Empty table: still answer coffee from general knowledge.
    sources = [];
  }

  // What the person is looking at when they ask (a comparison, say). Context
  // for the question, never a source to cite.
  const context = body.context?.trim().slice(0, 4000);

  const parts = input(sources, context, question);
  const started = Date.now();
  let written: Written;
  switch (provider(body)) {
    case "openai":
      written = await withOpenAI(parts, OPENAI_MS);
      break;
    case "gemini":
      written = await withGemini(parts, { attemptMs: ATTEMPT_MS });
      break;
    default:
      written = await withOpenAI(parts, OPENAI_FIRST_MS);
      if (!written.ok) {
        console.error(`ask: openai failed (status ${written.status}), gemini takes over`);
        // Straight to the light model: the primary has been the slow one.
        written = await withGemini(parts, { attemptMs: BACKUP_MS, models: [models().at(-1)!] });
      }
  }

  if (!written.ok) {
    return json(
      { error: written.error, provider: written.provider, model: written.model },
      written.status === 429 ? 429 : 502,
    );
  }
  const { parsed } = written;
  const found = cited(parsed, sources);
  return json({
    ...parsed,
    citations: found.citations,
    isCovered: found.isCovered,
    // A covered answer that lost its citations reads as general knowledge.
    tag: found.isCovered ? null : (parsed.tag ?? "general"),
    // The titles, so the app can name the sources without a second query.
    sources: found.sources.map((s) => ({ id: s.id, title: s.title, source: s.source })),
    provider: written.provider,
    model: written.model,
    inputTokens: written.inputTokens,
    outputTokens: written.outputTokens,
    latencyMs: Date.now() - started,
  });
});

type Written =
  | {
    ok: true;
    parsed: Record<string, unknown>;
    provider: string;
    model: string;
    inputTokens: number | null;
    outputTokens: number | null;
  }
  | { ok: false; status: number; error: string; provider: string; model: string };

async function withOpenAI(parts: string[], timeoutMs: number): Promise<Written> {
  const result = await generateJSON(PROMPT, parts.join("\n\n"), "answer", OPENAI_SCHEMA, undefined, { timeoutMs });
  if (!result.ok) {
    return { ok: false, status: result.status, error: `model returned ${result.status}`, provider: "openai", model: result.model };
  }
  const parsed = readAnswer(result.text);
  if (!parsed) return { ok: false, status: 502, error: "empty model response", provider: "openai", model: result.model };
  return {
    ok: true,
    parsed,
    provider: "openai",
    model: result.model,
    inputTokens: result.inputTokens,
    outputTokens: result.outputTokens,
  };
}

async function withGemini(parts: string[], options: { attemptMs: number[]; models?: string[] }): Promise<Written> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return { ok: false, status: 500, error: "function is not configured", provider: "gemini", model: "" };
  const result = await generate(apiKey, [{ text: PROMPT }, ...parts.map((text) => ({ text }))], {
    temperature: 0.1,
    responseMimeType: "application/json",
    responseSchema: SCHEMA,
    thinkingConfig: { thinkingLevel: "low" },
  }, options);
  if (!result.ok) {
    return { ok: false, status: result.status, error: `model returned ${result.status}`, provider: "gemini", model: result.model };
  }
  const parsed = readAnswer(result.text);
  if (!parsed) return { ok: false, status: 502, error: "empty model response", provider: "gemini", model: result.model };
  return {
    ok: true,
    parsed,
    provider: "gemini",
    model: result.model,
    inputTokens: result.usage.promptTokenCount ?? null,
    outputTokens: result.usage.candidatesTokenCount ?? null,
  };
}
