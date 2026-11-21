// Runs every narration pipeline on the same notes and compares them.
//
//   SUPABASE_URL=https://<ref>.supabase.co SUPABASE_KEY=<publishable or user JWT> \
//     deno run --allow-read --allow-net --allow-env scripts/eval-narration.ts [case.json ...]
//
//   --archived            also pull the dictations kept in Supabase (needs
//                         SUPABASE_SERVICE_KEY, the secret key)
//   --pipelines=a,b       only these pipelines (default: all four)
//
// A fixture is scored only when its `audio` names a local m4a (relative to
// the case file). A step counts as heard when the action matches, the mass is
// within 2 g and the time within 3 s of one expected step not yet matched.
// The word error rate is shown when the case has a `transcript` it was
// checked against.

type Step = { at: number; action: string; mass?: number | null };
type Case = {
  name: string;
  confirmed?: boolean;
  audio?: string;
  water?: number;
  transcript?: string;
  phrases: { at: number; text: string }[];
  expected: Step[];
};
type Note = {
  name: string;
  audio: Uint8Array;
  duration: number;
  dose?: number;
  water?: number;
  method?: string;
  coffee?: string;
  phrases: { at: number; text: string }[];
  expected: Step[] | null;
  reference: string | null;
};
type Run = {
  pipeline: string;
  ok: boolean;
  failure?: string;
  model?: string;
  latencyMs: number;
  costUsd?: number | null;
  transcript?: string;
  steps?: Step[];
};

const PIPELINES = ["gemini-audio", "scribe+luna", "scribe+gemini", "openai+luna"];
const MASS_SLACK = 2;
const TIME_SLACK = 3;
const FIXTURES = new URL("../KohiTests/Fixtures/Dictations/", import.meta.url);

function same(a: Step, b: Step): boolean {
  const action = (s: Step) => (s.action === "drawdown" ? "wait" : s.action);
  if (action(a) !== action(b)) return false;
  if (Math.abs(a.at - b.at) > TIME_SLACK) return false;
  if (a.mass == null || b.mass == null) return a.mass == null && b.mass == null;
  return Math.abs(a.mass - b.mass) <= MASS_SLACK;
}

function score(heard: Step[], expected: Step[]) {
  const left = [...expected];
  let hits = 0;
  for (const step of heard) {
    const index = left.findIndex((e) => same(step, e));
    if (index >= 0) {
      hits++;
      left.splice(index, 1);
    }
  }
  return {
    precision: heard.length ? hits / heard.length : 0,
    recall: expected.length ? hits / expected.length : 1,
  };
}

const fold = (word: string) =>
  word.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^\p{L}\p{N}]/gu, "");

