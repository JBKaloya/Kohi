// deno test supabase/functions/_shared/

import { assertEquals } from "jsr:@std/assert@1";
import { MOST_PHOTOS, OPENAI_SCHEMA, photos, PROMPT, toOpenAISchema, visionProvider, withoutNulls } from "./card-vision.ts";

Deno.test("a body carries one photo or several, the card first, four at most", () => {
  assertEquals(photos({ image: "AAA", mime: "image/png" }), [{ data: "AAA", mime: "image/png" }]);
  assertEquals(photos({ image: "AAA" }), [{ data: "AAA", mime: "image/jpeg" }]);
  const five = Array.from({ length: 5 }, (_, i) => ({ image: `P${i}` }));
  assertEquals(photos({ images: five })?.map((p) => p.data), ["P0", "P1", "P2", "P3"]);
  assertEquals(photos({ images: five })?.length, MOST_PHOTOS);
  assertEquals(photos({ images: [{ image: "" }, { mime: "image/jpeg" }, { image: "B" }] }), [{ data: "B", mime: "image/jpeg" }]);
  assertEquals(photos({}), null);
  assertEquals(photos(null), null);
});

Deno.test("OpenAI reads first unless one provider is asked for", () => {
  assertEquals(visionProvider({ provider: "openai" }), "openai");
  assertEquals(visionProvider({ provider: "gemini" }), "gemini");
  assertEquals(visionProvider({}), "openai-first");
  assertEquals(visionProvider({ image: "AAA" }), "openai-first");
});

Deno.test("Gemini's schema turns into OpenAI's strict one", () => {
  assertEquals(
    toOpenAISchema({
      type: "OBJECT",
      properties: {
        isCoffeeLabel: { type: "BOOLEAN" },
        name: { type: "STRING" },
        tastingNotes: { type: "ARRAY", items: { type: "STRING" } },
        recipe: { type: "OBJECT", properties: { seconds: { type: "INTEGER" } } },
      },
      required: ["isCoffeeLabel"],
      propertyOrdering: ["isCoffeeLabel", "name"],
    }),
    {
      type: "object",
      properties: {
        isCoffeeLabel: { type: "boolean" },
        name: { type: ["string", "null"] },
        tastingNotes: { type: ["array", "null"], items: { type: "string" } },
        recipe: {
          type: ["object", "null"],
          properties: { seconds: { type: ["integer", "null"] } },
          required: ["seconds"],
          additionalProperties: false,
        },
      },
      required: ["isCoffeeLabel", "name", "tastingNotes", "recipe"],
      additionalProperties: false,
    },
  );
  // Every property of the real schema is required, as strict mode demands.
  const schema = OPENAI_SCHEMA as { properties: Record<string, unknown>; required: string[] };
  assertEquals(schema.required, Object.keys(schema.properties));
});

Deno.test("OpenAI's nulls are dropped, so the app reads them as absent", () => {
  assertEquals(
    withoutNulls({ name: "Majirane", process: null, tastingNotes: ["Plum"], recipe: null, original: { name: null } }),
    { name: "Majirane", tastingNotes: ["Plum"], original: {} },
  );
});

Deno.test("the prompt reads several sides and keeps headings out of the values", () => {
  assertEquals(PROMPT.includes("Several photos are sides of one coffee"), true);
  assertEquals(PROMPT.includes("Headings are not values"), true);
});
