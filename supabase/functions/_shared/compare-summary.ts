// compare-summary, the rules without the server: what the model is told,
// which bodies are accepted, and how its answer is read. Kept apart from
// index.ts so `deno test` can load it without starting Deno.serve.

// The model is not trusted with arithmetic. On real tastings, where most
// scores sit between 4 and 7, it turned one-point gaps into "much higher" and
// once said the less sweet coffee was the sweeter. So the differences are
// worked out here, with their direction, and the model only puts them into
// words.
export const PROMPT = `\
You compare two or three coffees for Kohi, a coffee journal.

You get each coffee's number and title, then the facts that set them apart, \
already worked out from their scores, largest first. Write one or two short \
sentences from those facts, 35 words at most.

Rules:
1. Name each coffee by its number only: "No. 1", "No. 2". Never its title: \
   the legend beside the text already pairs them.
2. Use only the facts given and keep their direction: when a fact says No. 1 \
   is higher, never write that another one is.
3. Never mention an axis, a flavour or a rating that is not in the facts.
4. When the facts say the taste is close, say so, then give the one taste \
   difference listed as slight, as slight.
5. Say "much" only where a fact says "much".
6. No numbers: no scores, points or gaps. The radar beside the text shows them.
7. Write flavours as they are given. Say nothing about the flavours of a \
   coffee that has none listed.
8. Plain English, as a person would say it at the counter. No jargon, no \
   marketing adjectives, no exclamation marks.`;

export const AXES = [
  "acidity",
  "bitterness",
  "sweetness",
  "aroma",
  "aftertaste",
  "body",
  "clarity",
] as const;

/// The smallest gap worth a sentence: two points on an axis, one on the rating.
export const NOTABLE_AXIS = 2;
export const NOTABLE_RATING = 1;
/// A gap this large is "much" higher.
export const LARGE_AXIS = 4;
/// Two sentences hold about three differences: the largest axes, then the
/// rating and flavours. A trio has three coffees to place on each axis, so it
/// keeps two: with three, both models wrote four sentences.
export const MOST_AXES = 3;
export const MOST_AXES_TRIO = 2;

type Ranked = { numbers: number[]; value: number }[];

export type Difference =
  | { kind: "axis"; axis: string; gap: number; ranked: Ranked }
  | { kind: "rating"; gap: number; ranked: Ranked }
  | { kind: "flavours"; number: number; only: string[] }
  | { kind: "no-flavours"; number: number };

export type Reading = {
  differences: Difference[];
  /// Every axis they all scored is within a point.
  close: boolean;
  /// When close: the axis that differs most, if any differs at all.
  slight: Extract<Difference, { kind: "axis" }> | null;
};

/// Values grouped from highest to lowest, ties together.
function rank(entries: { number: number; value: number }[]): Ranked {
  const groups = new Map<number, number[]>();
  for (const e of entries) groups.set(e.value, [...(groups.get(e.value) ?? []), e.number]);
  return [...groups.entries()]
    .sort((a, b) => b[0] - a[0])
    .map(([value, numbers]) => ({ numbers: numbers.sort((a, b) => a - b), value }));
}

const gapOf = (ranked: Ranked) => ranked[0].value - ranked[ranked.length - 1].value;

/// What sets the series apart, largest first: axes every one of them scored,
/// then the rating, then flavours only one of them has.
export function differences(series: Series[]): Reading {
  const axes = AXES.flatMap((axis) => {
    if (!series.every((s) => typeof s.axes?.[axis] === "number")) return [];
    const ranked = rank(series.map((s) => ({ number: s.number, value: s.axes[axis] })));
    return [{ kind: "axis" as const, axis, gap: gapOf(ranked), ranked }];
  });
  // Stable: equal gaps keep the axes' own order.
  const byGap = [...axes].sort((a, b) => b.gap - a.gap);
  const most = series.length === 3 ? MOST_AXES_TRIO : MOST_AXES;
  const notable: Difference[] = byGap.filter((d) => d.gap >= NOTABLE_AXIS).slice(0, most);

  const rated = series.filter((s) => typeof s.rating === "number");
  if (rated.length === series.length) {
    const ranked = rank(rated.map((s) => ({ number: s.number, value: s.rating as number })));
    const gap = gapOf(ranked);
    if (gap >= NOTABLE_RATING) notable.push({ kind: "rating", gap, ranked });
  }

  const flavours = series.map((s) => (s.flavors ?? []).filter((f) => f.trim()));
  if (flavours.some((list) => list.length)) {
    series.forEach((s, index) => {
      if (!flavours[index].length) {
        notable.push({ kind: "no-flavours", number: s.number });
        return;
      }
      const others = new Set(
        flavours.flatMap((list, i) => (i === index ? [] : list.map((f) => f.toLowerCase()))),
      );
      const only = flavours[index].filter((f) => !others.has(f.toLowerCase()));
      if (only.length) notable.push({ kind: "flavours", number: s.number, only });
    });
  }

  const close = axes.length > 0 && byGap[0].gap < NOTABLE_AXIS;
  const slight = close && byGap[0].gap > 0 ? byGap[0] : null;
  return { differences: notable, close, slight };
}