/// Word error rate: edits to turn the heard words into the reference, over
/// the length of the reference.
export function wer(heard: string, reference: string): number {
  const a = heard.split(/\s+/).map(fold).filter(Boolean);
  const b = reference.split(/\s+/).map(fold).filter(Boolean);
  if (!b.length) return a.length ? 1 : 0;
  let row = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    const next = [i];
    for (let j = 1; j <= b.length; j++) {
      next[j] = Math.min(row[j] + 1, next[j - 1] + 1, row[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
    row = next;
  }
  return row[b.length] / b.length;
}

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

const args = Deno.args.filter((arg) => !arg.startsWith("--"));
const archived = Deno.args.includes("--archived");
const only = Deno.args.find((arg) => arg.startsWith("--pipelines="))?.split("=")[1].split(",");
const pipelines = only ?? PIPELINES;

async function fixtures(): Promise<Note[]> {
  const files: URL[] = [];
  if (args.length) {
    files.push(...args.map((path) => new URL(path, `file://${Deno.cwd()}/`)));
  } else {
    for await (const entry of Deno.readDir(FIXTURES)) {
      if (entry.isFile && entry.name.endsWith(".json")) files.push(new URL(entry.name, FIXTURES));
    }
  }
  const notes: Note[] = [];
  for (const file of files.sort((a, b) => a.pathname.localeCompare(b.pathname))) {
    const set: Case = JSON.parse(await Deno.readTextFile(file));
    if (!set.audio) {
      console.log(`skip  ${set.name}: no audio`);
      continue;
    }
    notes.push({
      name: set.name + (set.confirmed ? "" : " (expected not confirmed)"),
      audio: await Deno.readFile(new URL(set.audio, file)),
      duration: set.phrases.at(-1)?.at ?? 0,
      water: set.water,
      phrases: set.phrases,
      expected: set.expected,
      reference: set.confirmed ? set.transcript ?? null : null,
    });
  }
  return notes;
}

async function dictations(url: string): Promise<Note[]> {
  const service = Deno.env.get("SUPABASE_SERVICE_KEY");
  if (!service) {
    console.error("--archived needs SUPABASE_SERVICE_KEY.");
    Deno.exit(1);
  }
  const headers = { apikey: service, Authorization: `Bearer ${service}` };
  const rows: {
    id: string;
    context: string;
    audio_path: string;
    duration_s: number;
    transcript: string;
    phrases: { at: number; text: string }[];
    edited_steps: Step[] | null;
    brew_context: { dose?: number; water?: number; method?: string; coffee?: string } | null;
    created_at: string;
  }[] = await (await fetch(
    `${url}/rest/v1/dictations?select=*&context=eq.live&order=created_at.desc&limit=50`,
    { headers },
  )).json();
  const notes: Note[] = [];
  for (const row of rows) {
    const response = await fetch(`${url}/storage/v1/object/dictations/${row.audio_path}`, { headers });
    if (!response.ok) continue;
    notes.push({
      name: `dictation ${row.id.slice(0, 8)} · ${row.created_at.slice(0, 16)} · ${Math.round(row.duration_s)} s`,
      audio: new Uint8Array(await response.arrayBuffer()),
      duration: row.duration_s,
      dose: row.brew_context?.dose,
      water: row.brew_context?.water,
      method: row.brew_context?.method,
      coffee: row.brew_context?.coffee,
      phrases: row.phrases,
      expected: row.edited_steps,
      reference: null,
    });
  }
  return notes;
}

async function hear(url: string, key: string, note: Note, pipeline: string): Promise<Run> {
  const started = Date.now();
  const response = await fetch(`${url}/functions/v1/brew-narration`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}`, apikey: key },
    body: JSON.stringify({
      audio: base64(note.audio),
      mime: "audio/mp4",
      pipeline,
      context: {
        dose: note.dose,
        water: note.water,
        method: note.method,
        coffee: note.coffee,
        duration: note.duration,
        phrases: note.phrases,
      },
    }),
  });
  const latencyMs = Date.now() - started;
  if (!response.ok) {
    return { pipeline, ok: false, failure: `${response.status} ${await response.text()}`, latencyMs };
  }
  const body = await response.json();
  if (body.pipeline !== pipeline) {
    return { pipeline, ok: false, failure: `failed, ${body.pipeline} answered`, latencyMs };
  }
  return {
    pipeline,
    ok: true,
    model: body.model,
    latencyMs: body.latencyMs ?? latencyMs,
    costUsd: body.costUsd,
    transcript: body.fields?.transcript ?? "",
    steps: body.fields?.steps ?? [],
  };
}

const url = Deno.env.get("SUPABASE_URL");
const key = Deno.env.get("SUPABASE_KEY");
if (!url || !key) {
  console.error("Set SUPABASE_URL and SUPABASE_KEY.");
  Deno.exit(1);
}

const notes = [...await fixtures(), ...(archived ? await dictations(url) : [])];
const totals = new Map<string, { runs: number; failed: number; ms: number[]; cost: number; wer: number[]; recall: number[] }>();
const pct = (value: number) => `${(value * 100).toFixed(0)}%`;

for (const note of notes) {
  console.log(`\n## ${note.name}`);
  console.log(
    `   set before: ${note.dose ?? "?"} g coffee, ${note.water ?? "?"} g water` +
      (note.coffee ? `, ${note.coffee}` : ""),
  );
  console.log(`   device: ${note.phrases.map((p) => p.text).join(" ").slice(0, 160)}`);
  const runs = await Promise.all(pipelines.map((pipeline) => hear(url, key, note, pipeline)));
  for (const run of runs) {
    const total = totals.get(run.pipeline) ?? { runs: 0, failed: 0, ms: [], cost: 0, wer: [], recall: [] };
    totals.set(run.pipeline, total);
    total.runs++;
    if (!run.ok) {
      total.failed++;
      console.log(`   ${run.pipeline.padEnd(14)} FAILED ${run.failure?.slice(0, 120)}`);
      continue;
    }
    total.ms.push(run.latencyMs);
    total.cost += run.costUsd ?? 0;
    const parts = [`${(run.latencyMs / 1000).toFixed(1)} s`, `$${(run.costUsd ?? 0).toFixed(4)}`, run.model ?? ""];
    if (note.reference != null) {
      const rate = wer(run.transcript ?? "", note.reference);
      total.wer.push(rate);
      parts.push(`WER ${pct(rate)}`);
    }
    if (note.expected?.length) {
      const result = score(run.steps ?? [], note.expected);
      total.recall.push(result.recall);
      parts.push(`steps ${pct(result.recall)} recall, ${pct(result.precision)} precision`);
    }
    console.log(`   ${run.pipeline.padEnd(14)} ${parts.join(" · ")}`);
    console.log(`   ${"".padEnd(14)} "${(run.transcript ?? "").slice(0, 160)}"`);
    console.log(
      `   ${"".padEnd(14)} ${
        (run.steps ?? []).map((s) => `${s.action}${s.mass != null ? ` ${s.mass}` : ""}@${s.at}`).join(", ") || "no step"
      }`,
    );
  }
}

const median = (values: number[]) => {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)];
};
const p95 = (values: number[]) => {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * 0.95) - 1)];
};
const mean = (values: number[]) => values.length ? values.reduce((a, b) => a + b, 0) / values.length : null;

console.log(`\n${notes.length} notes\n`);
console.log("pipeline        answered  p50 s  p95 s  $/note   WER   step recall");
for (const [pipeline, total] of totals) {
  const answered = total.runs - total.failed;
  const seconds = (ms: number | null) => (ms == null ? "  -  " : (ms / 1000).toFixed(1).padStart(5));
  const rate = mean(total.wer);
  const recall = mean(total.recall);
  console.log(
    [
      pipeline.padEnd(14),
      `${answered}/${total.runs}`.padStart(8),
      seconds(median(total.ms)),
      seconds(p95(total.ms)),
      (answered ? `$${(total.cost / answered).toFixed(4)}` : "-").padStart(7),
      (rate == null ? "-" : pct(rate)).padStart(5),
      (recall == null ? "-" : pct(recall)).padStart(12),
    ].join("  "),
  );
}
