// ask: answers a coffee question from a curated knowledge base, with the
// source named in the answer.
//
// The base is the annexes of the PRD, stored in `public.knowledge` and served
// here as the only material the model is allowed to draw on. That is the whole
// design: an answer that cannot be traced to an entry is not returned, because
// a confident sentence about extraction that nobody wrote is exactly the kind
// of thing this app should not produce.
//
// Secrets:  GEMINI_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Optional: GEMINI_MODEL (defaults to gemini-3.6-flash)

import { createClient } from "jsr:@supabase/supabase-js@2";

const PROMPT = `\
You answer coffee questions for Kohi.

You are given a curated knowledge base (sources). Use it when it covers the \
question, and cite those sources by id.

Rules, in order of importance:
1. If the sources cover the question, answer from them and set isCovered true. \
   Cite every source you used by id.
2. If the sources do not cover it, but the question is about coffee (brewing, \
   grind, water, roast, taste, equipment, recipes), answer from general coffee \
   knowledge. Set isCovered false and tag "general". Do not invent citations. \
   Never say "the base does not cover this".
3. If the question is not about coffee, refuse in one short sentence. Set \
   isCovered false and tag "off-topic".
4. When sources disagree, say they disagree and give both readings.
5. Distinguish what is measured from what is common practice.
6. Plain English, no marketing adjectives, no exclamation marks. Two short \
   paragraphs at most.`;

const SCHEMA = {
  type: "OBJECT",
  properties: {
    answer: { type: "STRING" },
    isCovered: { type: "BOOLEAN" },
    citations: { type: "ARRAY", items: { type: "STRING" } },
    tag: { type: "STRING" },
  },
  required: ["answer", "isCovered"],
  propertyOrdering: ["answer", "isCovered", "citations", "tag"],
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
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!apiKey || !supabaseUrl || !serviceKey) {
    return json({ error: "function is not configured" }, 500);
  }

  let body: { question?: string; topic?: string };
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

  const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.6-flash";
  const started = Date.now();
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
      body: JSON.stringify({
        contents: [{
          parts: [
            { text: PROMPT },
            { text: `Sources:\n${JSON.stringify(sources)}` },
            { text: `Question: ${question}` },
          ],
        }],
        generationConfig: {
          temperature: 0.1,
          responseMimeType: "application/json",
          responseSchema: SCHEMA,
          thinkingConfig: { thinkingLevel: "low" },
        },
      }),
    },
  );

  if (!response.ok) {
    const detail = await response.text();
    console.error(`gemini error ${response.status}: ${detail}`);
    return json({ error: `model returned ${response.status}` }, 502);
  }

  const data = await response.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) return json({ error: "empty model response" }, 502);

  const parsed = JSON.parse(text);
  const usage = data?.usageMetadata ?? {};
  return json({
    ...parsed,
    // The titles, so the app can name the sources without a second query.
    sources: (parsed.citations ?? [])
      .map((id: string) => sources.find((s) => s.id === id))
      .filter(Boolean)
      .map((s: { id: string; title: string; source: string }) => ({
        id: s.id,
        title: s.title,
        source: s.source,
      })),
    model,
    inputTokens: usage.promptTokenCount ?? null,
    outputTokens: usage.candidatesTokenCount ?? null,
    latencyMs: Date.now() - started,
  });
});
