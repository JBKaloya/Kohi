// recipe-adapt: a variant of a recipe the rules already produced.
//
// It is never the answer on its own. The app has computed a recipe from the
// deterministic rules and shows it; this returns a second one underneath,
// labelled as a variant, with a sentence saying what it changed and why. If
// this function is off, slow, or wrong, the screen is unchanged apart from a
// missing row.
//
// The prompt is written to constrain rather than to inspire: the model gets
// the rules it must not contradict, and is asked for one change with a reason.
//
// Secrets:  GEMINI_API_KEY (required)
// Optional: GEMINI_MODEL (defaults to gemini-3.6-flash)

const PROMPT = `\
You are suggesting one variant of a filter or espresso recipe that a rules \
engine has already produced. The rules are not yours to overrule; they encode \
published practice:

- Temperature follows the roast: lighter roasts hotter, within 88–100 °C.
- Filter ratios stay between 1:14 and 1:18. Espresso ratios between 1:1.5 \
  and 1:3.
- One variable at a time. A variant that moves the grind AND the ratio AND \
  the temperature teaches nothing.
- Grind is described in the same words the input used. Never invent a click \
  count for a grinder you were not told about.

Given the recipe and what is known about the coffee, propose ONE variant. \
Say what you changed, and why, in a single sentence of plain English with no \
marketing adjectives. If the recipe is already the sensible thing to do, say \
so by returning null for the variant — an unnecessary suggestion is worse \
than none, because it teaches the reader to ignore this row.

Never claim a result. "This will taste sweeter" is a promise you cannot keep; \
"a longer ratio usually reads as sweeter and lighter" is a description of \
practice.`;

const SCHEMA = {
  type: "OBJECT",
  properties: {
    hasVariant: { type: "BOOLEAN" },
    dose: { type: "NUMBER", nullable: true },
    water: { type: "NUMBER", nullable: true },
    beverage: { type: "NUMBER", nullable: true },
    temperature: { type: "NUMBER", nullable: true },
    seconds: { type: "INTEGER", nullable: true },
    grindLabel: { type: "STRING", nullable: true },
    changed: { type: "STRING", nullable: true },
    why: { type: "STRING", nullable: true },
  },
  required: ["hasVariant"],
  propertyOrdering: [
    "hasVariant", "dose", "water", "beverage", "temperature", "seconds",
    "grindLabel", "changed", "why",
  ],
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

  let body: { recipe?: unknown; coffee?: unknown; history?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (!body.recipe) return json({ error: "missing recipe" }, 400);

  const parts = [
    { text: PROMPT },
    { text: `Recipe from the rules: ${JSON.stringify(body.recipe)}` },
    { text: `Coffee: ${JSON.stringify(body.coffee ?? {})}` },
  ];
  // Past brews of this coffee, when there are any: a variant that repeats
  // something already tried and disliked is worse than useless.
  if (body.history) {
    parts.push({ text: `Already brewed: ${JSON.stringify(body.history)}` });
  }

  const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.6-flash";
  const started = Date.now();
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
      body: JSON.stringify({
        contents: [{ parts }],
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

  const usage = data?.usageMetadata ?? {};
  return json({
    variant: JSON.parse(text),
    model,
    inputTokens: usage.promptTokenCount ?? null,
    outputTokens: usage.candidatesTokenCount ?? null,
    latencyMs: Date.now() - started,
  });
});
