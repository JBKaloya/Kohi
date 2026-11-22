// Coffee Intelligence's `ask`, on the questions testers ask, by Gemini and
// OpenAI side by side (docs/assistants-gemini-vs-openai.md).
//
//   deno run --allow-net --allow-read --allow-write --allow-env scripts/ask-duel.ts [--provider=app|gemini|openai|both]
//
// `both` (the default) sends each question to both providers at once, so they
// face the same moment and the same load. `app` sends what the app sends: no
// provider, so OpenAI first and Gemini as backup.
//
// Two of the questions are asked from a comparison of a tester's tastings
// (scores and flavours as they were, places left out), in the words the
// Compare screen hands to Ask (CompareSummary.context).
//
// Needs the session scripts/compare-real.ts uses (KOHI_SMOKE_EMAIL and
// KOHI_SMOKE_PASSWORD in .env). Writes .private/ask-duel-<stamp>.md: each
// answer, its sources, tag, model and latency, and checks a person would
// otherwise do by eye.

import { session } from "./compare-real.ts";

export type Question = {
  text: string;
  /// What the Compare screen hands to Ask, when it is asked from there.
  context?: string;
  /// What a good answer does: "covered" or "general" for a coffee question,
  /// "off-topic" when it should refuse.
  expect: "coffee" | "off-topic";
};

const COMPARISON = [
  "Comparing 2 coffees, numbered as on the radar (0 to 10 per axis):",
  "No. 1: Guatemala (café A · Oct); Acidity 6, Bitterness 5, Sweetness 7, Aroma 4, Aftertaste 5, Body 4, Clarity 4; rated 3 of 5",
  "No. 2: Gakuyuini (café B · Nov); Acidity 6, Bitterness 5, Sweetness 5, Aroma 4, Aftertaste 6, Body 5, Clarity 3; rated 3 of 5",
  "Summary shown: No. 1 is sweeter than No. 2.",
].join("\n");

const TRIO = [
  "Comparing 3 coffees, numbered as on the radar (0 to 10 per axis):",
  "No. 1: Giastes, (café C · Oct); Acidity 4, Bitterness 3, Sweetness 6, Aroma 4, Aftertaste 6, Body 6, Clarity 4; rated 3 of 5",
  "No. 2: Las Marias \"Gesha Rio Dulce\" (café B · Nov); Acidity 6, Bitterness 5, Sweetness 4, Aroma 6, Aftertaste 4, Body 5, Clarity 6; flavours: Apple, Orange, Lime, Peach; rated 5 of 5",
  "No. 3: ETHIOPIA CHELLE LIGHT ROAST (café D · Nov); Acidity 4, Bitterness 6, Sweetness 5, Aroma 3, Aftertaste 6, Body 5, Clarity 3; flavours: Brown Sugar, Cocoa, Vanillin; rated 3 of 5",
  "Summary shown: No. 3 is the most bitter and No. 1 the least, while No. 2 sits between them. No. 2 has the strongest aroma and rating, with apple and orange; No. 3 has brown sugar and cocoa.",
].join("\n");

export const QUESTIONS: Question[] = [
  { text: "Why does my V60 taste sour?", expect: "coffee" },
  { text: "My pour-over tastes bitter and dry. Should I grind coarser?", expect: "coffee" },
  { text: "What ratio should I use for a pour-over?", expect: "coffee" },
  { text: "How hot should the water be for a light roast?", expect: "coffee" },
  { text: "What does a washed process do to the taste compared with a natural?", expect: "coffee" },
  { text: "Is a thermal shock process the same as an anaerobic one?", expect: "coffee" },
  { text: "How long should I let beans rest after roasting?", expect: "coffee" },
  { text: "Does the bloom matter?", expect: "coffee" },
  { text: "What's a good recipe for a Kalita Wave with 15 g?", expect: "coffee" },
  { text: "Can you recommend a good ramen place in Shimokitazawa?", expect: "off-topic" },
  { text: "Why would No. 1 taste sweeter if both are washed?", context: COMPARISON, expect: "coffee" },
  { text: "Which of these would I brew for a friend who likes chocolate?", context: TRIO, expect: "coffee" },
];

export type Answer = {
  answer?: string;
  isCovered?: boolean;
  citations?: unknown[];
  sources?: { id: string; title: string }[];
  tag?: string | null;
};

/// What a reader would check by eye. Empty when nothing stands out.
export function checks(question: Question, answer: Answer): string[] {
  const notes: string[] = [];
  const text = answer.answer ?? "";
  const citations = Array.isArray(answer.citations) ? answer.citations : [];
  const sources = answer.sources ?? [];
  if (question.expect === "off-topic" && answer.tag !== "off-topic") notes.push("off-topic: answered instead of refusing");
  if (question.expect === "coffee" && answer.tag === "off-topic") notes.push("refused a coffee question");
  if (answer.isCovered && !citations.length) notes.push("covered but cites nothing");
  if (citations.length > sources.length) notes.push(`cites ${citations.length - sources.length} id(s) not in the sources`);
  if (!answer.isCovered && citations.length) notes.push("not covered, yet cites sources");
  const paragraphs = text.split(/\n\s*\n/).filter((p) => p.trim()).length;
  if (paragraphs > 2) notes.push(`${paragraphs} paragraphs, the prompt allows two`);
  const words = text.split(/\s+/).filter(Boolean).length;
  if (words > 180) notes.push(`${words} words`);
  if (/!/.test(text)) notes.push("exclamation mark");
  if (/\b(provided sources|the sources|knowledge base|the base)\b/i.test(text)) notes.push("talks about the sources");
  if (/\[[\w-]+(,\s*[\w-]+)*\]|【/.test(text)) notes.push("source id in the text");
  if (question.context && !/No\.\s?\d/.test(text)) notes.push("asked from a comparison, names no coffee by its number");
  return notes;
}