const no = (numbers: number[]) => numbers.map((n) => `No. ${n}`).join(" and ");

/// One fact in words. No numbers: the model copied them into the summary
/// ("with a score of 7 compared to 5"), and the radar already shows them.
function ordered(what: string, ranked: Ranked, gap: number, size = gap >= LARGE_AXIS ? "much " : ""): string {
  if (ranked.length === 2) {
    return `${what}: ${no(ranked[0].numbers)} ${size}higher than ${no(ranked[1].numbers)}`;
  }
  const parts = ranked.map((group, index) => {
    const place = index === 0 ? "highest" : index === ranked.length - 1 ? "lowest" : "in between";
    return `${no(group.numbers)} ${place}`;
  });
  const by = size === "much " ? ", by much" : size === "slightly " ? ", slightly" : "";
  return `${what}: ${parts.join(", ")}${by}`;
}

/// The model's input: who is who, then the facts, one per line.
export function describe(series: Series[]): string {
  const { differences: facts, close, slight } = differences(series);
  const lines = ["Coffees:", ...series.map((s) => `No. ${s.number}: ${s.title}`), "", "Facts:"];
  if (close) {
    lines.push(
      slight
        ? "- taste: close"
        : "- taste: the same on every axis they all scored",
    );
    if (slight) lines.push(`- ${ordered(slight.axis, slight.ranked, slight.gap, "slightly ")}`);
  }
  for (const fact of facts) {
    switch (fact.kind) {
      case "axis":
        lines.push(`- ${ordered(fact.axis, fact.ranked, fact.gap)}`);
        break;
      case "rating":
        lines.push(`- ${ordered("rating", fact.ranked, fact.gap, "")}`);
        break;
      case "flavours":
        // The most noted two: four flavours each made the sentences lists.
        // Lower case, as they read mid-sentence ("Other Fruit" came back
        // capitalised).
        lines.push(`- flavours only No. ${fact.number} has: ${fact.only.slice(0, 2).map((f) => f.toLowerCase()).join(", ")}`);
        break;
      case "no-flavours":
        // Kept in the reading, left out of the facts: told it, OpenAI
        // wrote "no flavours are noted for No. 2".
        break;
    }
  }
  if (lines[lines.length - 1] === "Facts:") lines.push("- nothing notable sets them apart");
  return lines.join("\n");
}

export const SCHEMA = {
  type: "OBJECT",
  properties: { summary: { type: "STRING" } },
  required: ["summary"],
};

export type Series = {
  number: number;
  title: string;
  detail?: string;
  axes: Record<string, number>;
  flavors?: string[];
  rating?: number | null;
};

/// The same answer for OpenAI, as strict JSON Schema.
export const OPENAI_SCHEMA = {
  type: "object",
  properties: { summary: { type: "string" } },
  required: ["summary"],
  additionalProperties: false,
};

/// Who writes it: see _shared/provider.ts. On Timour's tastings (22 Nov
/// 2026) gpt-5.6-luna answered 15 of 15 in 1.6 s at the median, while the
/// Gemini fallback left people waiting 6 to 12 s.
export { type Provider, provider } from "./provider.ts";

/// The app stops waiting at 12 s (CompareSummary.withDeadline). OpenAI gets
/// 6 s, about three times its slowest answer; the backup gets 5 s, five times
/// flash-lite's usual answer.
export const OPENAI_FIRST_MS = 6_000;
export const BACKUP_MS = [5_000];

/// A provider asked for alone gets the whole time Gemini's two tries get.
export const OPENAI_MS = 15_000;

/// The primary model gets six seconds: a person is looking at the radar,
/// waiting. The lighter fallback then has the rest of the client's patience.
export const ATTEMPT_MS = [6_000, 20_000];

/// Two to three series, the first three if more came. Null when the body
/// cannot be compared.
export function validSeries(body: unknown): Series[] | null {
  const raw = (body as { series?: unknown })?.series;
  if (!Array.isArray(raw)) return null;
  const series = raw.slice(0, 3) as Series[];
  return series.length < 2 ? null : series;
}

/// The summary out of the model's JSON, trimmed. Null when the text is not
/// JSON, has no summary, or the summary is empty.
export function readSummary(text: string | undefined): string | null {
  if (!text) return null;
  try {
    const parsed = JSON.parse(text);
    const summary = typeof parsed?.summary === "string" ? parsed.summary.trim() : "";
    return summary || null;
  } catch {
    return null;
  }
}
