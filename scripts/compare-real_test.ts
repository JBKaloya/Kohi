import { assertEquals } from "jsr:@std/assert@1";
import { axes, checks, choose, direction, distance, flavorName, numbered, ratingPoints } from "./compare-real.ts";

Deno.test("a taste is read in the three shapes the app reads", () => {
  assertEquals(axes({ values: { acidity: 8, body: 0, clarity: 11 } }), { acidity: 8, body: 0 });
  assertEquals(axes({ acidity: 4, body: 2, clarity: 9 }), { acidity: 8, body: 4 });
  assertEquals(axes({ clarity: 7 }), { clarity: 7 });
  assertEquals(axes({}), {});
  assertEquals(axes(null), {});
});

Deno.test("a flavour reads as the wheel's label or the words typed", () => {
  const labels = new Map([["floral-floral-jasmine", "Jasmine"]]);
  assertEquals(flavorName("floral-floral-jasmine", labels), "Jasmine");
  assertEquals(flavorName({ id: "floral-floral-jasmine", intensity: 2 }, labels), "Jasmine");
  assertEquals(flavorName({ id: "custom:lychee", custom: "Lychee" }, labels), "Lychee");
  assertEquals(flavorName("custom:yuzu", labels), "yuzu");
  assertEquals(flavorName(null, labels), null);
});

Deno.test("half points count only when they agree with the whole rating", () => {
  assertEquals(ratingPoints(4, 9), 4.5);
  assertEquals(ratingPoints(4, 6), 4);
  assertEquals(ratingPoints(4, null), 4);
  assertEquals(ratingPoints(null, 9), null);
});

function tasting(id: string, title: string, acidity: number, body: number, sweetness: number, flavors: string[] = []) {
  return {
    id,
    origin: "",
    series: { title, detail: "12 Nov", axes: { acidity, body, sweetness }, flavors, rating: 4 },
  };
}

Deno.test("comparisons mix far pairs, close pairs and trios, three uses at most", () => {
  const tastings = [
    tasting("a", "Kenya", 9, 2, 5, ["Blackcurrant"]),
    tasting("b", "Brazil", 2, 9, 8, ["Chocolate"]),
    tasting("c", "Ethiopia", 8, 3, 7, ["Jasmine"]),
    tasting("d", "Colombia", 5, 6, 6),
    tasting("e", "Guatemala", 5, 6, 7),
    tasting("f", "Thin", 5, 5, 5),
  ];
  tastings[5].series.axes = { acidity: 5 } as never; // fewer than three axes: left out
  const picks = choose(tastings, 5);
  assertEquals(picks.some((p) => p.length === 3), true);
  assertEquals(picks.some((p) => p.some((t) => t.id === "f")), false);
  const uses = new Map<string, number>();
  for (const t of picks.flat()) uses.set(t.id, (uses.get(t.id) ?? 0) + 1);
  assertEquals([...uses.values()].every((n) => n <= 3), true);
  // The farthest pair comes first.
  const first = picks[0].map((t) => t.id).sort();
  assertEquals(first, ["a", "b"]);
  assertEquals(distance(tastings[3].series, tastings[4].series) < 1, true);
});

Deno.test("the checks flag a missing number, a small gap and an invented flavour", () => {
  const series = numbered([
    tasting("a", "Kenya", 9, 3, 5, ["Blackcurrant"]),
    tasting("b", "Brazil", 2, 8, 6, ["Chocolate"]),
  ]);
  const wheel = ["Blackcurrant", "Chocolate", "Peach", "Jasmine"];
  assertEquals(checks(series, "No. 1 is brighter with blackcurrant; No. 2 has more body and chocolate.", wheel), []);
  assertEquals(checks(series, "No. 1 is brighter and sweeter, with peach.", wheel), [
    "numbers: does not name No. 2",
    "gaps: names sweetness, spread 1",
    'flavours: names "Peach", which none of them has',
    "direction: says No. 1 is higher on sweetness (5 vs 6)",
  ]);
});

Deno.test("the checks catch a reversed claim and leave flavour words and axis words alone", () => {
  // Onibus Guatemala and Gakuyuini, as flash-lite summarised them on 22 Nov.
  const close = numbered([
    tasting("a", "Guatemala", 6, 4, 7),
    tasting("b", "Gakuyuini", 6, 5, 5),
  ]);
  close[0].axes = { ...close[0].axes, aftertaste: 5 };
  close[1].axes = { ...close[1].axes, aftertaste: 6 };
  assertEquals(direction(close, "no. 2 has higher sweetness while no. 1 has a slightly more prominent aftertaste."), [
    "direction: says No. 2 is higher on sweetness (5 vs 7)",
    "direction: says No. 1 is higher on aftertaste (5 vs 6)",
  ]);
  // Two coffees tied at the top, said together.
  const trio = numbered([
    tasting("a", "Worka", 4, 5, 6),
    tasting("b", "Huehue", 6, 4, 5),
    tasting("c", "Onibus", 6, 4, 7),
  ]);
  assertEquals(direction(trio, "no. 2 and no. 3 have higher acidity than no. 1, and no. 3 is the sweetest."), []);
  assertEquals(direction(trio, "no. 3 has higher acidity than no. 1."), []);
  assertEquals(direction(trio, "no. 3 has higher acidity than no. 2."), [
    "direction: says No. 3 is higher on acidity (6 vs 6)",
  ]);
  assertEquals(direction(trio, "no. 1 and no. 2 have higher acidity, and no. 2 has the most sweetness."), [
    "direction: says No. 1 and No. 2 are higher on acidity (4, 6 vs 6)",
    "direction: says No. 2 is higher on sweetness (5 vs 6, 7)",
  ]);
  assertEquals(direction(close, "they are close; no. 1 is sweeter, and no. 2 has lower body."), [
    "direction: says No. 2 is lower on body (5 vs 4)",
  ]);

  const far = numbered([
    tasting("a", "Rio Ata", 7, 5, 6, ["Sweet Aromatics", "Lime"]),
    tasting("b", "Dimtu", 2, 5, 4),
  ]);
  const wheel = ["Bitter", "Sweet Aromatics", "Lime"];
  // "sweet aromatics" is a flavour, "more bitter" is the axis, not the Bitter flavour.
  far[0].axes = { ...far[0].axes, bitterness: 4 };
  far[1].axes = { ...far[1].axes, bitterness: 7 };
  assertEquals(checks(far, "No. 1 is much higher in acidity with lime and sweet aromatics, while No. 2 is more bitter.", wheel), []);
  assertEquals(checks(far, "No. 1 is more bitter, with lime.", wheel), [
    "numbers: does not name No. 2",
    "direction: says No. 1 is higher on bitterness (4 vs 7)",
  ]);
});
