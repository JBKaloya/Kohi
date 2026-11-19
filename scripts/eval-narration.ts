// Scores brew-narration against the dictation evaluation set.
//
//   SUPABASE_URL=https://<ref>.supabase.co SUPABASE_KEY=<publishable or user JWT> \
//     deno run --allow-read --allow-net --allow-env scripts/eval-narration.ts [case.json ...]
//
// A case is scored only when its `audio` names a local m4a (relative to the
// case file). A step counts as heard when the action matches, the mass is
// within 2 g and the time within 3 s of one expected step not yet matched.

type Step = { at: number; action: string; mass?: number | null };
type Case = {
  name: string;
  confirmed?: boolean;
  audio?: string;
  water?: number;
  phrases: { at: number; text: string }[];
  expected: Step[];
};

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
    missed: left,
  };
}

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

async function files(): Promise<URL[]> {
  if (Deno.args.length) return Deno.args.map((path) => new URL(path, `file://${Deno.cwd()}/`));
  const found: URL[] = [];
  for await (const entry of Deno.readDir(FIXTURES)) {
    if (entry.isFile && entry.name.endsWith(".json")) found.push(new URL(entry.name, FIXTURES));
  }
  return found.sort((a, b) => a.pathname.localeCompare(b.pathname));
}

const url = Deno.env.get("SUPABASE_URL");
const key = Deno.env.get("SUPABASE_KEY");
if (!url || !key) {
  console.error("Set SUPABASE_URL and SUPABASE_KEY.");
  Deno.exit(1);
}

let scored = 0;
let recall = 0;
let precision = 0;
for (const file of await files()) {
  const set: Case = JSON.parse(await Deno.readTextFile(file));
  const tag = set.confirmed ? "" : " (expected not confirmed)";
  if (!set.audio) {
    console.log(`skip  ${set.name}: no audio`);
    continue;
  }
  const audio = await Deno.readFile(new URL(set.audio, file));
  const started = Date.now();
  const response = await fetch(`${url}/functions/v1/brew-narration`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}`, apikey: key },
    body: JSON.stringify({
      audio: base64(audio),
      mime: "audio/mp4",
      context: { water: set.water, duration: set.phrases.at(-1)?.at },
    }),
  });
  if (!response.ok) {
    console.log(`fail  ${set.name}: ${response.status} ${await response.text()}`);
    continue;
  }
  const body = await response.json();
  const heard: Step[] = body.fields?.steps ?? [];
  const result = score(heard, set.expected);
  scored++;
  recall += result.recall;
  precision += result.precision;
  console.log(
    `${(result.recall * 100).toFixed(0).padStart(3)}%  ${set.name}${tag} · ` +
      `precision ${(result.precision * 100).toFixed(0)}% · ${Date.now() - started} ms`,
  );
  for (const step of result.missed) {
    console.log(`        missed ${step.action} ${step.mass ?? ""} @${step.at}`);
  }
}

if (scored) {
  console.log(
    `\n${scored} cases · recall ${(recall / scored * 100).toFixed(0)}% · ` +
      `precision ${(precision / scored * 100).toFixed(0)}%`,
  );
} else {
  console.log("\nNo case has audio yet. Add `audio` to a case to score it.");
}
