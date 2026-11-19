// The ways a brew note can be heard, behind one call.
//
//   gemini-audio   Gemini listens to the audio and returns everything.
//   scribe+luna    Scribe transcribes with word timings, gpt-5.6-luna reads the steps.
//   scribe+gemini  Scribe transcribes, Gemini reads the steps from the text.
//   openai+luna    gpt-transcribe transcribes without timings, the words are
//                  placed from the device's, gpt-5.6-luna reads the steps.
//
// Every result says what it cost and how long it took, so pipelines can be
// compared on the same note.

import { generate } from "./gemini.ts";
import { generateJSON } from "./openai.ts";
import { transcribeOpenAI, transcribeScribe, type Transcript, type Word } from "./stt.ts";
import {
  type Context,
  describe,
  estimate,
  INTERPRET_PROMPT,
  INTERPRET_SCHEMA,
  INTERPRET_SCHEMA_GEMINI,
  interpretInput,
  type Phrase,
  STEP_RULES,
  utterances,
} from "./narration-interpret.ts";

export const PIPELINES = ["gemini-audio", "scribe+luna", "scribe+gemini", "openai+luna"] as const;
export type Pipeline = typeof PIPELINES[number];

export function isPipeline(name: unknown): name is Pipeline {
  return typeof name === "string" && (PIPELINES as readonly string[]).includes(name);
}

/// The pipeline brew-narration runs when the request names none.
export function defaultPipeline(): Pipeline {
  const named = Deno.env.get("NARRATION_PIPELINE");
  return isPipeline(named) ? named : "gemini-audio";
}

export type Step = {
  at: number;
  action: string;
  mass: number | null;
  until: number | null;
  note: string;
};

export type Heard = {
  transcript: string;
  utterances: Phrase[];
  steps: Step[];
  dose: number | null;
  water: number | null;
  seconds: number | null;
};

export type Result =
  | {
    pipeline: Pipeline;
    ok: true;
    fields: Heard;
    model: string;
    inputTokens: number | null;
    outputTokens: number | null;
    latencyMs: number;
    costUsd: number | null;
  }
  | { pipeline: Pipeline; ok: false; model: string; latencyMs: number; failure: string; status: number };

export type Audio = { bytes: Uint8Array; base64: string; mime: string };

/// USD per million tokens, input then output.
const PRICES: Record<string, [number, number]> = {
  "gemini-3.8-flash": [0.75, 3.75],
  "gemini-3.5-flash-lite": [0.30, 2.50],
  "gpt-5.6-luna": [0.20, 1.20],
};

function tokenCost(model: string, input: number | null, output: number | null): number | null {
  const price = Object.entries(PRICES).find(([name]) => model.startsWith(name))?.[1];
  if (!price) return null;
  return ((input ?? 0) * price[0] + (output ?? 0) * price[1]) / 1_000_000;
}

/// Words a brew note says that a general model mishears.
const BREW_TERMS = [
  "bloom", "palier", "paliers", "drawdown", "swirl", "V60", "Kalita", "Origami",
  "Chemex", "AeroPress", "grammes", "je verse", "ça draine",
];

const TRANSCRIBE_PROMPT =
  "Narration d'un café filtre pendant l'infusion : bloom de 40 grammes, je verse par paliers, j'attends 30 secondes, ça draine.";

const AUDIO_PROMPT = `\
You are listening to someone narrating a coffee brew out loud while they \
make it, in French or English. The recording starts when the brew starts, \
so a time in the audio is the time in the brew.

Return:
- transcript: everything that was said, verbatim, in the speaker's language.
- utterances: each sentence with the second it began at.
- steps: the brew steps the narration describes, in order.

- at is the second, from the start of the recording, at which the step was \
  said. Take it from the audio, never from a number the speaker said.

${STEP_RULES}`;

const NULL_NUMBER = { type: "NUMBER", nullable: true } as const;

const AUDIO_SCHEMA = {
  type: "OBJECT",
  properties: {
    transcript: { type: "STRING" },
    utterances: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: { at: { type: "NUMBER" }, text: { type: "STRING" } },
        propertyOrdering: ["at", "text"],
      },
    },
    steps: INTERPRET_SCHEMA_GEMINI.properties.steps,
    dose: NULL_NUMBER,
    water: NULL_NUMBER,
    seconds: { type: "INTEGER", nullable: true },
  },
  propertyOrdering: ["transcript", "utterances", "steps", "dose", "water", "seconds"],
};

type Answer = Omit<Extract<Result, { ok: true }>, "pipeline" | "latencyMs">;
type Failure = { ok: false; model: string; failure: string; status: number };

function failed(model: string, status: number, failure: string): Failure {
  return { ok: false, model, status, failure };
}

function heard(raw: unknown): Heard {
  const fields = raw as Partial<Heard>;
  return {
    transcript: fields.transcript ?? "",
    utterances: fields.utterances ?? [],
    steps: (fields.steps ?? []).map((step) => ({
      at: Math.round(step.at),
      action: step.action,
      mass: step.mass ?? null,
      until: step.until ?? null,
      note: step.note ?? "",
    })),
    dose: fields.dose ?? null,
    water: fields.water ?? null,
    seconds: fields.seconds ?? null,
  };
}

