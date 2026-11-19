// What testers said when they compared the readings of their Live notes.
//
//   SUPABASE_URL=https://<ref>.supabase.co SUPABASE_SERVICE_KEY=<secret key> \
//     deno run --allow-net --allow-env scripts/narration-trials-report.ts [--since=2026-11-19]
//
// Per dictator, then for everyone: for each pipeline, how often it was
// picked when it was shown, how often a trial had none right, how much of
// the pick survived to the steps kept at save (same action, mass within 2 g,
// time within 3 s), latency and cost. Then every comment.

type Step = { at: number; action: string; mass?: number | null };
type Candidate = {
  pipeline: string;
  ok: boolean;
  model: string;
  steps: Step[];
  latency_ms: number;
  cost_usd?: number | null;
  failure?: string | null;
};
type Trial = {
  id: string;
  user_id: string;
  dictation_id: string | null;
  candidates: Candidate[];
  chosen: string | null;
  none_right: boolean;
  skipped: boolean;
  comment: string;
  app_build: string | null;
  created_at: string;
};

const url = Deno.env.get("SUPABASE_URL");
const key = Deno.env.get("SUPABASE_SERVICE_KEY");
if (!url || !key) {
  console.error("Set SUPABASE_URL and SUPABASE_SERVICE_KEY.");
  Deno.exit(1);
}
const headers = { apikey: key, Authorization: `Bearer ${key}` };
const since = Deno.args.find((arg) => arg.startsWith("--since="))?.split("=")[1];

async function get<T>(path: string): Promise<T> {
  const response = await fetch(`${url}${path}`, { headers });
  if (!response.ok) throw new Error(`${path}: ${response.status} ${await response.text()}`);
  return await response.json();
}

const trials = await get<Trial[]>(
  `/rest/v1/narration_trials?select=*&order=created_at.asc${since ? `&created_at=gte.${since}` : ""}`,
);
const dictationIDs = [...new Set(trials.map((t) => t.dictation_id).filter(Boolean))];
const kept = new Map<string, Step[] | null>();
if (dictationIDs.length) {
  const rows = await get<{ id: string; edited_steps: Step[] | null }[]>(
    `/rest/v1/dictations?select=id,edited_steps&id=in.(${dictationIDs.join(",")})`,
  );
  for (const row of rows) kept.set(row.id, row.edited_steps);
}

const names = new Map<string, string>();
try {
  const { users } = await get<{ users: { id: string; email?: string }[] }>("/auth/v1/admin/users?per_page=200");
  for (const user of users) names.set(user.id, user.email ?? user.id.slice(0, 8));
} catch {
  // Ids are enough to tell two testers apart.
}

function same(a: Step, b: Step): boolean {
  const action = (s: Step) => (s.action === "drawdown" ? "wait" : s.action);
  if (action(a) !== action(b)) return false;
  if (Math.abs(a.at - b.at) > 3) return false;
  if (a.mass == null || b.mass == null) return a.mass == null && b.mass == null;
  return Math.abs(a.mass - b.mass) <= 2;
}

/// Share of the picked steps found unchanged in the steps kept at save.
function survived(picked: Step[], final: Step[]): number {
  if (!picked.length) return final.length ? 0 : 1;
  const left = [...final];
  let hits = 0;
  for (const step of picked) {
    const index = left.findIndex((s) => same(step, s));
    if (index >= 0) {
      hits++;
      left.splice(index, 1);
    }
  }
  return hits / Math.max(picked.length, final.length);
}

const pct = (value: number | null) => (value == null ? "-" : `${Math.round(value * 100)}%`);
const quantile = (values: number[], q: number) => {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * q) - 1)];
};
const seconds = (ms: number | null) => (ms == null ? "-" : (ms / 1000).toFixed(1));
const mean = (values: number[]) => (values.length ? values.reduce((a, b) => a + b, 0) / values.length : null);

function report(title: string, set: Trial[]) {
  const answered = set.filter((t) => !t.skipped);
  console.log(`\n## ${title}`);
  console.log(
    `${set.length} trials · ${answered.length} answered · ${set.length - answered.length} skipped · ` +
      `${answered.filter((t) => t.none_right).length} with none right`,
  );
  const pipelines = [...new Set(set.flatMap((t) => t.candidates.map((c) => c.pipeline)))].sort();
  console.log("\npipeline        shown  picked  win    answered  p50 s  p95 s  $/note   kept at save");
  for (const pipeline of pipelines) {
    const shown = answered.filter((t) => t.candidates.some((c) => c.pipeline === pipeline));
    const runs = set.flatMap((t) => t.candidates.filter((c) => c.pipeline === pipeline));
    const ok = runs.filter((c) => c.ok);
    const picked = shown.filter((t) => t.chosen === pipeline);
    const survival = picked.flatMap((t) => {
      const final = t.dictation_id ? kept.get(t.dictation_id) : null;
      const pick = t.candidates.find((c) => c.pipeline === pipeline);
      return final && pick ? [survived(pick.steps, final)] : [];
    });
    const latency = pipeline === "device" ? [] : ok.map((c) => c.latency_ms);
    const cost = mean(ok.map((c) => c.cost_usd ?? 0));
    console.log(
      [
        pipeline.padEnd(14),
        String(shown.length).padStart(5),
        String(picked.length).padStart(6),
        pct(shown.length ? picked.length / shown.length : null).padStart(5),
        `${ok.length}/${runs.length}`.padStart(8),
        seconds(quantile(latency, 0.5)).padStart(5),
        seconds(quantile(latency, 0.95)).padStart(5),
        (cost == null || pipeline === "device" ? "-" : `$${cost.toFixed(4)}`).padStart(7),
        pct(mean(survival)).padStart(13),
      ].join("  "),
    );
  }
  const failures = set.flatMap((t) => t.candidates.filter((c) => !c.ok).map((c) => `${c.pipeline}: ${c.failure}`));
  if (failures.length) {
    console.log("\nfailures");
    for (const failure of failures) console.log(`  ${failure.slice(0, 140)}`);
  }
  const comments = set.filter((t) => t.comment);
  if (comments.length) {
    console.log("\ncomments");
    for (const trial of comments) {
      const pick = trial.none_right ? "none right" : trial.chosen ?? "skipped";
      console.log(`  ${trial.created_at.slice(0, 16)} [${pick}] ${trial.comment}`);
    }
  }
}

if (!trials.length) {
  console.log("No trial yet.");
  Deno.exit(0);
}
const byUser = Map.groupBy(trials, (t) => t.user_id);
for (const [user, set] of byUser) report(names.get(user) ?? user.slice(0, 8), set);
if (byUser.size > 1) report("Everyone", trials);
