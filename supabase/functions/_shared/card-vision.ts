// card-vision, the rules without the server: what the vision model is told,
// the answer's shape for Gemini and for OpenAI, which photos a body carries,
// and how the answer is cleaned. Kept apart from index.ts so `deno test` can
// load it without starting Deno.serve.

export const PROMPT = `You are reading one or more photos of the same specialty coffee: a bag label, a coffee
info card, or several sides or pages of them. Extract the metadata printed on them and
return JSON matching the response schema.

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
- Several photos are sides of one coffee: combine what they print into one answer. When
  two sides print the same field differently, keep the clearest, most complete print.
- Headings are not values. On a card that prints a row of headings ("MASL  PRODUCER
  PROCESS") with their values underneath, each value belongs to the heading directly
  above it. "Taste notes", "Brew notes", "Brew rating" are headings.
- A logo or a word in large type is not the coffee name unless it names the coffee.
- If no photo shows a coffee label, bag, or card, set isCoffeeLabel to false and omit everything else.`;

export const FIELD = { type: "STRING" };

// propertyOrdering keeps constrained decoding on rails; without it the model
// occasionally leaks property names into string values.
export const SCHEMA = {
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

/// Gemini's response schema in OpenAI's strict dialect: lower-case types,
/// every property required but nullable (an absent field comes back null, then
/// `withoutNulls` drops it), no extra properties, no propertyOrdering.
export function toOpenAISchema(schema: Record<string, unknown>, nullable = false): Record<string, unknown> {
  const type = String(schema.type ?? "").toLowerCase();
  const typed = (t: string) => (nullable ? [t, "null"] : t);
  if (type === "object") {
    const properties = (schema.properties ?? {}) as Record<string, Record<string, unknown>>;
    const required = (schema.required ?? []) as string[];
    return {
      type: typed("object"),
      properties: Object.fromEntries(
        Object.entries(properties).map(([key, value]) => [key, toOpenAISchema(value, !required.includes(key))]),
      ),
      required: Object.keys(properties),
      additionalProperties: false,
    };
  }
  if (type === "array") {
    return { type: typed("array"), items: toOpenAISchema(schema.items as Record<string, unknown>) };
  }
  return { type: typed(type) };
}

export const OPENAI_SCHEMA = toOpenAISchema(SCHEMA);

/// OpenAI answers every field, null when the photo does not print it; the app
/// reads an absent field the way Gemini leaves it out.
export function withoutNulls(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(withoutNulls);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).filter(([, v]) => v !== null).map(([k, v]) => [k, withoutNulls(v)]),
    );
  }
  return value;
}

export type Photo = { data: string; mime: string };

/// The most photos one call reads: the card and three more sides.
export const MOST_PHOTOS = 4;

/// The photos a body carries, the card first: `images` (a list of
/// `{ image, mime }`), or the single `image` older builds send. Null when
/// there is none.
export function photos(body: unknown): Photo[] | null {
  const b = body as { image?: unknown; mime?: unknown; images?: unknown } | null;
  const list = Array.isArray(b?.images) ? b.images : b?.image ? [{ image: b.image, mime: b.mime }] : [];
  const found = list.flatMap((entry: { image?: unknown; mime?: unknown }) =>
    typeof entry?.image === "string" && entry.image
      ? [{ data: entry.image, mime: typeof entry.mime === "string" ? entry.mime : "image/jpeg" }]
      : []
  );
  return found.length ? found.slice(0, MOST_PHOTOS) : null;
}

/// Who reads: OpenAI first, then Gemini's light model (_shared/provider.ts),
/// unless the body asks for one alone, which the scan benchmark does. On 22
/// coffees (22 Nov 2026) with every side sent, both read 93–94 % of fields
/// right, but Gemini failed 15 of 33 calls and OpenAI none.
export { type Provider, provider as visionProvider } from "./provider.ts";

/// A person is waiting on the scan. OpenAI gets 15 s, about four times its
/// median with every side; the light Gemini model then gets 15 s more.
export const OPENAI_FIRST_MS = 15_000;
export const BACKUP_MS = [15_000];

/// A provider asked for alone: Gemini's primary gets 8 s, not 25 (on 21–22
/// Nov 2026 gemini-3.8-flash answered none of our calls), OpenAI 30 s.
export const ATTEMPT_MS = [8_000, 30_000];
export const OPENAI_MS = 30_000;
