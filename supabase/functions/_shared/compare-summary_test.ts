// deno test supabase/functions/_shared/

import { assertEquals } from "jsr:@std/assert@1";
import {
  ATTEMPT_MS,
  AXES,
  BACKUP_MS,
  OPENAI_FIRST_MS,
  describe,
  differences,
  provider,
  readSummary,
  type Series,
  validSeries,
} from "./compare-summary.ts";
import { attempts } from "./gemini.ts";

const one = (number: number) => ({ number, title: `Coffee ${number}`, axes: { acidity: number } });

Deno.test("fewer than two series cannot be compared", () => {
  assertEquals(validSeries({ series: [one(1)] }), null);
  assertEquals(validSeries({ series: [] }), null);
  assertEquals(validSeries({}), null);
  assertEquals(validSeries(null), null);
  assertEquals(validSeries({ series: "two" }), null);
});

Deno.test("two or three series pass, a fourth is cut", () => {
  assertEquals(validSeries({ series: [one(1), one(2)] })?.length, 2);
  assertEquals(validSeries({ series: [one(1), one(2), one(3), one(4)] })?.map((s) => s.number), [1, 2, 3]);
});

Deno.test("the summary is read trimmed, and an empty or broken one is refused", () => {
  assertEquals(readSummary('{"summary":"  No. 1 is brighter.  "}'), "No. 1 is brighter.");
  assertEquals(readSummary('{"summary":"   "}'), null);
  assertEquals(readSummary('{"other":"x"}'), null);
  assertEquals(readSummary("not json"), null);
  assertEquals(readSummary(undefined), null);
});

Deno.test("each model gets its time, the last time repeating", () => {
  assertEquals(attempts(["a", "b"]), [{ model: "a", ms: 25_000 }, { model: "b", ms: 90_000 }]);
  assertEquals(attempts(["a", "b"], ATTEMPT_MS), [{ model: "a", ms: 6_000 }, { model: "b", ms: 20_000 }]);
  assertEquals(attempts(["a", "b", "c"], [5_000]), [
    { model: "a", ms: 5_000 },
    { model: "b", ms: 5_000 },
    { model: "c", ms: 5_000 },
  ]);
  assertEquals(attempts(["a"], []), [{ model: "a", ms: 25_000 }]);
});

// Cases taken from real tastings, where flash-lite got them wrong
// (.private/compare-real-2026-11-22-07-55.md).
const coffee = (number: number, a: number[], flavors: string[] = [], rating: number | null = 3) => ({
  number,
  title: `Coffee ${number}`,
  axes: Object.fromEntries(AXES.map((axis, i) => [axis, a[i]])),
  flavors,
  rating,
});

Deno.test("a close pair says it is close, and the slight gap keeps its direction", () => {
  // Onibus Guatemala and Gakuyuini: the model said No. 2 was sweeter.
  const pair = [coffee(1, [6, 5, 7, 4, 5, 4, 4]), coffee(2, [6, 5, 5, 4, 6, 5, 3])];
  const reading = differences(pair);
  assertEquals(reading.close, false);
  assertEquals(reading.differences.map((d) => d.kind === "axis" && d.axis), ["sweetness"]);
  assertEquals(describe(pair).includes("- sweetness: No. 1 higher than No. 2"), true);

  // ASTRID MEDINA and Nigusse Gemeda: no axis apart by two, the rating is.
  const close = [coffee(1, [6, 7, 5, 4, 7, 5, 4], [], 3), coffee(2, [6, 7, 6, 5, 6, 5, 5], [], 4)];
  const near = differences(close);
  assertEquals(near.close, true);
  assertEquals(near.slight?.axis, "sweetness");
  assertEquals(describe(close), [
    "Coffees:",
    "No. 1: Coffee 1",
    "No. 2: Coffee 2",
    "",
    "Facts:",
    "- taste: close",
    "- sweetness: No. 2 slightly higher than No. 1",
    "- rating: No. 2 higher than No. 1",
  ].join("\n"));
});

