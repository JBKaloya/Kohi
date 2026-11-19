// Reads the steps of a brew from a timed transcript.
//
// The transcript comes from a speech-to-text model that gives the second
// each word was said, so a step's time is read, not guessed. When the model
// gives no timings, `estimate` places the words from what the device heard.

import type { Word } from "./stt.ts";

export type Phrase = { at: number; text: string };

export type Context = {
  method?: string;
  dose?: number;
  water?: number;
  duration?: number;
  recipe?: string[];
  vocabulary?: string[];
  /// What Speech heard on the device, word by word or phrase by phrase.
  phrases?: Phrase[];
};

export function describe(context: Context): string {
  const lines: string[] = [];
  if (context.method) lines.push(`Method: ${context.method}`);
  if (context.dose) lines.push(`Dose: ${context.dose} g`);
  if (context.water) lines.push(`Water: ${context.water} g`);
  if (context.duration) lines.push(`Recording length: ${Math.round(context.duration)} s`);
  if (context.recipe?.length) lines.push(`Recipe followed: ${context.recipe.join("; ")}`);
  if (context.vocabulary?.length) lines.push(`Vocabulary: ${context.vocabulary.join(", ")}`);
  return lines.join("\n");
}

export const ACTIONS = [
  "bloom", "pour", "swirl", "stir", "wait", "drawdown", "press", "steep", "rinse",
] as const;

/// The rules a step follows, shared by the audio prompt and the text one.
export const STEP_RULES = `\
Steps:
- action is one of: bloom, pour, swirl, stir, wait, drawdown, press, steep, \
  rinse. Nothing else.
- mass is the scale reading in grams after the step, so it always grows: \
  "bloom 40" then "encore 100" is 40 then 140. Null when no mass was said, \
  and always null for wait, drawdown, swirl and stir.
- A pattern describes several steps: "je verse par palier de 40, j'attends \
  20 secondes entre chaque, jusqu'à 200", said at 8 s after a 40 g bloom, is \
  four pours: 80 at 8, 120 at 28, 160 at 48, 200 at 68. Each pour has its own \
  at, the interval apart, even though it was all said at once. The waits \
  between the pours of a pattern are not steps. When no target is said, the \
  pattern ends on the water from the context.
- "Ça draine", "drawdown", "it's draining" is a drawdown at that second.
- A time spoken as a wait ("j'attends 20 secondes") is never a mass.
- note carries what was said about the step that is not its action or its \
  mass ("plus lent", "en spirale"), verbatim. Empty otherwise.
- Do not add a step that was not said. Small talk is not a step.

dose and water are grams, only when spoken. seconds is the total brew time, \
only when spoken.`;

export const INTERPRET_PROMPT = `\
You read the transcript of someone narrating a coffee brew out loud while \
they make it, in French or English. The recording starts when the brew \
starts, so a time in the transcript is the time in the brew.

Each line is "[second] words", the second the line began at. The transcript \
was written by a speech model: a word that sounds like a coffee term from \
the vocabulary probably is one.

Return the brew steps the narration describes, in order.
- at is the second at which the step was said: the second of its line, or \
  later in the line when the step is said at its end. Never a number the \
  speaker said.

${STEP_RULES}`;

export const ESTIMATED_NOTE = `\
The seconds of this transcript are estimated from a rougher transcript and \
can be a few seconds off; keep the order they give.`;

/// Lines for the prompt: a new one after a sentence ends, a pause, or a
/// dozen words, so a step said mid-line is never far from its second.
export function timedLines(words: Word[]): string {
  const lines: string[] = [];
  let current: Word[] = [];
  const flush = () => {
    if (!current.length) return;
    lines.push(`[${current[0].start.toFixed(1)}] ${current.map((w) => w.w).join(" ")}`);
    current = [];
  };
  for (const [index, word] of words.entries()) {
    const previous = words[index - 1];
    if (
      previous && current.length &&
      (/[.?!]$/.test(previous.w) || word.start - previous.end > 1 || current.length >= 12)
    ) flush();
    current.push(word);
  }
  flush();
  return lines.join("\n");
}

/// Sentences with the second they began at, for the app's transcript view.
export function utterances(words: Word[]): Phrase[] {
  const result: Phrase[] = [];
  let current: Word[] = [];
  const flush = () => {
    if (!current.length) return;
    result.push({ at: current[0].start, text: current.map((w) => w.w).join(" ") });
    current = [];
  };
  for (const word of words) {
    current.push(word);
    if (/[.?!]$/.test(word.w)) flush();
  }
  flush();
  return result;
}

