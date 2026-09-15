// field-extract: turns a dictated phrase, or a photo of a receipt, a bag or a
// water label, into the same shape of fields the local parsers produce.
//
// It runs second. The app has already tried its own grammar and its own OCR,
// and it sends what it could not place. Whatever comes back only ever fills
// fields that are still empty, so a wrong answer costs a tap rather than a
// correction.
//
// Secrets:  GEMINI_API_KEY (required)
// Optional: GEMINI_MODEL (defaults to gemini-3.6-flash)

const FIELD = { type: "STRING", nullable: true } as const;

const BREW_PROMPT = `\
You are reading one spoken sentence from someone logging a coffee they just \
brewed. Return only what was actually said. Never infer a value from another \
one: if the dose was not spoken, dose is null, even when the water and a \
ratio were.

Conventions:
- Masses are grams. "Eighteen in" or "eighteen of coffee" is the dose; \
  "two fifty of water" is the water; "thirty-six out" is the beverage.
- "Two forty-five" spoken as a duration is 2 min 45 s, so 165 seconds.
- Temperature is Celsius, between 60 and 100. Ignore anything outside.
- Grind stays in the words that were used: "22 clicks", "medium-fine".
- method is one of: espresso, v60, filter, aeropress, moka, frenchPress, \
  coldBrew. Nothing else.
- rating is 1 to 5, only when a score was given.
- flavors are the tasting words used, in English, each capitalised.
- notes carries the part of the sentence that is not a field, verbatim, minus \
  filler words. Empty when everything was placed.`;

const LABEL_PROMPT = `\
You are reading a photograph of one of three things: a shop receipt for \
coffee, the back of a coffee bag, or the label of a bottle of water.

For a receipt: the price paid, its currency, the bag weight if printed, and \
the shop name.
For a bag: everything printed about the coffee itself.
For a water label: the mineral analysis, in mg/L.

Return null for anything not legible on the image. Do not convert, estimate \
or complete a value from general knowledge — a wrong number here is worse \
than a missing one, because it looks like a measurement.`;

const BREW_SCHEMA = {
  type: "OBJECT",
  properties: {
    dose: { type: "NUMBER", nullable: true },
    water: { type: "NUMBER", nullable: true },
    beverage: { type: "NUMBER", nullable: true },
    seconds: { type: "INTEGER", nullable: true },
    temperature: { type: "NUMBER", nullable: true },
    grind: FIELD,
    method: FIELD,
    rating: { type: "INTEGER", nullable: true },
    flavors: { type: "ARRAY", items: { type: "STRING" } },
    notes: FIELD,
  },
  propertyOrdering: [
    "dose", "water", "beverage", "seconds", "temperature",
    "grind", "method", "rating", "flavors", "notes",
  ],
};

const LABEL_SCHEMA = {
  type: "OBJECT",
  properties: {
    kind: { type: "STRING", nullable: true },
    // Receipt
    price: { type: "NUMBER", nullable: true },
    currency: FIELD,
    shop: FIELD,
    bagWeightGrams: { type: "NUMBER", nullable: true },
    // Bag
    name: FIELD,
    roaster: FIELD,
    country: FIELD,
    region: FIELD,
    process: FIELD,
    variety: FIELD,
    roastLevel: FIELD,
    roastedOn: FIELD,
    lot: FIELD,
    tastingNotes: { type: "ARRAY", items: { type: "STRING" } },
    // Water, mg/L
    waterName: FIELD,
    calcium: { type: "NUMBER", nullable: true },
    magnesium: { type: "NUMBER", nullable: true },
    sodium: { type: "NUMBER", nullable: true },
    bicarbonate: { type: "NUMBER", nullable: true },
    tds: { type: "NUMBER", nullable: true },
  },
  propertyOrdering: [
    "kind", "price", "currency", "shop", "bagWeightGrams",
    "name", "roaster", "country", "region", "process", "variety",
    "roastLevel", "roastedOn", "lot", "tastingNotes",
    "waterName", "calcium", "magnesium", "sodium", "bicarbonate", "tds",
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

  let body: {
    kind?: "brew" | "label";
    transcript?: string;
    image?: string;
    mime?: string;
    context?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }

  const kind = body.kind ?? (body.image ? "label" : "brew");
  if (kind === "brew" && !body.transcript?.trim()) {
    return json({ error: "missing transcript" }, 400);
  }
  if (kind === "label" && !body.image) {
    return json({ error: "missing image" }, 400);
  }

  const parts: unknown[] = [];
  if (body.image) {
    parts.push({
      inlineData: { mimeType: body.mime ?? "image/jpeg", data: body.image },
    });
  }
  parts.push({ text: kind === "brew" ? BREW_PROMPT : LABEL_PROMPT });
  // What the app already knows, so the model does not contradict it.
  if (body.context) parts.push({ text: `Context: ${body.context}` });
  if (body.transcript) parts.push({ text: `Sentence: ${body.transcript}` });

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
          temperature: 0,
          responseMimeType: "application/json",
          responseSchema: kind === "brew" ? BREW_SCHEMA : LABEL_SCHEMA,
          thinkingConfig: { thinkingLevel: "low" },
        },
      }),
    },
  );

  if (!response.ok) {
    const detail = await response.text();
    console.error(`gemini error ${response.status}: ${detail}`);
    return json({
      error: response.status === 429
        ? "model quota exhausted"
        : `model returned ${response.status}`,
    }, 502);
  }

  const data = await response.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) return json({ error: "empty model response" }, 502);

  // The usage figures ride along so the app can log what the call cost
  // without a second round trip.
  const usage = data?.usageMetadata ?? {};
  return json({
    fields: JSON.parse(text),
    model,
    inputTokens: usage.promptTokenCount ?? null,
    outputTokens: usage.candidatesTokenCount ?? null,
    latencyMs: Date.now() - started,
  });
});
