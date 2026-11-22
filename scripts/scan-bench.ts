// How well a coffee label is read, field by field, against what it really
// prints: the vision model (card-vision) on the card alone and on the card
// with its other sides, Gemini against OpenAI. The device's own read is
// measured by KohiTests/ScanBenchmarkTests on the same fixtures.
//
//   deno run --allow-net --allow-read --allow-write --allow-env scripts/scan-bench.ts [--provider=app|gemini|openai|both] [--only=<case>]
//
// `app` reads as the app does: OpenAI first, Gemini's light model as backup.
//
// Fixtures live in .private/scan-fixtures/ (git-ignored), one folder per coffee:
//
//   .private/scan-fixtures/dr-congo-majirane/
//     1.jpg            the photo a person scans first (the card, or the bag's front)
//     2.jpg, 3.jpg     other sides or pages, in the order they would be added
//     truth.json       what the coffee really prints, only the fields it prints:
//                      { "name": "Majirane", "roaster": "Process Coffee", "country": "DR Congo",
//                        "altitude": "1750", "producer": "Smallholders", "process": "Washed",
//                        "notes": ["Plum", "Molasses", "Liquorice"] }
//
// Writes .private/scan-bench-<stamp>.md: per case and per field, what each
// read gave and whether it matches; then per read, the share of fields right,
// fields wrong (a value that is not the truth, the worst case) and fields
// missed, notes recall, latency.

import { session } from "./compare-real.ts";

export const FIELDS = ["name", "roaster", "country", "region", "producer", "altitude", "variety", "process"] as const;
export type Field = typeof FIELDS[number];
export type Truth = Partial<Record<Field, string>> & { notes?: string[] };
export type Read = Partial<Record<Field, string>> & { notes?: string[] };

/// Case, accents, punctuation and spacing aside.
export function folded(text: string): string {
  return text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();
}

/// A read value matches when one contains the other once folded: "DR Congo"
/// and "Congo", "1750 masl" and "1750" are the same fact. An altitude matches
/// on its digits.
export function matches(field: Field, truth: string, read: string): boolean {
  if (field === "altitude") {
    // Every number the truth prints, read whole: 1750 is in "1750 masl", not in "175C".
    // "1,897M" is 1897: thousands separators go before reading the numbers.
    const numbers = (s: string): string[] => s.replace(/(\d)[,.\s](\d{3})(?!\d)/g, "$1$2").match(/\d+/g) ?? [];
    const printed = numbers(truth);
    return printed.length > 0 && printed.every((n) => numbers(read).includes(n));
  }
  const t = folded(truth), r = folded(read);
  return t !== "" && r !== "" && (t === r || t.includes(r) || r.includes(t));
}

export type Verdict = "right" | "wrong" | "missed" | "extra";

/// Each printed field: right, wrong (a value that is not the truth) or
/// missed. A field the truth does not print but the read filled is "extra".
export function judge(truth: Truth, read: Read): Record<Field, Verdict | null> & { notesRecall: number | null; notesNoise: number } {
  const verdicts = Object.fromEntries(FIELDS.map((field) => {
    const t = truth[field], r = read[field];
    if (!t) return [field, r ? "extra" : null];
    if (!r) return [field, "missed"];
    return [field, matches(field, t, r) ? "right" : "wrong"];
  })) as Record<Field, Verdict | null>;
  const truthNotes = (truth.notes ?? []).map(folded);
  const readNotes = (read.notes ?? []).map(folded);
  const found = truthNotes.filter((t) => readNotes.some((r) => r === t || r.includes(t) || t.includes(r)));
  const noise = readNotes.filter((r) => !truthNotes.some((t) => r === t || r.includes(t) || t.includes(r)));
  return {
    ...verdicts,
    notesRecall: truthNotes.length ? found.length / truthNotes.length : null,
    notesNoise: noise.length,
  };
}

/// card-vision's answer as a read.
export function fromVision(data: Record<string, unknown>): Read {
  const read: Read = {};
  for (const field of FIELDS) {
    const value = data[field];
    if (typeof value === "string" && value.trim()) read[field] = value.trim();
  }
  if (Array.isArray(data.tastingNotes)) read.notes = data.tastingNotes.filter((n): n is string => typeof n === "string");
  return read;
}