Deno.test("one-point gaps are left out, the three largest come first, in words", () => {
  // Bulga West Arsi and Ethiopia Dimtu: sweetness 5 vs 4 was called "much higher".
  const pair = [
    coffee(1, [5, 5, 5, 8, 5, 3, 5], ["Lemon", "Winey", "Sweet Aromatics"], 4),
    coffee(2, [2, 6, 4, 3, 6, 5, 1], [], 2),
  ];
  const { differences: facts, close } = differences(pair);
  assertEquals(close, false);
  assertEquals(
    facts.map((d) => (d.kind === "axis" ? `${d.axis} ${d.gap}` : d.kind)),
    ["aroma 5", "clarity 4", "acidity 3", "rating", "flavours", "no-flavours"],
  );
  const text = describe(pair);
  assertEquals(text.includes("sweetness"), false);
  assertEquals(text.includes("body"), false);
  assertEquals(text.includes("- aroma: No. 1 much higher than No. 2"), true);
  assertEquals(text.includes("- acidity: No. 1 higher than No. 2"), true);
  // No score, point or gap reaches the model.
  assertEquals(/\d/.test(text.split("Facts:")[1].replace(/No\. \d/g, "")), false);
  assertEquals(text.includes("- flavours only No. 1 has: lemon, winey"), true);
  // The reading knows No. 2 has none; the model is not told, so it says nothing.
  assertEquals(text.includes("no flavours"), false);
});

Deno.test("a trio ranks its two largest axes, ties together", () => {
  const trio = [
    coffee(1, [4, 3, 6, 4, 6, 6, 4], [], 3),
    coffee(2, [6, 5, 4, 6, 4, 5, 6], ["Apple", "Peach"], 5),
    coffee(3, [4, 6, 5, 3, 6, 5, 3], ["Cocoa", "peach"], 3),
  ];
  const text = describe(trio);
  assertEquals(text.includes("- bitterness: No. 3 highest, No. 2 in between, No. 1 lowest"), true);
  assertEquals(text.includes("- aroma: No. 2 highest, No. 1 in between, No. 3 lowest"), true);
  // Clarity has the same gap as aroma, but a trio keeps two axes.
  assertEquals(text.includes("clarity"), false);
  assertEquals(text.includes("- aroma: No. 2 highest, No. 1 lowest, No. 3 lowest"), false);
  assertEquals(text.includes("- rating: No. 2 higher than No. 1 and No. 3"), true);
  // Peach is shared, whatever its case.
  assertEquals(text.includes("- flavours only No. 2 has: apple"), true);
  assertEquals(text.includes("- flavours only No. 3 has: cocoa"), true);
});

Deno.test("only axes they all scored count, and a missing rating drops the rating", () => {
  const pair: Series[] = [
    { number: 1, title: "A", axes: { acidity: 8, body: 2 }, flavors: [], rating: null },
    { number: 2, title: "B", axes: { acidity: 3 }, flavors: [], rating: 4 },
  ];
  const { differences: facts } = differences(pair);
  assertEquals(facts.map((d) => d.kind === "axis" ? d.axis : d.kind), ["acidity"]);
  assertEquals(describe([
    { number: 1, title: "A", axes: {}, flavors: [] },
    { number: 2, title: "B", axes: {}, flavors: [] },
  ]).endsWith("- nothing notable sets them apart"), true);
  const same = [coffee(1, [5, 5, 5, 5, 5, 5, 5]), coffee(2, [5, 5, 5, 5, 5, 5, 5])];
  assertEquals(describe(same).includes("- taste: the same on every axis they all scored"), true);
});

Deno.test("OpenAI writes first unless the body asks for one provider alone", () => {
  assertEquals(provider({ series: [], provider: "openai" }), "openai");
  assertEquals(provider({ series: [], provider: "gemini" }), "gemini");
  assertEquals(provider({ series: [] }), "openai-first");
  assertEquals(provider({ provider: "claude" }), "openai-first");
  assertEquals(provider({ provider: "OpenAI" }), "openai-first");
  assertEquals(provider(null), "openai-first");
});

Deno.test("OpenAI and the backup together stay inside the app's 12 s", () => {
  assertEquals(OPENAI_FIRST_MS + BACKUP_MS.reduce((a, b) => a + b, 0) < 12_000, true);
});
