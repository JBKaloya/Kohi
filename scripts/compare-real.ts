// compare-summary on real tastings: what the summary says about comparisons
// a tester could actually make, read side by side with what was compared.
//
//   deno run --allow-net --allow-read --allow-write --allow-env \
//     scripts/compare-real.ts .private/tastings.json [--limit=15] [--dry-run]
//
// The JSON is the `export` cell of supabase/checks/2026-11-21-export-tastings.sql.
// Each tasting becomes a series the way the app builds one
// (CompareSeries.tasting, CompareSummary.payload): the coffee's name, place ·
// date, the scored axes, up to four flavours and the rating in points.
//
// Comparisons are drawn to cover what the prompt has to handle: pairs far
// apart, pairs close together (the summary should say they are close), and
// trios. No tasting appears in more than three, and the same coffees are
// compared once.
//
// The calls need a signed-in session since 21 Nov 2026: a test account's
// KOHI_SMOKE_EMAIL and KOHI_SMOKE_PASSWORD, or a KOHI_SMOKE_JWT, from the
// environment or .env (ignored by git). The project URL and key come
// from Kohi/Resources/Supabase.plist; none of them is printed. --dry-run
// builds the comparisons and prints them without calling anything.
//
// The report goes to .private/compare-real-<date>.md: each comparison with its
// axes and flavours, the summary, the model, the latency, and three checks
// that flag what to look at rather than grade it:
//   numbers   every coffee is named by its number;
//   gaps      an axis is named although no two coffees differ on it by 2 or more;
//   flavours  a flavour of the wheel is named that none of the coffees has.

const PLIST = "Kohi/Resources/Supabase.plist";
const WHEEL = "Kohi/Resources/Reference/flavor-wheel.json";
const AXES = ["acidity", "bitterness", "sweetness", "aroma", "aftertaste", "body", "clarity"] as const;
const FLAVOR_LIMIT = 4;
const MIN_AXES = 3;
const MAX_USES = 3;

type Axis = typeof AXES[number];
type Row = {
  id: string;
  tasted_at: string;
  coffee?: { name?: string | null; roaster?: string | null; country?: string | null; process?: string | null };
  place?: string | null;
  taste?: Record<string, unknown> | null;
  flavors?: unknown[] | null;
  rating?: number | null;
  rating_halves?: number | null;
};
export type Series = {
  number: number;
  title: string;
  detail: string;
  axes: Partial<Record<Axis, number>>;
  flavors: string[];
  rating: number | null;
};
type Tasting = { id: string; series: Omit<Series, "number">; origin: string };

// ---- Reading a tasting the way the app does ---------------------------------

/// TasteProfile.init(from:): `{ values: {...} }` is 0–10. Otherwise any of
/// the six card-era keys at the top makes it the legacy 1–5 object, doubled,
/// with no clarity. Only a top level with clarity alone is read as 0–10.
export function axes(taste: Record<string, unknown> | null | undefined): Partial<Record<Axis, number>> {
  const out: Partial<Record<Axis, number>> = {};
  if (!taste) return out;
  const isInt = (value: unknown): value is number => typeof value === "number" && Number.isInteger(value);
  const nested = taste.values;
  if (nested && typeof nested === "object") {
    for (const axis of AXES) {
      const value = (nested as Record<string, unknown>)[axis];
      if (isInt(value) && value >= 0 && value <= 10) out[axis] = value;
    }
    return out;
  }
  const legacyKeys = AXES.filter((axis) => axis !== "clarity");
  if (legacyKeys.some((axis) => isInt(taste[axis]))) {
    for (const axis of legacyKeys) {
      const value = taste[axis];
      if (isInt(value) && value >= 1 && value <= 5) out[axis] = value * 2;
    }
    return out;
  }
  if (isInt(taste.clarity) && taste.clarity >= 0 && taste.clarity <= 10) out.clarity = taste.clarity;
  return out;
}

export function flavorName(tag: unknown, labels: Map<string, string>): string | null {
  const id = typeof tag === "string" ? tag : (tag as { id?: unknown })?.id;
  const custom = typeof tag === "object" && tag ? (tag as { custom?: unknown }).custom : undefined;
  if (typeof custom === "string" && custom.trim()) return custom.trim();
  if (typeof id !== "string" || !id) return null;
  if (id.startsWith("custom:")) return id.slice("custom:".length) || null;
  return labels.get(id) ?? id;
}

