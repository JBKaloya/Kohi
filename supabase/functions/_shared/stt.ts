// Speech to text, by a model made for it.
//
// Secrets: ELEVENLABS_API_KEY (Scribe), OPENAI_API_KEY (gpt-transcribe)
// Optional: ELEVENLABS_MODEL (defaults to scribe_v2)
//           OPENAI_TRANSCRIBE_MODEL (defaults to gpt-transcribe)
//
// Both return the same shape. `words` is null when the model gives no
// timings (gpt-transcribe): the caller has to place the words itself.

export type Word = { w: string; start: number; end: number };

export type Transcript =
  | {
    ok: true;
    text: string;
    words: Word[] | null;
    language: string | null;
    model: string;
    costUsd: number;
  }
  | { ok: false; status: number; model: string; detail: string };

/// USD per second of audio.
const SCRIBE_PER_SECOND = 0.22 / 3600;
/// Keyterms are billed 20% on top.
const SCRIBE_KEYTERMS = 1.2;
const OPENAI_PER_SECOND = 0.0045 / 60;

const TIMEOUT_MS = 30_000;

/// Scribe refuses a keyterm past 50 characters, 5 words, or with any of
/// these characters, and fails the whole request for it.
export function keyterms(terms: string[]): string[] {
  const seen = new Set<string>();
  return terms
    .map((term) => term.trim())
    .filter((term) =>
      term.length > 1 && term.length <= 50 &&
      term.split(/\s+/).length <= 5 && !/[<>{}[\]\\]/.test(term)
    )
    .filter((term) => {
      const key = term.toLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .slice(0, 100);
}

function file(audio: Uint8Array, mime: string): File {
  return new File([audio as BlobPart], "note.m4a", { type: mime });
}

export async function transcribeScribe(
  audio: Uint8Array,
  mime: string,
  terms: string[],
  seconds: number,
): Promise<Transcript> {
  const model = Deno.env.get("ELEVENLABS_MODEL") ?? "scribe_v2";
  const apiKey = Deno.env.get("ELEVENLABS_API_KEY");
  if (!apiKey) return { ok: false, status: 500, model, detail: "ELEVENLABS_API_KEY is not configured" };

  const form = new FormData();
  form.append("model_id", model);
  form.append("file", file(audio, mime));
  form.append("timestamps_granularity", "word");
  form.append("tag_audio_events", "false");
  const hints = keyterms(terms);
  for (const term of hints) form.append("keyterms", term);

  let response: Response;
  try {
    response = await fetch("https://api.elevenlabs.io/v1/speech-to-text", {
      method: "POST",
      headers: { "xi-api-key": apiKey },
      body: form,
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (error) {
    return { ok: false, status: 504, model, detail: `${error}` };
  }
  if (!response.ok) {
    return { ok: false, status: response.status, model, detail: await response.text() };
  }
  const data = await response.json();
  const words: Word[] = (data?.words ?? [])
    .filter((word: { type?: string }) => word.type === "word")
    .map((word: { text: string; start: number; end: number }) => ({
      w: word.text,
      start: word.start,
      end: word.end,
    }));
  const heard = seconds || words.at(-1)?.end || 0;
  return {
    ok: true,
    text: data?.text ?? "",
    words,
    language: data?.language_code ?? null,
    model,
    costUsd: heard * SCRIBE_PER_SECOND * (hints.length ? SCRIBE_KEYTERMS : 1),
  };
}

export async function transcribeOpenAI(
  audio: Uint8Array,
  mime: string,
  terms: string[],
  prompt: string,
  seconds: number,
): Promise<Transcript> {
  const model = Deno.env.get("OPENAI_TRANSCRIBE_MODEL") ?? "gpt-transcribe";
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) return { ok: false, status: 500, model, detail: "OPENAI_API_KEY is not configured" };

  const form = new FormData();
  form.append("model", model);
  form.append("file", file(audio, mime));
  form.append("response_format", "json");
  form.append("languages[]", "fr");
  form.append("languages[]", "en");
  for (const term of keyterms(terms)) form.append("keywords[]", term);
  if (prompt) form.append("prompt", prompt);

  let response: Response;
  try {
    response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form,
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (error) {
    return { ok: false, status: 504, model, detail: `${error}` };
  }
  if (!response.ok) {
    return { ok: false, status: response.status, model, detail: await response.text() };
  }
  const data = await response.json();
  return {
    ok: true,
    text: data?.text ?? "",
    words: null,
    language: data?.languages?.[0]?.code ?? null,
    model,
    costUsd: seconds * OPENAI_PER_SECOND,
  };
}