function geminiKey(): string | undefined {
  return Deno.env.get("GEMINI_API_KEY");
}

async function geminiAudio(audio: Audio, context: Context): Promise<Answer | Failure> {
  const apiKey = geminiKey();
  if (!apiKey) return failed("gemini", 500, "GEMINI_API_KEY is not configured");
  const parts: unknown[] = [
    { inlineData: { mimeType: audio.mime, data: audio.base64 } },
    { text: AUDIO_PROMPT },
  ];
  const described = describe(context);
  if (described) parts.push({ text: described });
  const result = await generate(apiKey, parts, {
    temperature: 0,
    responseMimeType: "application/json",
    responseSchema: AUDIO_SCHEMA,
    thinkingConfig: { thinkingLevel: "low" },
  });
  if (!result.ok) return failed(result.model, result.status, `model returned ${result.status}`);
  if (!result.text) return failed(result.model, 502, "empty model response");
  const input = result.usage.promptTokenCount ?? null;
  const output = result.usage.candidatesTokenCount ?? null;
  return {
    ok: true,
    fields: heard(JSON.parse(result.text)),
    model: result.model,
    inputTokens: input,
    outputTokens: output,
    costUsd: tokenCost(result.model, input, output),
  };
}

type Read = { steps: Step[]; dose: number | null; water: number | null; seconds: number | null };

async function interpret(
  reader: "luna" | "gemini",
  words: Word[],
  context: Context,
  estimated: boolean,
): Promise<
  | { ok: true; read: Read; model: string; inputTokens: number | null; outputTokens: number | null }
  | Failure
> {
  const input = interpretInput(words, context, estimated);
  if (reader === "luna") {
    const result = await generateJSON(INTERPRET_PROMPT, input, "brew_steps", INTERPRET_SCHEMA);
    if (!result.ok) return failed(result.model, result.status, result.detail.slice(0, 300));
    return {
      ok: true,
      read: JSON.parse(result.text),
      model: result.model,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
    };
  }
  const apiKey = geminiKey();
  if (!apiKey) return failed("gemini", 500, "GEMINI_API_KEY is not configured");
  const result = await generate(apiKey, [{ text: INTERPRET_PROMPT }, { text: input }], {
    temperature: 0,
    responseMimeType: "application/json",
    responseSchema: INTERPRET_SCHEMA_GEMINI,
    thinkingConfig: { thinkingLevel: "low" },
  });
  if (!result.ok) return failed(result.model, result.status, `model returned ${result.status}`);
  if (!result.text) return failed(result.model, 502, "empty model response");
  return {
    ok: true,
    read: JSON.parse(result.text),
    model: result.model,
    inputTokens: result.usage.promptTokenCount ?? null,
    outputTokens: result.usage.candidatesTokenCount ?? null,
  };
}

async function twoStage(
  pipeline: Exclude<Pipeline, "gemini-audio">,
  audio: Audio,
  context: Context,
): Promise<Answer | Failure> {
  const terms = [...BREW_TERMS, ...(context.vocabulary ?? [])];
  const seconds = context.duration ?? 0;
  const transcript: Transcript = pipeline === "openai+luna"
    ? await transcribeOpenAI(audio.bytes, audio.mime, terms, TRANSCRIBE_PROMPT, seconds)
    : await transcribeScribe(audio.bytes, audio.mime, terms, seconds);
  if (!transcript.ok) {
    console.error(`stt error ${transcript.status} model=${transcript.model}: ${transcript.detail}`);
    return failed(transcript.model, transcript.status, transcript.detail.slice(0, 300));
  }
  const estimated = transcript.words == null;
  const words = transcript.words ??
    estimate(transcript.text, context.phrases ?? [], seconds);
  const base = {
    transcript: transcript.text,
    utterances: utterances(words),
  };
  if (!words.length) {
    return {
      ok: true,
      fields: heard({ ...base, steps: [] }),
      model: transcript.model,
      inputTokens: null,
      outputTokens: null,
      costUsd: transcript.costUsd,
    };
  }
  const read = await interpret(pipeline === "scribe+gemini" ? "gemini" : "luna", words, context, estimated);
  if (!read.ok) return failed(`${transcript.model} + ${read.model}`, read.status, read.failure);
  return {
    ok: true,
    fields: heard({ ...read.read, ...base }),
    model: `${transcript.model} + ${read.model}`,
    inputTokens: read.inputTokens,
    outputTokens: read.outputTokens,
    costUsd: transcript.costUsd + (tokenCost(read.model, read.inputTokens, read.outputTokens) ?? 0),
  };
}

/// One pipeline on one note. Never throws: a failure is a result too.
export async function run(
  pipeline: Pipeline,
  audio: Audio,
  context: Context,
  timeoutMs = 30_000,
): Promise<Result> {
  const started = Date.now();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<Failure>((resolve) => {
    timer = setTimeout(() => resolve(failed("timeout", 504, `no answer in ${timeoutMs / 1000} s`)), timeoutMs);
  });
  const work = (pipeline === "gemini-audio" ? geminiAudio(audio, context) : twoStage(pipeline, audio, context))
    .catch((error) => failed("unknown", 500, `${error}`));
  const outcome = await Promise.race([work, deadline]);
  clearTimeout(timer);
  return { ...outcome, pipeline, latencyMs: Date.now() - started };
}
