// Smoke test for the AI edge functions behind the comparison: compare-summary
// and ask, called on the deployed project the way the app calls them.
//
//   deno run --allow-net --allow-read --allow-env scripts/smoke-ai.ts [runs]
//
// The project URL and its publishable key come from Kohi/Resources/Supabase.plist,
// the same file the app reads; neither is ever printed. A session JWT, when
// KOHI_SMOKE_JWT is set (environment or .env, gitignored), is sent the way the
// signed-in app sends it.
//
// The first cases check that a call with no session is refused, by every AI
// function: with the publishable key alone, with that key sent as a bearer,
// and with a made-up session token. On 21 Nov 2026 they were not: every
// function ran on the publishable key alone. Those calls send `{}` (a full
// body for compare-summary, the one that answered), so an unguarded function
// still stops at its own validation and never reaches a model.
//
// The cases that need a session run only with KOHI_SMOKE_JWT; without it
// they are skipped rather than sent through the hole they test for.
//
// Each case prints its status, latency and the model that answered. `runs`
// (default 3) repeats the summary call to see the usual latency, not one draw.

const PLIST = "Kohi/Resources/Supabase.plist";
const SLOW_MS = 8_000;

function plistValue(xml: string, key: string): string | undefined {
  const match = xml.match(new RegExp(`<key>${key}</key>\\s*<string>([^<]*)</string>`));
  return match?.[1];
}

async function dotenv(name: string): Promise<string | undefined> {
  if (Deno.env.get(name)) return Deno.env.get(name);
  try {
    const text = await Deno.readTextFile(".env");
    for (const line of text.split("\n")) {
      const match = line.match(new RegExp(`^\\s*${name}\\s*=\\s*"?([^"\\n]*)"?\\s*$`));
      if (match) return match[1];
    }
  } catch {
    // No .env: the session checks are skipped.
  }
  return undefined;
}

const xml = await Deno.readTextFile(PLIST);
const url = plistValue(xml, "SUPABASE_URL");
const key = plistValue(xml, "SUPABASE_KEY");
if (!url || !key) {
  console.error(`${PLIST} has no SUPABASE_URL or SUPABASE_KEY`);
  Deno.exit(2);
}
const jwt = await dotenv("KOHI_SMOKE_JWT");
const runs = Number(Deno.args[0] ?? 3);

type Row = { name: string; expected: string; status: number | string; ms: number; model: string; note: string; ok: boolean };
const rows: Row[] = [];