if (import.meta.main) {
  const asked = Deno.args.find((arg) => arg.startsWith("--provider="))?.split("=")[1] ?? "both";
  const providers: string[] = asked === "both" ? ["gemini", "openai"] : [asked];
  if (!providers.every((p) => p === "app" || p === "gemini" || p === "openai")) {
    console.error("usage: scripts/ask-duel.ts [--provider=app|gemini|openai|both]");
    Deno.exit(2);
  }
  const { url, key, jwt } = await session();

  type Total = { latencies: number[]; flagged: number; failed: number; covered: number; input: number; output: number; models: Set<string> };
  const totals = new Map<string, Total>(
    providers.map((p) => [p, { latencies: [], flagged: 0, failed: 0, covered: 0, input: 0, output: 0, models: new Set() }]),
  );
  const stamp = new Date().toISOString().slice(0, 16).replace(/[:T]/g, "-");
  const lines = [`# ask · ${stamp}`, "", `${QUESTIONS.length} questions · ${providers.join(" vs ")}`, ""];

  async function ask(question: Question, provider: string) {
    const started = performance.now();
    try {
      const body: Record<string, unknown> = { question: question.text };
      if (question.context) body.context = question.context;
      if (provider !== "app") body.provider = provider;
      const response = await fetch(`${url}/functions/v1/ask`, {
        method: "POST",
        headers: { "Content-Type": "application/json", apikey: key, Authorization: `Bearer ${jwt}` },
        body: JSON.stringify(body),
      });
      const data = await response.json().catch(() => ({}));
      return { provider, status: response.status, ms: Math.round(performance.now() - started), data };
    } catch (error) {
      return { provider, status: 0, ms: Math.round(performance.now() - started), data: { error: `${error}` } };
    }
  }

  for (const [index, question] of QUESTIONS.entries()) {
    lines.push(`## ${index + 1}. ${question.text}`, "");
    if (question.context) lines.push("Asked from Compare:", "", ...question.context.split("\n").map((l) => `    ${l}`), "");
    const answers = await Promise.all(providers.map((p) => ask(question, p)));
    if (answers.some((a) => a.status === 401)) {
      console.error("401: the session is refused (expired?). Stopping.");
      Deno.exit(1);
    }
    for (const { provider, status, ms, data } of answers) {
      const total = totals.get(provider)!;
      const label = providers.length > 1 ? `**${provider}** · ` : "";
      if (typeof data.answer !== "string" || !data.answer.trim()) {
        total.failed++;
        lines.push(`${label}**No answer** · ${status} ${String(data.error ?? "")} · ${(ms / 1000).toFixed(1)} s`, "");
        console.log(`✗ ${index + 1} · ${provider} · ${status} ${String(data.error ?? "")}`);
        continue;
      }
      total.latencies.push(ms);
      total.models.add(String(data.model ?? "?"));
      total.input += Number(data.inputTokens ?? 0);
      total.output += Number(data.outputTokens ?? 0);
      if (data.isCovered) total.covered++;
      const notes = checks(question, data as Answer);
      if (notes.length) total.flagged++;
      const cited = (data.sources ?? []).map((s: { title: string }) => s.title).join("; ") || "none";
      lines.push(
        `${label}${String(data.model ?? "?")} · ${(ms / 1000).toFixed(1)} s · ${data.isCovered ? "covered" : "not covered"} · tag ${data.tag ?? "–"} · sources: ${cited}`,
        "",
        ...String(data.answer).split("\n").map((l) => `> ${l}`),
        "",
      );
      for (const note of notes) lines.push(`- ⚠︎ ${note}`);
      if (notes.length) lines.push("");
      console.log(
        `${notes.length ? "⚠︎" : "✓"} ${index + 1} · ${provider} · ${(ms / 1000).toFixed(1)} s · ${String(data.model ?? "?")} · ${data.isCovered ? "covered" : (data.tag ?? "not covered")}${notes.length ? ` · ${notes.join("; ")}` : ""}`,
      );
    }
  }

  const summaries: string[] = [];
  for (const [provider, total] of totals) {
    const sorted = [...total.latencies].sort((a, b) => a - b);
    const at = (q: number) => sorted.length ? (sorted[Math.min(sorted.length - 1, Math.floor(q * sorted.length))] / 1000).toFixed(1) : "–";
    summaries.push(
      `${provider}: ${QUESTIONS.length - total.failed}/${QUESTIONS.length} answered · ${total.covered} from the base · ${total.flagged} flagged · median ${at(0.5)} s · p90 ${at(0.9)} s · ${total.input} in / ${total.output} out tokens · ${[...total.models].join(", ")}`,
    );
  }
  lines.splice(3, 0, ...summaries, "");
  console.log(`\n${summaries.join("\n")}`);
  await Deno.mkdir(".private", { recursive: true });
  const out = `.private/ask-duel-${stamp}.md`;
  await Deno.writeTextFile(out, lines.join("\n"));
  console.log(`report: ${out}`);
}