/// HalfRating.resolve, then points: halves only when they agree with the
/// whole rating.
export function ratingPoints(rating: number | null | undefined, halves: number | null | undefined): number | null {
  if (typeof rating !== "number" || rating < 1 || rating > 5) return null;
  if (typeof halves === "number" && halves >= 1 && halves <= 10 && Math.max(1, Math.floor(halves / 2)) === rating) {
    return halves / 2;
  }
  return rating;
}

function tasting(row: Row, labels: Map<string, string>): Tasting {
  const date = new Date(row.tasted_at).toLocaleDateString("en-GB", { day: "numeric", month: "short" });
  const place = row.place?.trim() ?? "";
  const names: string[] = [];
  for (const tag of row.flavors ?? []) {
    const name = flavorName(tag, labels);
    if (name && !names.includes(name)) names.push(name);
  }
  const coffee = row.coffee ?? {};
  return {
    id: row.id,
    origin: [coffee.roaster, coffee.country, coffee.process].filter(Boolean).join(" · "),
    series: {
      title: coffee.name?.trim() || "A coffee",
      detail: place ? `${place} · ${date}` : date,
      axes: axes(row.taste),
      flavors: names.slice(0, FLAVOR_LIMIT),
      rating: ratingPoints(row.rating, row.rating_halves),
    },
  };
}

// ---- Choosing comparisons ----------------------------------------------------

/// How far apart two tastings are: the mean gap over the axes both scored,
/// plus one point per flavour only one of them has (capped at 3).
export function distance(a: Tasting["series"], b: Tasting["series"]): number {
  const shared = AXES.filter((axis) => a.axes[axis] !== undefined && b.axes[axis] !== undefined);
  if (!shared.length) return 0;
  const gap = shared.reduce((sum, axis) => sum + Math.abs(a.axes[axis]! - b.axes[axis]!), 0) / shared.length;
  const only = a.flavors.filter((f) => !b.flavors.includes(f)).length +
    b.flavors.filter((f) => !a.flavors.includes(f)).length;
  return gap + Math.min(3, only) * 0.5;
}

export function choose(tastings: Tasting[], limit: number): Tasting[][] {
  const usable = tastings.filter((t) => Object.keys(t.series.axes).length >= MIN_AXES);
  const pairs: { pick: Tasting[]; d: number }[] = [];
  for (let i = 0; i < usable.length; i++) {
    for (let j = i + 1; j < usable.length; j++) {
      // Two tastings of the same coffee at the same place say little.
      if (usable[i].series.title === usable[j].series.title && usable[i].series.detail === usable[j].series.detail) continue;
      pairs.push({ pick: [usable[i], usable[j]], d: distance(usable[i].series, usable[j].series) });
    }
  }
  const uses = new Map<string, number>();
  const chosen: Tasting[][] = [];
  // The same coffees twice say nothing new, even from other tastings.
  const seen = new Set<string>();
  const titles = (pick: Tasting[]) => pick.map((t) => t.series.title).sort().join("\u{1f}");
  const free = (pick: Tasting[]) =>
    !seen.has(titles(pick)) && pick.every((t) => (uses.get(t.id) ?? 0) < MAX_USES);
  const take = (pick: Tasting[]) => {
    chosen.push(pick);
    seen.add(titles(pick));
    for (const t of pick) uses.set(t.id, (uses.get(t.id) ?? 0) + 1);
  };

  const far = Math.ceil(limit * 0.6);
  const close = Math.floor(limit * 0.2);
  const trios = limit - far - close;

  for (const { pick } of [...pairs].sort((a, b) => b.d - a.d)) {
    if (chosen.length >= far) break;
    if (free(pick)) take(pick);
  }
  // Trios: a far pair plus the tasting farthest from both.
  let triosTaken = 0;
  for (const { pick } of [...pairs].sort((a, b) => b.d - a.d)) {
    if (triosTaken >= trios) break;
    const third = usable
      .filter((t) => !pick.includes(t))
      .map((t) => ({ t, d: Math.min(distance(t.series, pick[0].series), distance(t.series, pick[1].series)) }))
      .sort((a, b) => b.d - a.d)
      .find(({ t }) => free([...pick, t]));
    if (third) {
      take([...pick, third.t]);
      triosTaken++;
    }
  }
  let closeTaken = 0;
  for (const { pick } of [...pairs].sort((a, b) => a.d - b.d)) {
    if (closeTaken >= close) break;
    if (free(pick)) {
      take(pick);
      closeTaken++;
    }
  }
  return chosen;
}

