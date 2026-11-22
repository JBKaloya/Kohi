import { assertEquals } from "jsr:@std/assert@1";
import { attempts } from "./gemini.ts";
import { ATTEMPT_MS, cited, input, OPENAI_SCHEMA, PROMPT, provider, readAnswer, SCHEMA } from "./ask.ts";

Deno.test("ask gives the primary 8 s and the fallback 30 s", () => {
  assertEquals(
    attempts(["gemini-3.8-flash", "gemini-3.5-flash-lite"], ATTEMPT_MS),
    [
      { model: "gemini-3.8-flash", ms: 8_000 },
      { model: "gemini-3.5-flash-lite", ms: 30_000 },
    ],
  );
});

Deno.test("an answer is read only when the model returned a JSON object", () => {
  assertEquals(readAnswer('{"answer":"Grind finer.","citations":[]}'), {
    answer: "Grind finer.",
    citations: [],
  });
  assertEquals(readAnswer(undefined), null);
  assertEquals(readAnswer(""), null);
  assertEquals(readAnswer('{"answer":"Grind fin'), null);
  assertEquals(readAnswer("[1, 2]"), null);
  assertEquals(readAnswer("null"), null);
});

Deno.test("the model reads the sources, then what is on screen, then the question", () => {
  const sources = [{ id: "grind-1", title: "Grind" }];
  assertEquals(input(sources, undefined, "Why sour?"), [
    'Sources:\n[{"id":"grind-1","title":"Grind"}]',
    "Question: Why sour?",
  ]);
  assertEquals(input([], "Comparing 2 coffees", "Which is brighter?"), [
    "Sources:\n[]",
    "What they are looking at (not a source):\nComparing 2 coffees",
    "Question: Which is brighter?",
  ]);
});

Deno.test("OpenAI's schema asks for every field Gemini's does, and nothing else", () => {
  assertEquals(OPENAI_SCHEMA.required, Object.keys(SCHEMA.properties));
  assertEquals(Object.keys(OPENAI_SCHEMA.properties), Object.keys(SCHEMA.properties));
  assertEquals(OPENAI_SCHEMA.additionalProperties, false);
});

Deno.test("OpenAI answers first unless one provider is asked for", () => {
  assertEquals(provider({ question: "x" }), "openai-first");
  assertEquals(provider({ question: "x", provider: "gemini" }), "gemini");
  assertEquals(provider({ question: "x", provider: "openai" }), "openai");
});

Deno.test("only citations found in the sources are kept, and covered needs one", () => {
  const sources = [{ id: "f4-frost-roast-tds-2020", title: "Roast" }, { id: "g7", title: "Rules" }];
  // OpenAI's answer of 22 Nov: a made-up id, said to be covered.
  assertEquals(cited({ isCovered: true, citations: ["f4-roast-tds-2020"] }, sources), {
    citations: [],
    sources: [],
    isCovered: false,
  });
  assertEquals(cited({ isCovered: true, citations: ["g7", "nope", 3] }, sources), {
    citations: ["g7"],
    sources: [{ id: "g7", title: "Rules" }],
    isCovered: true,
  });
  assertEquals(cited({ isCovered: false, citations: ["g7"] }, sources).isCovered, false);
  assertEquals(cited({ isCovered: true }, sources).isCovered, false);
});

Deno.test("the prompt counts processing as coffee and keeps ids out of the text", () => {
  assertEquals(PROMPT.includes("thermal shock"), true);
  assertEquals(PROMPT.includes("never write a source id"), true);
});
