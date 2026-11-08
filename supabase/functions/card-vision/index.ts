// card-vision: reads a coffee card photo with a vision LLM and returns the
// structured fields the local parser could not extract. The model key stays
// server-side; the app only ever sees the JSON result.
//
// Secrets:   GEMINI_API_KEY  (required)
// Optional:  GEMINI_MODEL    (defaults to gemini-3.6-flash)

const PROMPT = `You are reading a photo of a specialty coffee bag label or a coffee info card.
Extract the metadata printed on it and return JSON matching the response schema.

Rules:
- All field values must be in English. If the card is written in another language
  (Japanese, Chinese, French, ...), translate the values to English and put the
  exact original text into the "original" object under the same key.
- "name" is the coffee name, not the roaster name and not the lot number.
- "tastingNotes" are the flavour descriptors, each 1-3 words ("Golden Raisin", "Yuzu").
- "roastLevel" is one of light, mediumLight, medium, mediumDark, dark. Only when
  the bag states a roast level in words. Do not derive it from an Agtron number,
  from "espresso roast", or from "omni": those say what the roast is for, not how
  dark it is.
- "roastedOn" is the roast date as YYYY-MM-DD. Never a best-before date
  (賞味期限, "best before"): if only a best-before date is printed, omit this.
- "harvest" is the crop year as printed ("2025/26", "Nov 2025").
- "lot" is the lot or batch identifier as printed.
- "cuppingScore" is the printed cupping score, 55-100. Not a percentage.
- "price" is the number only, with "currency" as a three-letter ISO code.
- "bagWeightGrams" is the net weight converted to grams (12 oz -> 340).
- "isDecaf" is true only when the bag says decaffeinated, or names a decaf
  process (Swiss Water, sugarcane EA, CO2).
- "recipe" only when brewing parameters are printed on the card: dose in grams,
  water in grams or ml, total brew time in seconds, water temperature in Celsius,
  grind setting as printed, method as one of espresso, v60, filter, aeropress,
  moka, frenchPress, coldBrew.
- "detectedLanguage" is the two-letter code of the card's main language ("en", "ja", "zh", "fr").
- Omit any field that is not printed on the card. Never guess or invent values.
- If the photo is not a coffee label, bag, or card, set isCoffeeLabel to false and omit everything else.`;

const FIELD = { type: "STRING" };

// propertyOrdering keeps constrained decoding on rails; without it the model
// occasionally leaks property names into string values.
const SCHEMA = {
  type: "OBJECT",
  properties: {
    isCoffeeLabel: { type: "BOOLEAN" },
    detectedLanguage: FIELD,
    name: FIELD,
    roaster: FIELD,
    country: FIELD,
    region: FIELD,
    producer: FIELD,
    altitude: FIELD,
    variety: FIELD,
    process: FIELD,
    tastingNotes: { type: "ARRAY", items: FIELD },
    roastLevel: FIELD,
    roastedOn: FIELD,
    harvest: FIELD,
    lot: FIELD,
    cuppingScore: { type: "NUMBER" },
    price: { type: "NUMBER" },
    currency: FIELD,
    bagWeightGrams: { type: "NUMBER" },
    isDecaf: { type: "BOOLEAN" },
    recipe: {
      type: "OBJECT",
      properties: {
        doseGrams: { type: "NUMBER" },
        waterGrams: { type: "NUMBER" },
        seconds: { type: "INTEGER" },
        temperatureCelsius: { type: "NUMBER" },
        grind: FIELD,
        method: FIELD,
      },
      propertyOrdering: [
        "doseGrams", "waterGrams", "seconds", "temperatureCelsius",
        "grind", "method",
      ],
    },
    original: {
      type: "OBJECT",
      properties: {
        name: FIELD,
        roaster: FIELD,
        country: FIELD,
        region: FIELD,
        producer: FIELD,
        altitude: FIELD,
        variety: FIELD,
        process: FIELD,
        tastingNotes: { type: "ARRAY", items: FIELD },
      },
      propertyOrdering: [
        "name", "roaster", "country", "region", "producer",
        "altitude", "variety", "process", "tastingNotes",
      ],
    },
  },
  required: ["isCoffeeLabel"],
  propertyOrdering: [
    "isCoffeeLabel", "detectedLanguage", "name", "roaster", "country",
    "region", "producer", "altitude", "variety", "process", "tastingNotes",
    "roastLevel", "roastedOn", "harvest", "lot", "cuppingScore",
    "price", "currency", "bagWeightGrams", "isDecaf",
    "recipe", "original",
  ],
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "POST only" }, 405);
  }

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    return json({ error: "GEMINI_API_KEY is not configured" }, 500);
  }

  let image: string | undefined;
  let mime: string | undefined;
  try {
    ({ image, mime } = await req.json());
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (!image) {
    return json({ error: "missing image" }, 400);
  }

  const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.6-flash";
  const started = Date.now();
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: JSON.stringify({
        contents: [{
          parts: [
            { inlineData: { mimeType: mime ?? "image/jpeg", data: image } },
            { text: PROMPT },
          ],
        }],
        generationConfig: {
          temperature: 0.1,
          responseMimeType: "application/json",
          responseSchema: SCHEMA,
          // Gemini 3 replaced thinkingBudget with discrete levels; "low" is
          // the recommended setting for extraction and keeps latency in check.
          thinkingConfig: { thinkingLevel: "low" },
        },
      }),
    },
  );

  if (!response.ok) {
    const detail = await response.text();
    console.error(`gemini error ${response.status}: ${detail}`);
    // The two failures worth telling apart in the app log: out of credit, and
    // everything else.
    const reason = response.status === 429
      ? "vision model quota exhausted"
      : `vision model returned ${response.status}`;
    return json({ error: reason }, 502);
  }

  const data = await response.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) {
    console.error("gemini returned no candidate text");
    return json({ error: "empty model response" }, 502);
  }

  // The usage figures ride along at the top level, next to the fields, so
  // builds that decode the fields alone keep working and newer ones can log
  // what the call cost.
  let fields: Record<string, unknown>;
  try {
    fields = JSON.parse(text);
  } catch {
    console.error("gemini returned text that is not JSON");
    return json({ error: "unreadable model response" }, 502);
  }
  const usage = data?.usageMetadata ?? {};
  return json({
    ...fields,
    model,
    inputTokens: usage.promptTokenCount ?? null,
    outputTokens: usage.candidatesTokenCount ?? null,
    latencyMs: Date.now() - started,
  });
});