export function numbered(pick: Tasting[]): Series[] {
  return pick.map((t, index) => ({ number: index + 1, ...t.series }));
}

// ---- Checking what the summary says -------------------------------------------

export function checks(series: Series[], summary: string, wheelLabels: string[]): string[] {
  const notes: string[] = [];
  const missing = series.filter((s) => !new RegExp(`No\\.\\s?${s.number}\\b`).test(summary)).map((s) => s.number);
  if (missing.length) notes.push(`numbers: does not name No. ${missing.join(", No. ")}`);

  // Flavour names said back ("Sweet Aromatics", "sweet notes") are not the axis.
  const given = new Set(series.flatMap((s) => s.flavors.map((f) => f.toLowerCase())));
  let lower = summary.toLowerCase();
  for (const flavour of [...given].sort((a, b) => b.length - a.length)) lower = lower.split(flavour).join(" ");
  lower = lower.replace(/\bsweet (flavou?rs?|notes?|aromatics?)\b/g, " ");

  for (const axis of AXES) {
    if (!STEMS[axis].test(lower)) continue;
    const values = series.map((s) => s.axes[axis]).filter((v): v is number => v !== undefined);
    const spread = values.length >= 2 ? Math.max(...values) - Math.min(...values) : 0;
    // Close coffees may name their one slight gap, as slight: the prompt asks for it.
    const slightAllowed = spread === 1 && /\b(close|similar|alike)/.test(lower) && /\bslight/.test(lower);
    if (values.length >= 2 && spread < 2 && !slightAllowed) notes.push(`gaps: names ${axis}, spread ${spread}`);
    if (values.length < 2) notes.push(`gaps: names ${axis}, scored on ${values.length} coffee`);
  }

  for (const label of wheelLabels) {
    const word = label.toLowerCase();
    if (word.length < 4 || given.has(word)) continue;
    // "Bitter", "Sweet", "Sour": wheel labels, but also how an axis is said.
    if (AXES.some((axis) => STEMS[axis].test(word))) continue;
    if ([...given].some((g) => g.includes(word) || word.includes(g))) continue;
    if (new RegExp(`\\b${word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`).test(lower)) {
      notes.push(`flavours: names "${label}", which none of them has`);
    }
  }
  const spreads = AXES.flatMap((axis) => {
    const values = series.map((s) => s.axes[axis]);
    return values.every((v) => v !== undefined) ? [Math.max(...values as number[]) - Math.min(...values as number[])] : [];
  });
  if (spreads.length && Math.max(...spreads) < 2 && !/\b(close|similar|alike|near)/.test(lower)) {
    notes.push("close: no axis differs by 2, and it does not say they are close");
  }
  notes.push(...direction(series, lower));
  return notes;
}

/// "sweeter", "more acidic", "fuller-bodied": the axis, however it is said.
const STEMS: Record<Axis, RegExp> = {
  acidity: /\bacid/,
  bitterness: /\bbitter/,
  sweetness: /\bsweet/,
  aroma: /\baroma/,
  aftertaste: /\baftertaste|\bfinish/,
  body: /\bbod(y|ied)/,
  clarity: /\bclarity|\bclean/,
};

/// Comparatives that carry their axis in one word.
const FOLDED: [RegExp, Axis, 1 | -1][] = [
  [/\bsweeter\b/, "sweetness", 1],
  [/\bbrighter\b/, "acidity", 1],
  [/\bfuller\b/, "body", 1],
  [/\bcleaner\b/, "clarity", 1],
  [/\blonger (after|finish)/, "aftertaste", 1],
];

const UP = /\b(higher|highest|more|most|stronger|greater|fuller|longer|bigger|heavier)\b/g;
const DOWN = /\b(lower|lowest|less|least|weaker|lighter|shorter|thinner|softer)\b/g;

