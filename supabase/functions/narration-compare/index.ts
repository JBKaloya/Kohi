// narration-compare: every narration pipeline on the same voice note, for
// testers to say which one heard them best.
//
// No pipeline stands in for another here: one that fails or runs past its
// time comes back as a failure, which is part of what is being compared.
//
// Secrets: GEMINI_API_KEY, ELEVENLABS_API_KEY, OPENAI_API_KEY

import { type Context } from "../_shared/narration-interpret.ts";
import { isPipeline, PIPELINES, run } from "../_shared/narration-pipelines.ts";
import { requireUser } from "../_shared/auth.ts";

const TIMEOUT_MS = 30_000;

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

  const auth = await requireUser(req);
  if (!auth.ok) return auth.response;

  let body: { audio?: string; mime?: string; context?: Context; pipelines?: string[] };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (!body.audio) return json({ error: "missing audio" }, 400);

  const audio = { bytes: bytes(body.audio), base64: body.audio, mime: body.mime ?? "audio/mp4" };
  const context = body.context ?? {};
  const pipelines = body.pipelines?.filter(isPipeline) ?? [...PIPELINES];

  const candidates = await Promise.all(
    pipelines.map((pipeline) => run(pipeline, audio, context, TIMEOUT_MS)),
  );
  for (const candidate of candidates) {
    console.log(
      `compare ${candidate.pipeline} ${candidate.ok ? "ok" : `failed ${candidate.failure}`} ` +
        `${candidate.latencyMs} ms model=${candidate.model}`,
    );
  }
  return json({ candidates });
});