const fold = (text: string) =>
  text.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^\p{L}\p{N}]/gu, "");

/// Speech rate used past the last word the device placed.
const WORDS_PER_SECOND = 2.5;
/// How far ahead a device word may find its match in the transcript.
const LOOKAHEAD = 30;

/// Places the words of an untimed transcript: each word the device also
/// heard takes the device's second, the others are spread between them.
export function estimate(text: string, phrases: Phrase[], duration: number): Word[] {
  const tokens = text.split(/\s+/).filter(Boolean);
  if (!tokens.length) return [];
  const folded = tokens.map(fold);
  const device = phrases.flatMap((phrase) =>
    phrase.text.split(/\s+/).filter(Boolean).map((word) => ({ at: phrase.at, w: fold(word) }))
  );

  const anchors = new Map<number, number>();
  let cursor = 0;
  for (const heard of device) {
    if (!heard.w) continue;
    const limit = Math.min(tokens.length, cursor + LOOKAHEAD);
    for (let index = cursor; index < limit; index++) {
      if (folded[index] === heard.w) {
        const last = [...anchors.values()].at(-1) ?? -Infinity;
        if (heard.at >= last) anchors.set(index, heard.at);
        cursor = index + 1;
        break;
      }
    }
  }

  const end = duration > 0 ? duration : tokens.length / WORDS_PER_SECOND;
  const times = new Array<number>(tokens.length);
  const known = [...anchors.entries()].sort((a, b) => a[0] - b[0]);
  if (!known.length) {
    const step = end / (tokens.length + 1);
    tokens.forEach((_, index) => (times[index] = step * (index + 1)));
  } else {
    const [firstIndex, firstAt] = known[0];
    for (let index = 0; index < firstIndex; index++) {
      times[index] = Math.max(0, firstAt - (firstIndex - index) / WORDS_PER_SECOND);
    }
    for (const [position, [index, at]] of known.entries()) {
      times[index] = at;
      const next = known[position + 1];
      if (!next) continue;
      const [nextIndex, nextAt] = next;
      for (let between = index + 1; between < nextIndex; between++) {
        times[between] = at + (nextAt - at) * (between - index) / (nextIndex - index);
      }
    }
    const [lastIndex, lastAt] = known.at(-1)!;
    for (let index = lastIndex + 1; index < tokens.length; index++) {
      times[index] = Math.min(end, lastAt + (index - lastIndex) / WORDS_PER_SECOND);
    }
  }
  return tokens.map((w, index) => ({ w, start: times[index], end: times[index] }));
}

/// Strict JSON Schema, for OpenAI.
export const INTERPRET_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["steps", "dose", "water", "seconds"],
  properties: {
    steps: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["at", "action", "mass", "until", "note"],
        properties: {
          at: { type: "integer" },
          action: { type: "string", enum: [...ACTIONS] },
          mass: { type: ["number", "null"] },
          until: { type: ["integer", "null"] },
          note: { type: "string" },
        },
      },
    },
    dose: { type: ["number", "null"] },
    water: { type: ["number", "null"] },
    seconds: { type: ["integer", "null"] },
  },
};

const NULL_NUMBER = { type: "NUMBER", nullable: true } as const;

/// The same, in Gemini's dialect.
export const INTERPRET_SCHEMA_GEMINI = {
  type: "OBJECT",
  properties: {
    steps: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          at: { type: "INTEGER" },
          action: { type: "STRING", enum: [...ACTIONS] },
          mass: NULL_NUMBER,
          until: { type: "INTEGER", nullable: true },
          note: { type: "STRING" },
        },
        required: ["at", "action", "note"],
        propertyOrdering: ["at", "action", "mass", "until", "note"],
      },
    },
    dose: NULL_NUMBER,
    water: NULL_NUMBER,
    seconds: { type: "INTEGER", nullable: true },
  },
  required: ["steps"],
  propertyOrdering: ["steps", "dose", "water", "seconds"],
};

/// The user message for the interpreter.
export function interpretInput(words: Word[], context: Context, estimated: boolean): string {
  return [
    describe(context),
    estimated ? ESTIMATED_NOTE : "",
    "Transcript:",
    timedLines(words),
  ].filter(Boolean).join("\n\n");
}