// A token shaped like a session, signed by nobody.
function forged(): string {
  const part = (value: unknown) =>
    btoa(JSON.stringify(value)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const claims = { sub: crypto.randomUUID(), role: "authenticated", aud: "authenticated", exp: Math.floor(Date.now() / 1000) + 3600 };
  return `${part({ alg: "ES256", typ: "JWT", kid: "smoke" })}.${part(claims)}.${part("not a signature")}`;
}

async function call(
  fn: string,
  body: string,
  auth: "session" | "none" | "publishable" | "forged",
): Promise<{ status: number; ms: number; data: Record<string, unknown> }> {
  const headers: Record<string, string> = { "Content-Type": "application/json", apikey: key! };
  if (auth === "session" && jwt) headers.Authorization = `Bearer ${jwt}`;
  if (auth === "publishable") headers.Authorization = `Bearer ${key}`;
  if (auth === "forged") headers.Authorization = `Bearer ${forged()}`;
  const started = performance.now();
  const response = await fetch(`${url}/functions/v1/${fn}`, { method: "POST", headers, body });
  const ms = Math.round(performance.now() - started);
  let data: Record<string, unknown> = {};
  try {
    data = await response.json();
  } catch {
    // An error page, not JSON: the status says enough.
  }
  return { status: response.status, ms, data };
}

const kenya = {
  number: 1,
  title: "Kenya Kiambu AA",
  detail: "Glitch · 12 Nov",
  axes: { acidity: 9, bitterness: 2, sweetness: 5, aroma: 8, aftertaste: 6, body: 3, clarity: 8 },
  flavors: ["Blackcurrant", "Grapefruit", "Black tea"],
  rating: 4.5,
};
const brazil = {
  number: 2,
  title: "Brazil Cerrado",
  detail: "Onibus · 14 Nov",
  axes: { acidity: 3, bitterness: 5, sweetness: 8, aroma: 5, aftertaste: 5, body: 8, clarity: 5 },
  flavors: ["Chocolate", "Hazelnut"],
  rating: 3.5,
};
const ethiopia = {
  number: 3,
  title: "Ethiopia Guji",
  detail: "Leaves · 18 Nov",
  axes: { acidity: 7, bitterness: 2, sweetness: 7, aroma: 9, aftertaste: 7, body: 4, clarity: 9 },
  flavors: ["Jasmine", "Peach", "Bergamot"],
  rating: 5,
};

function record(name: string, expected: string, result: { status: number; ms: number; data: Record<string, unknown> }, ok: boolean, note = "") {
  rows.push({
    name,
    expected,
    status: result.status,
    ms: result.ms,
    model: String(result.data.model ?? "-"),
    note,
    ok,
  });
}

// No session: every function refuses before it reads the body.
const FUNCTIONS = [
  "ask",
  "compare-summary",
  "card-vision",
  "field-extract",
  "recipe-adapt",
  "suggested-correction",
  "brew-narration",
  "narration-compare",
];
{
  const result = await call("compare-summary", JSON.stringify({ series: [kenya, brazil] }), "none");
  record(
    "compare-summary, no session",
    "401",
    result,
    result.status === 401,
    result.status === 401 ? "" : "runs without a session",
  );
}
for (const fn of FUNCTIONS) {
  for (const auth of ["none", "publishable", "forged"] as const) {
    if (fn === "compare-summary" && auth === "none") continue;
    const result = await call(fn, "{}", auth);
    const label = { none: "no session", publishable: "key as bearer", forged: "forged session" }[auth];
    record(`${fn}, ${label}`, "401", result, result.status === 401, result.status === 401 ? "" : "runs without a session");
  }
}

function skip(name: string, expected: string) {
  rows.push({ name, expected, status: "skipped", ms: 0, model: "-", note: "no KOHI_SMOKE_JWT", ok: true });
}

if (!jwt) {
  skip("compare-summary, 2 series", "200 · No. 1/2 · < 8 s");
  skip("compare-summary, 3 series", "200 · No. 1/2/3");
  skip("compare-summary, 1 series", "400");
  skip("compare-summary, not JSON", "400");
  skip("ask, no context", "200 · answer");
  skip("ask, with context", "200 · answer uses it");
} else {
  for (let run = 1; run <= runs; run++) {
    const result = await call("compare-summary", JSON.stringify({ series: [kenya, brazil] }), "session");
    const summary = String(result.data.summary ?? "");
    const named = summary.includes("No. 1") && summary.includes("No. 2");
    const ok = result.status === 200 && named && result.ms < SLOW_MS;
    record(`compare-summary, 2 series #${run}`, "200 · No. 1/2 · < 8 s", result, ok, summary || String(result.data.error ?? ""));
  }
  {
    const result = await call("compare-summary", JSON.stringify({ series: [kenya, brazil, ethiopia] }), "session");
    const summary = String(result.data.summary ?? "");
    const ok = result.status === 200 && ["No. 1", "No. 2", "No. 3"].every((n) => summary.includes(n));
    record("compare-summary, 3 series", "200 · No. 1/2/3", result, ok, summary || String(result.data.error ?? ""));
  }
  {
    const result = await call("compare-summary", JSON.stringify({ series: [kenya] }), "session");
    record("compare-summary, 1 series", "400", result, result.status === 400, String(result.data.error ?? ""));
  }
  {
    const result = await call("compare-summary", "not json", "session");
    record("compare-summary, not JSON", "400", result, result.status === 400, String(result.data.error ?? ""));
  }
  {
    const result = await call("ask", JSON.stringify({ question: "What does a longer bloom change?" }), "session");
    const answer = String(result.data.answer ?? "");
    record("ask, no context", "200 · answer", result, result.status === 200 && answer.length > 0, answer.slice(0, 120));
  }
  {
    const context = [
      "Comparing 2 coffees, numbered as on the radar (0 to 10 per axis):",
      "No. 1: Kenya Kiambu AA; Acidity 9, Body 3; flavours: Blackcurrant, Grapefruit",
      "No. 2: Brazil Cerrado; Acidity 3, Body 8; flavours: Chocolate, Hazelnut",
    ].join("\n");
    const result = await call(
      "ask",
      JSON.stringify({ question: "Which of the two should I order if I like sweet, round cups?", context }),
      "session",
    );
    const answer = String(result.data.answer ?? "");
    const usesIt = /No\. ?2|Brazil/i.test(answer);
    record("ask, with context", "200 · answer uses it", result, result.status === 200 && usesIt, answer.slice(0, 120));
  }
}

console.log("");
for (const row of rows) {
  const mark = row.status === "skipped" ? "–" : row.ok ? "✓" : "✗";
  const ms = row.status === "skipped" ? "" : `${(row.ms / 1000).toFixed(1)} s`;
  console.log(`${mark} ${row.name.padEnd(42)} ${String(row.status).padEnd(8)} ${ms.padStart(7)}  ${row.model.padEnd(24)} expect ${row.expected}`);
  if (row.note) console.log(`    ${row.note}`);
}
const failed = rows.filter((row) => !row.ok).length;
console.log(`\n${failed ? `${failed} failed` : "all passed"}${jwt ? "" : " (no KOHI_SMOKE_JWT: the session cases were skipped)"}`);
Deno.exit(failed ? 1 : 0);
