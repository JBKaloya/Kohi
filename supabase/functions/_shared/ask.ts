// Rules of the ask function that do not need the network, kept apart so they
// can be tested.

export { type Provider, provider } from "./provider.ts";

export const PROMPT = `\
You answer coffee questions for Kohi.

You are given a curated knowledge base (sources). Use it when it covers the \
question, and cite those sources by id.

Rules, in order of importance:
1. If the sources cover the question, answer from them and set isCovered true. \
   Cite every source you used by id, in citations only.
2. If the sources do not cover it, but the question is about coffee, answer \
   from general coffee knowledge. Set isCovered false and tag "general". Do not \
   invent citations. Coffee includes brewing, grind, water, roast, taste, \
   equipment, recipes, and also the coffees themselves: origins, varieties, \
   farms, processing (washed, natural, honey, anaerobic, thermal shock, \
   fermentation), resting and storage.
3. If the question is not about coffee, refuse in one short sentence. Set \
   isCovered false and tag "off-topic".
4. The answer is read on its own. Never mention the sources, the base or what \
   they lack ("the provided sources do not..."), and never write a source id \
   or a bracket in the answer: the app lists the sources under it.
5. When sources disagree, say they disagree and give both readings.
6. Distinguish what is measured from what is common practice. Prefer confirming \
   what actually happened (Save what you did) before changing grind or ratio.
7. Answer the brewing method asked about: a pour-over question gets a \
   pour-over answer, even when the only source is about espresso.
8. When they are looking at a comparison, name the coffees by their number \
   ("No. 1") and use their scores and flavours.
9. Plain English, no marketing adjectives, no exclamation marks. Two short \
   paragraphs at most.`;

export const SCHEMA = {
  type: "OBJECT",
  properties: {
    answer: { type: "STRING" },
    isCovered: { type: "BOOLEAN" },
    citations: { type: "ARRAY", items: { type: "STRING" } },
    tag: { type: "STRING" },
  },
  required: ["answer", "isCovered"],
  propertyOrdering: ["answer", "isCovered", "citations", "tag"],
};

/// The same answer for OpenAI, as strict JSON Schema: every property
/// required, the tag null when the base covered the question.
export const OPENAI_SCHEMA = {
  type: "object",
  properties: {
    answer: { type: "string" },
    isCovered: { type: "boolean" },
    citations: { type: "array", items: { type: "string" } },
    tag: { type: ["string", "null"] },
  },
  required: ["answer", "isCovered", "citations", "tag"],
  additionalProperties: false,
};

/// Everything after the prompt, in the order the model reads it: the sources,
/// what the person is looking at (never a source), then the question.
export function input(sources: unknown[], context: string | undefined, question: string): string[] {
  return [
    `Sources:\n${JSON.stringify(sources)}`,
    ...(context ? [`What they are looking at (not a source):\n${context}`] : []),
    `Question: ${question}`,
  ];
}

/// An answer runs to two paragraphs and nobody else waits on it, so the
/// times are longer than the comparison summary's. OpenAI gets 15 s, about
/// five times its usual answer; the backup then gets 20 s.
export const OPENAI_FIRST_MS = 15_000;
export const BACKUP_MS = [20_000];
export const OPENAI_MS = 30_000;

/// Someone is waiting on screen. The primary gets 8 s: on 21 Nov 2026
/// gemini-3.8-flash answered none of its calls, timing out or returning 503,
/// and with the 25 s default every question waited 25 s before the fallback
/// answered. The fallback then gets 30 s.
export const ATTEMPT_MS = [8_000, 30_000];

/// The sources the answer cites, out of those it was given: an id the model
/// made up (OpenAI once wrote "f4-roast-tds-2020" for "f4-frost-roast-tds-2020")
/// is dropped, and an answer left with none is not covered by the base.
export function cited<S extends { id: string }>(
  parsed: Record<string, unknown>,
  sources: S[],
): { citations: string[]; sources: S[]; isCovered: boolean } {
  const ids = Array.isArray(parsed.citations) ? parsed.citations.filter((id): id is string => typeof id === "string") : [];
  const found = ids.flatMap((id) => sources.filter((s) => s.id === id));
  return {
    citations: found.map((s) => s.id),
    sources: found,
    isCovered: parsed.isCovered === true && found.length > 0,
  };
}

/// The model's JSON answer, or null when it is not an object: a reply cut
/// short or malformed is a failed call, not a crash of the function.
export function readAnswer(text: string | undefined): Record<string, unknown> | null {
  if (!text) return null;
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}
