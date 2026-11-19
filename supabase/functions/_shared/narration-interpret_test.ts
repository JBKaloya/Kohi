// deno test supabase/functions/_shared/

import { assertEquals } from "jsr:@std/assert@1";
import { estimate, timedLines, utterances } from "./narration-interpret.ts";

const word = (w: string, start: number) => ({ w, start, end: start + 0.2 });

Deno.test("lines break after a sentence and after a pause", () => {
  const words = [
    word("Bloom", 3), word("40.", 3.4),
    word("Je", 10), word("verse", 10.3),
    word("encore", 12), word("100", 12.3),
  ];
  assertEquals(timedLines(words), "[3.0] Bloom 40.\n[10.0] Je verse\n[12.0] encore 100");
});

Deno.test("utterances are sentences with their first second", () => {
  assertEquals(utterances([word("Bloom", 3), word("40.", 3.4), word("Ça", 30), word("draine", 30.2)]), [
    { at: 3, text: "Bloom 40." },
    { at: 30, text: "Ça draine" },
  ]);
});

Deno.test("words the device heard keep its seconds, the others fall between", () => {
  const placed = estimate(
    "OK donc la bloom de 40 grammes. Et enfin je termine.",
    [{ at: 4, text: "bloom" }, { at: 30.6, text: "Et" }, { at: 31.1, text: "termine" }],
    33,
  );
  assertEquals(placed[3].start, 4);
  assertEquals(placed[7].start, 30.6);
  assertEquals(placed[10].start, 31.1);
  const grams = placed[6].start;
  if (!(grams > 4 && grams < 30.6)) throw new Error(`grammes at ${grams}`);
  if (!(placed[0].start < 4 && placed[0].start >= 0)) throw new Error(`OK at ${placed[0].start}`);
});

Deno.test("without any match the words spread over the note", () => {
  const placed = estimate("un deux trois", [], 8);
  assertEquals(placed.map((w) => w.start), [2, 4, 6]);
});
