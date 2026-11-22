import { assertEquals } from "jsr:@std/assert@1";
import { folded, fromVision, judge, matches } from "./scan-bench.ts";

Deno.test("the same fact written another way matches", () => {
  assertEquals(folded("  Café  Ñandú! "), "cafe nandu");
  assertEquals(matches("country", "DR Congo", "Congo"), true);
  assertEquals(matches("process", "Washed", "WASHED"), true);
  assertEquals(matches("altitude", "1750", "1750 masl"), true);
  assertEquals(matches("altitude", "1750", "175C"), false);
  assertEquals(matches("altitude", "1897", "1,897M"), true);
  assertEquals(matches("altitude", "1570-1850", "1,570~1,850m"), true);
  assertEquals(matches("process", "Washed", "175C"), false);
});

Deno.test("each printed field is right, wrong or missed, and the notes are counted", () => {
  // The Congo card as the device first read it.
  const verdict = judge(
    { name: "Majirane", country: "DR Congo", process: "Washed", altitude: "1750", notes: ["Plum", "Molasses", "Liquorice"] },
    { name: "SUPER", country: "Congo", process: "175C", roaster: "Process Coffee", notes: ["NOTES"] },
  );
  assertEquals(verdict.name, "wrong");
  assertEquals(verdict.country, "right");
  assertEquals(verdict.process, "wrong");
  assertEquals(verdict.altitude, "missed");
  assertEquals(verdict.roaster, "extra");
  assertEquals(verdict.region, null);
  assertEquals(verdict.notesRecall, 0);
  assertEquals(verdict.notesNoise, 1);
});

Deno.test("card-vision's answer becomes a read", () => {
  assertEquals(
    fromVision({ name: " Majirane ", process: "", tastingNotes: ["Plum", 3], model: "x" }),
    { name: "Majirane", notes: ["Plum"] },
  );
});