/// A coffee said to be higher on an axis must be above every other one, and
/// lower below every other one. Each clause is read on its own: its subject is
/// the first "No. n" in it, and each axis takes the nearest comparative before it.
export function direction(series: Series[], text: string): string[] {
  const notes: string[] = [];
  // A full stop ends a sentence, not the one in "No. 2".
  const clauses = text.split(/\.(?!\s?\d)|;|\bwhile\b|\bwhereas\b|\bbut\b|\bcompared\b/);
  // A clause can change subject mid-way ("No. 1 is sweeter, and No. 2 ...");
  // "than No. 2" or "compared to No. 2" do not, and "No. 2 and No. 3 have"
  // is one subject of two.
  const segments = clauses.flatMap((clause) => {
    const starts = [...clause.matchAll(/no\.\s?(\d)/g)].filter((m) =>
      !/(than|to|from|with)\s*$/.test(clause.slice(0, m.index!))
    );
    const out: { numbers: number[]; text: string }[] = [];
    starts.forEach((m, i) => {
      const text = clause.slice(m.index!, starts[i + 1]?.index);
      const joined = out.length && /^no\.\s?\d\s+and\s*$/.test(out[out.length - 1].text);
      if (joined) {
        const last = out[out.length - 1];
        out[out.length - 1] = { numbers: [...last.numbers, Number(m[1])], text: last.text + text };
      } else {
        out.push({ numbers: [Number(m[1])], text });
      }
    });
    return out;
  });
  for (const { numbers, text: clause } of segments) {
    const group = series.filter((s) => numbers.includes(s.number));
    if (group.length !== numbers.length) continue;
    const claims: [Axis, 1 | -1][] = [];
    for (const [pattern, axis, sign] of FOLDED) if (pattern.test(clause)) claims.push([axis, sign]);
    for (const axis of AXES) {
      const at = clause.search(STEMS[axis]);
      if (at < 0 || claims.some(([a]) => a === axis)) continue;
      const before = clause.slice(0, at);
      const lastUp = Math.max(-1, ...[...before.matchAll(UP)].map((m) => m.index!));
      const lastDown = Math.max(-1, ...[...before.matchAll(DOWN)].map((m) => m.index!));
      if (lastUp < 0 && lastDown < 0) continue;
      claims.push([axis, lastUp > lastDown ? 1 : -1]);
    }
    for (const [axis, sign] of claims) {
      const values = group.map((s) => s.axes[axis]);
      if (values.some((v) => v === undefined)) continue;
      // "higher acidity than No. 1" compares with No. 1 only.
      const than = clause.match(/than ((?:no\.\s?\d(?:,\s*|\s+and\s+|\s+or\s+)?)+)/);
      const against = than ? [...than[1].matchAll(/no\.\s?(\d)/g)].map((m) => Number(m[1])) : null;
      const others = series
        .filter((s) => !group.includes(s) && (!against || against.includes(s.number)))
        .map((s) => s.axes[axis])
        .filter((v): v is number => v !== undefined);
      const wrong = sign === 1
        ? others.some((v) => v >= Math.min(...values as number[]))
        : others.some((v) => v <= Math.max(...values as number[]));
      if (wrong) {
        notes.push(
          `direction: says ${numbers.map((n) => `No. ${n}`).join(" and ")} ${numbers.length > 1 ? "are" : "is"} ${sign === 1 ? "higher" : "lower"} on ${axis} (${values.join(", ")} vs ${others.join(", ")})`,
        );
      }
    }
  }
  return notes;
}

// ---- Running -----------------------------------------------------------------

function plistValue(xml: string, key: string): string | undefined {
  return xml.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]*)</string>`))?.[1];
}

async function dotenv(name: string): Promise<string | undefined> {
  if (Deno.env.get(name)) return Deno.env.get(name);
  try {
    for (const line of (await Deno.readTextFile(".env")).split("\n")) {
      const match = line.match(new RegExp(`^\\s*${name}\\s*=\\s*"?([^"\\n]*)"?\\s*$`));
      if (match) return match[1];
    }
  } catch {
    // No .env.
  }
  return undefined;
}

function axesLine(s: Series): string {
  return AXES.map((axis) => `${axis.slice(0, 4)} ${s.axes[axis] ?? "–"}`).join(" · ");
}

