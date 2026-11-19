// brew-narration: listens to the voice note of a Live brew and returns what
// was said, when, and the steps it describes.
//
// It runs second. The app has already transcribed the note on device and
// shown the steps it could read; this answer replaces them only while the
// brewer has not touched them, and the app checks every step against the
// length of the note and the water before it does.
//
// Secrets:  GEMINI_API_KEY (required), ELEVENLABS_API_KEY, OPENAI_API_KEY
// Optional: NARRATION_PIPELINE (see _shared/narration-pipelines.ts, defaults
//           to gemini-audio), and the model variables of the shared helpers.
//
// A request may name its pipeline, for the evaluation. When the pipeline
// fails, Gemini listening to the audio answers instead.

import { type Context } from "../_shared/narration-interpret.ts";
import { defaultPipeline, isPipeline, run } from "../_shared/narration-pipelines.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function bytes(base64: string): Uint8Array {
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let body: { audio?: string; mime?: string; context?: Context; pipeline?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (!body.audio) return json({ error: "missing audio" }, 400);

  const audio = { bytes: bytes(body.audio), base64: body.audio, mime: body.mime ?? "audio/mp4" };
  const context = body.context ?? {};
  const pipeline = isPipeline(body.pipeline) ? body.pipeline : defaultPipeline();

  let result = await run(pipeline, audio, context, 60_000);
  if (!result.ok && pipeline !== "gemini-audio") {
    console.error(`narration ${pipeline} failed (${result.failure}), Gemini listens instead`);
    result = await run("gemini-audio", audio, context, 90_000);
  }
  if (!result.ok) {
    return json({
      error: result.status === 429 ? "model quota exhausted" : `model returned ${result.status}`,
    }, 502);
  }

  return json({
    fields: result.fields,
    model: result.model,
    pipeline: result.pipeline,
    inputTokens: result.inputTokens,
    outputTokens: result.outputTokens,
    costUsd: result.costUsd,
    latencyMs: result.latencyMs,
  });
});
