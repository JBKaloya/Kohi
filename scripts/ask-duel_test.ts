import { assertEquals } from "jsr:@std/assert@1";
import { checks, QUESTIONS } from "./ask-duel.ts";

const coffee = { text: "Why sour?", expect: "coffee" as const };
const offTopic = { text: "Ramen?", expect: "off-topic" as const };
const fromCompare = { text: "Why sweeter?", context: "Comparing 2 coffees", expect: "coffee" as const };

Deno.test("a covered answer citing its sources passes", () => {
  assertEquals(
    checks(coffee, {
      answer: "Under-extraction.\n\nGrind finer.",
      isCovered: true,
      citations: ["a"],
      sources: [{ id: "a", title: "A" }],
      tag: null,
    }),
    [],
  );
});

Deno.test("the checks flag a refusal missed, an invented citation and a long answer", () => {
  assertEquals(checks(offTopic, { answer: "Try Ichiran.", isCovered: false, citations: [], tag: "general" }), [
    "off-topic: answered instead of refusing",
  ]);
  assertEquals(
    checks(coffee, { answer: "One.\n\nTwo.\n\nThree!", isCovered: true, citations: ["a", "zzz"], sources: [{ id: "a", title: "A" }] }),
    ["cites 1 id(s) not in the sources", "3 paragraphs, the prompt allows two", "exclamation mark"],
  );
  assertEquals(checks(coffee, { answer: "No.", isCovered: false, tag: "off-topic" }), ["refused a coffee question"]);
  assertEquals(checks(fromCompare, { answer: "The first is sweeter.", isCovered: false, tag: "general" }), [
    "asked from a comparison, names no coffee by its number",
  ]);
});

Deno.test("the checks flag talk about the sources and ids left in the text", () => {
  assertEquals(checks(coffee, { answer: "The provided sources do not discuss this.", isCovered: false, tag: "general" }), [
    "talks about the sources",
  ]);
  assertEquals(checks(coffee, { answer: "Hotter helps [f3-batali-temperature-2020].", isCovered: true, citations: ["a"], sources: [{ id: "a", title: "A" }] }), [
    "source id in the text",
  ]);
  assertEquals(checks(coffee, { answer: "Darker reads heavier.【f4-roast-tds-2020】", isCovered: false, tag: "general" }), [
    "source id in the text",
  ]);
});

Deno.test("the question set has one refusal and two asked from Compare", () => {
  assertEquals(QUESTIONS.filter((q) => q.expect === "off-topic").length, 1);
  assertEquals(QUESTIONS.filter((q) => q.context).length, 2);
});