/// The project's URL and publishable key from the app's plist, and a signed-in
/// session: KOHI_SMOKE_JWT, or the test account in KOHI_SMOKE_EMAIL and
/// KOHI_SMOKE_PASSWORD (.env, git-ignored). Exits when there is none.
export async function session(): Promise<{ url: string; key: string; jwt: string }> {
  const xml = await Deno.readTextFile(PLIST);
  const url = plistValue(xml, "SUPABASE_URL") ?? "";
  const key = plistValue(xml, "SUPABASE_KEY") ?? "";
  if (!url || !key) {
    console.error(`${PLIST} has no SUPABASE_URL or SUPABASE_KEY`);
    Deno.exit(2);
  }
  let jwt = await dotenv("KOHI_SMOKE_JWT");
  const email = await dotenv("KOHI_SMOKE_EMAIL");
  const password = await dotenv("KOHI_SMOKE_PASSWORD");
  if (!jwt && email && password) {
    const response = await fetch(`${url}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: key },
      body: JSON.stringify({ email, password }),
    });
    const signedIn = await response.json().catch(() => ({}));
    if (!response.ok || typeof signedIn.access_token !== "string") {
      console.error(`Signing in KOHI_SMOKE_EMAIL failed (${response.status}).`);
      Deno.exit(2);
    }
    jwt = signedIn.access_token;
  }
  if (!jwt) {
    console.error("No session: set KOHI_SMOKE_EMAIL and KOHI_SMOKE_PASSWORD (a test account) or KOHI_SMOKE_JWT in .env.");
    Deno.exit(2);
  }
  return { url, key, jwt };
}

if (import.meta.main) {
  const path = Deno.args.find((arg) => !arg.startsWith("--"));
  const limit = Number(Deno.args.find((arg) => arg.startsWith("--limit="))?.split("=")[1] ?? 15);
  const dryRun = Deno.args.includes("--dry-run");
  // app (what the app gets: OpenAI first, Gemini as backup), gemini or openai
  // alone, or both side by side on the same facts.
  const asked = Deno.args.find((arg) => arg.startsWith("--provider="))?.split("=")[1] ?? "app";
  const providers: string[] = asked === "both" ? ["gemini", "openai"] : [asked];
  if (!path || !providers.every((p) => p === "app" || p === "gemini" || p === "openai")) {
    console.error("usage: scripts/compare-real.ts <tastings.json> [--limit=15] [--provider=app|gemini|openai|both] [--dry-run]");
    Deno.exit(2);
  }

  const wheel = JSON.parse(await Deno.readTextFile(WHEEL)) as { nodes: { id: string; en: string; level: number }[] };
  const labels = new Map(wheel.nodes.map((n) => [n.id, n.en]));
  // Only the leaves and their groups: "Fruity" or "Sweet" are words a
  // summary may use without naming a flavour.
  const wheelLabels = wheel.nodes.filter((n) => n.level >= 2).map((n) => n.en);

  const raw = JSON.parse(await Deno.readTextFile(path));
  const rows: Row[] = Array.isArray(raw) ? raw : raw.export ?? [];
  const tastings = rows.map((row) => tasting(row, labels));
  const comparisons = choose(tastings, limit);
  console.log(
    `${rows.length} tastings, ${tastings.filter((t) => Object.keys(t.series.axes).length >= MIN_AXES).length} with ${MIN_AXES}+ axes, ${comparisons.length} comparisons`,
  );

  let url = "", key = "", jwt: string | undefined;
  if (!dryRun) ({ url, key, jwt } = await session());

  const stamp = new Date().toISOString().slice(0, 16).replace(/[:T]/g, "-");
  const lines: string[] = [
    `# compare-summary on real tastings · ${stamp}`,
    "",
    `Source: ${path} · ${comparisons.length} comparisons · ${providers.join(" vs ")}`,
    "",
  ];
  type Total = { latencies: number[]; flagged: number; failed: number; input: number; output: number; models: Set<string> };
  const totals = new Map<string, Total>(
    providers.map((p) => [p, { latencies: [], flagged: 0, failed: 0, input: 0, output: 0, models: new Set() }]),
  );

  type Answer = { provider: string; status: number; ms: number; data: Record<string, unknown> };
  async function ask(series: Series[], provider: string): Promise<Answer> {
    const started = performance.now();
    try {
      const response = await fetch(`${url}/functions/v1/compare-summary`, {
        method: "POST",
        headers: { "Content-Type": "application/json", apikey: key, Authorization: `Bearer ${jwt}` },
        body: JSON.stringify(provider === "app" ? { series } : { series, provider }),
      });
      const data = await response.json().catch(() => ({}));
      return { provider, status: response.status, ms: Math.round(performance.now() - started), data };
    } catch (error) {
      return { provider, status: 0, ms: Math.round(performance.now() - started), data: { error: `${error}` } };
    }
  }

  for (const [index, pick] of comparisons.entries()) {
    const series = numbered(pick);
    const kind = series.length === 3 ? "trio" : distance(series[0], series[1]) < 2 ? "close pair" : "pair";
    lines.push(`## ${index + 1}. ${kind}`, "");
    for (const [i, s] of series.entries()) {
      lines.push(
        `- **No. ${s.number}** ${s.title} (${s.detail})${pick[i].origin ? ` — ${pick[i].origin}` : ""}`,
        `  ${axesLine(s)} · ${s.flavors.join(", ") || "no flavour"} · ${s.rating ?? "–"}★`,
      );
    }
    lines.push("");

    if (dryRun) {
      console.log(`${index + 1}. ${kind}: ${series.map((s) => `No. ${s.number} ${s.title}`).join(" / ")}`);
      continue;
    }

    // Both at once: the same moment, the same load, a fair latency.
    const answers = await Promise.all(providers.map((p) => ask(series, p)));
    if (answers.some((a) => a.status === 401)) {
      console.error("401: the session is refused (expired?). Stopping.");
      Deno.exit(1);
    }
    for (const { provider, status, ms, data } of answers) {
      const total = totals.get(provider)!;
      const label = providers.length > 1 ? `**${provider}** · ` : "";
      const summary = typeof data.summary === "string" ? data.summary : "";
      if (!summary) {
        total.failed++;
        lines.push(`> ${label}**No summary** · ${status} ${String(data.error ?? "")} · ${(ms / 1000).toFixed(1)} s`, "");
        console.log(`✗ ${index + 1}. ${kind} · ${provider} · ${status} ${String(data.error ?? "")}`);
        continue;
      }
      total.latencies.push(ms);
      total.models.add(String(data.model ?? "?"));
      total.input += Number(data.inputTokens ?? 0);
      total.output += Number(data.outputTokens ?? 0);
      const notes = checks(series, summary, wheelLabels);
      if (notes.length) total.flagged++;
      lines.push(`> ${label}${summary}`, "", `${String(data.model ?? "?")} · ${(ms / 1000).toFixed(1)} s`, "");
      for (const note of notes) lines.push(`- ⚠︎ ${note}`);
      if (notes.length) lines.push("");
      console.log(
        `${notes.length ? "⚠︎" : "✓"} ${index + 1}. ${kind} · ${provider} · ${(ms / 1000).toFixed(1)} s · ${String(data.model ?? "?")}${notes.length ? ` · ${notes.join("; ")}` : ""}`,
      );
    }
  }

  if (!dryRun) {
    const summaries: string[] = [];
    for (const [provider, total] of totals) {
      const sorted = [...total.latencies].sort((a, b) => a - b);
      const at = (q: number) => sorted.length ? (sorted[Math.min(sorted.length - 1, Math.floor(q * sorted.length))] / 1000).toFixed(1) : "–";
      summaries.push(
        `${provider}: ${comparisons.length - total.failed}/${comparisons.length} answered · ${total.flagged} flagged · median ${at(0.5)} s · p90 ${at(0.9)} s · ${total.input} in / ${total.output} out tokens · ${[...total.models].join(", ")}`,
      );
    }
    lines.splice(3, 0, ...summaries, "");
    console.log(`\n${summaries.join("\n")}`);
  }
  await Deno.mkdir(".private", { recursive: true });
  const out = `.private/compare-real-${stamp}${providers.length > 1 ? "-duel" : ""}${dryRun ? "-dry" : ""}.md`;
  await Deno.writeTextFile(out, lines.join("\n"));
  console.log(`report: ${out}`);
}
