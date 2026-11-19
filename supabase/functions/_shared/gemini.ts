// One call to Gemini, with a fallback model.
//
// Optional: GEMINI_MODEL          (defaults to gemini-3.8-flash)
// Optional: GEMINI_MODEL_FALLBACK (defaults to gemini-3.5-flash-lite)
//
// The fallback is tried when the primary model is overloaded (503), out of
// quota (429), failing (500, 504) or gone (404). Anything else is the
// request's fault and would fail the same way on the second model.

const RETRYABLE = new Set([404, 429, 500, 503, 504]);
/// The primary is cut short so a hung call still leaves the fallback its
/// time inside the function's 150 s limit.
const ATTEMPT_MS = [25_000, 90_000];

export type Usage = {
  promptTokenCount?: number;
  candidatesTokenCount?: number;
};

export type Generated =
  | { ok: true; text: string | undefined; usage: Usage; model: string }
  | { ok: false; status: number; model: string };

export function models(): string[] {
  return [
    Deno.env.get("GEMINI_MODEL") ?? "gemini-3.8-flash",
    Deno.env.get("GEMINI_MODEL_FALLBACK") ?? "gemini-3.5-flash-lite",
  ].filter((name, index, all) => name && all.indexOf(name) === index);
}

/// Gemini 3 takes `thinkingLevel`; 2.5 takes a budget. Sending the wrong
/// shape is a 400, so it is dropped for anything older.
function configFor(model: string, config: Record<string, unknown>) {
  if (model.startsWith("gemini-3")) return config;
  const { thinkingConfig: _, ...rest } = config;
  return rest;
}

export async function generate(
  apiKey: string,
  parts: unknown[],
  generationConfig: Record<string, unknown>,
): Promise<Generated> {
  let failure: Generated = { ok: false, status: 502, model: models()[0] };
  for (const [attempt, model] of models().entries()) {
    let response: Response;
    try {
      response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": apiKey,
          },
          body: JSON.stringify({
            contents: [{ parts }],
            generationConfig: configFor(model, generationConfig),
          }),
          signal: AbortSignal.timeout(ATTEMPT_MS[attempt] ?? ATTEMPT_MS.at(-1)!),
        },
      );
    } catch (error) {
      console.error(`gemini error timeout model=${model}: ${error}`);
      failure = { ok: false, status: 504, model };
      continue;
    }
    if (response.ok) {
      const data = await response.json();
      return {
        ok: true,
        text: data?.candidates?.[0]?.content?.parts?.[0]?.text,
        usage: data?.usageMetadata ?? {},
        model,
      };
    }
    console.error(
      `gemini error ${response.status} model=${model}: ${await response
        .text()}`,
    );
    failure = { ok: false, status: response.status, model };
    if (!RETRYABLE.has(response.status)) break;
  }
  return failure;
}