if (import.meta.main) {
  const asked = Deno.args.find((arg) => arg.startsWith("--provider="))?.split("=")[1] ?? "both";
  const only = Deno.args.find((arg) => arg.startsWith("--only="))?.split("=")[1];
  const providers = asked === "both" ? ["gemini", "openai"] : [asked];
  const root = ".private/scan-fixtures";

  const cases: { name: string; photos: string[]; truth: Truth }[] = [];
  for await (const entry of Deno.readDir(root)) {
    if (!entry.isDirectory || (only && entry.name !== only)) continue;
    const dir = `${root}/${entry.name}`;
    let truth: Truth;
    try {
      truth = JSON.parse(await Deno.readTextFile(`${dir}/truth.json`));
    } catch {
      console.error(`${entry.name}: no truth.json, skipped`);
      continue;
    }
    const photos: string[] = [];
    for await (const file of Deno.readDir(dir)) {
      if (/^\d+\.(jpe?g|png|heic)$/i.test(file.name)) photos.push(`${dir}/${file.name}`);
    }
    photos.sort((a, b) => parseInt(a.split("/").pop()!) - parseInt(b.split("/").pop()!));
    if (photos.length) cases.push({ name: entry.name, photos, truth });
  }
  cases.sort((a, b) => a.name.localeCompare(b.name));
  if (!cases.length) {
    console.error(`No fixture in ${root}: one folder per coffee with 1.jpg (and 2.jpg…) and truth.json.`);
    Deno.exit(2);
  }

  const { url, key, jwt } = await session();
  const toBase64 = (bytes: Uint8Array) => {
    let binary = "";
    for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    return btoa(binary);
  };
  const mime = (path: string) => /\.png$/i.test(path) ? "image/png" : /\.heic$/i.test(path) ? "image/heic" : "image/jpeg";

  type Run = { label: string; provider: string; photos: number };
  const runs: Run[] = providers.flatMap((provider) => [
    { label: `${provider} · card`, provider, photos: 1 },
    { label: `${provider} · every side`, provider, photos: 4 },
  ]);
  const tally = new Map(runs.map((r) => [r.label, { right: 0, wrong: 0, missed: 0, extra: 0, recall: [] as number[], noise: 0, ms: [] as number[], failed: 0 }]));

  const stamp = new Date().toISOString().slice(0, 16).replace(/[:T]/g, "-");
  const lines = [`# Scan benchmark · ${stamp}`, "", `${cases.length} coffees · ${runs.map((r) => r.label).join(", ")}`, ""];

  for (const c of cases) {
    const images = await Promise.all(c.photos.map(async (p) => ({ image: toBase64(await Deno.readFile(p)), mime: mime(p) })));
    lines.push(`## ${c.name} (${c.photos.length} photo${c.photos.length > 1 ? "s" : ""})`, "");
    const header = ["field", "truth", ...runs.filter((r) => r.photos === 1 || c.photos.length > 1).map((r) => r.label)];
    const rows: string[][] = [];
    const reads: { run: Run; read: Read | null; ms: number; error: string | null }[] = [];
    await Promise.all(runs.map(async (run) => {
      if (run.photos > 1 && c.photos.length === 1) return;
      const started = performance.now();
      const response = await fetch(`${url}/functions/v1/card-vision`, {
        method: "POST",
        headers: { "Content-Type": "application/json", apikey: key, Authorization: `Bearer ${jwt}` },
        body: JSON.stringify({ images: images.slice(0, run.photos), provider: run.provider }),
      });
      const data = await response.json().catch(() => ({}));
      reads.push({
        run,
        read: response.ok ? fromVision(data) : null,
        ms: Math.round(performance.now() - started),
        // Why it failed, as the function says it: "vision model returned 503".
        error: response.ok ? null : String(data.error ?? `HTTP ${response.status}`),
      });
    }));
    reads.sort((a, b) => runs.indexOf(a.run) - runs.indexOf(b.run));

    for (const field of [...FIELDS, "notes"] as const) {
      const truth = field === "notes" ? (c.truth.notes ?? []).join(", ") : c.truth[field] ?? "";
      const cells = reads.map(({ read, error }) => {
        if (!read) return `✗ failed (${error})`;
        const value = field === "notes" ? (read.notes ?? []).join(", ") : read[field] ?? "";
        if (field === "notes") return value || "–";
        const verdict = judge(c.truth, read)[field];
        const mark = verdict === "right" ? "✓" : verdict === "wrong" ? "✗" : verdict === "missed" ? "∅" : verdict === "extra" ? "+" : "";
        return `${mark} ${value || "–"}`.trim();
      });
      if (truth || cells.some((cell) => !cell.endsWith("–"))) rows.push([field, truth || "–", ...cells]);
    }
    lines.push(`| ${header.join(" | ")} |`, `|${header.map(() => "---").join("|")}|`, ...rows.map((r) => `| ${r.join(" | ")} |`), "");
    lines.push(reads.map(({ run, ms, read, error }) => `${run.label}: ${read ? `${(ms / 1000).toFixed(1)} s` : `failed (${error})`}`).join(" · "), "");

    for (const { run, read, ms } of reads) {
      const t = tally.get(run.label)!;
      if (!read) {
        t.failed++;
        continue;
      }
      const verdict = judge(c.truth, read);
      for (const field of FIELDS) {
        const v = verdict[field];
        if (v) t[v]++;
      }
      if (verdict.notesRecall !== null) t.recall.push(verdict.notesRecall);
      t.noise += verdict.notesNoise;
      t.ms.push(ms);
    }
    console.log(`${c.name}: ${reads.map(({ run, read, error }) => `${run.label} ${read ? "ok" : `failed (${error})`}`).join(", ")}`);
  }

  const summary = ["| read | right | wrong | missed | extra | notes found | stray notes | median | failed |", "|---|---|---|---|---|---|---|---|---|"];
  for (const [label, t] of tally) {
    const printed = t.right + t.wrong + t.missed;
    const pct = (n: number) => printed ? `${Math.round((100 * n) / printed)} %` : "–";
    const sorted = [...t.ms].sort((a, b) => a - b);
    const median = sorted.length ? `${(sorted[Math.floor(sorted.length / 2)] / 1000).toFixed(1)} s` : "–";
    const recall = t.recall.length ? `${Math.round((100 * t.recall.reduce((a, b) => a + b, 0)) / t.recall.length)} %` : "–";
    summary.push(`| ${label} | ${pct(t.right)} | ${pct(t.wrong)} | ${pct(t.missed)} | ${t.extra} | ${recall} | ${t.noise} | ${median} | ${t.failed} |`);
  }
  lines.splice(4, 0, ...summary, "", "✓ right · ✗ wrong (a value that is not printed) · ∅ missed · + filled though not printed", "");
  console.log(`\n${summary.join("\n")}`);
  const out = `.private/scan-bench-${stamp}.md`;
  await Deno.writeTextFile(out, lines.join("\n"));
  console.log(`report: ${out}`);
}
