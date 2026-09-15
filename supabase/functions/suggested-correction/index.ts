// suggested-correction: pick three moves from an admissible set the app already
// computed. The model ranks and explains; it cannot invent a variable.

const PROMPT = `\
You rank three brew corrections. You are given the only moves you may use \
(allowed). Pick exactly three, rank them 1 (gentlest) to 3 (strongest), and \
explain each in one short clause. You must not invent a change that is not \
in the allowed list. One variable per move.

Return JSON: reading (one sentence of what the cup said), target (what to \
aim for), and moves: [{rank, variable, change, why, effect}]. change must \
match an allowed change. Plain English, no marketing.`;

const SCHEMA = {
  type: "OBJECT",
  properties: {
    reading: { type: "STRING" },
    target: { type: "STRING" },
    moves: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          rank: { type: "INTEGER" },
          variable: { type: "STRING" },
          change: { type: "STRING" },
          why: { type: "STRING" },
          effect: { type: "OBJECT" },
        },
        required: ["rank", "variable", "change", "why"],
      },
    },
  },
  required: ["reading", "target", "moves"],
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
  if (!apiKey) return json({ error: "GEMINI_API_KEY is not configured" }, 500);

  let body: { readingHint?: string; comment?: string; allowed?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (!body.allowed) return json({ error: "missing allowed" }, 400);

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
            { text: `Allowed moves: ${JSON.stringify(body.allowed)}` },
            { text: `Reading hint: ${body.readingHint ?? ""}` },
            { text: `Comment: ${body.comment ?? ""}` },
          ],
        }],
        generationConfig: {
          temperature: 0.2,
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
    model,
    inputTokens: usage.promptTokenCount ?? null,
    outputTokens: usage.candidatesTokenCount ?? null,
    latencyMs: Date.now() - started,
  });
});
