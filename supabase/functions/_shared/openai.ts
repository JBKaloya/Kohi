// One structured call to an OpenAI text model.
//
// Secrets:  OPENAI_API_KEY
// Optional: OPENAI_TEXT_MODEL (defaults to gpt-5.6-luna)
//           OPENAI_REASONING (defaults to low)
//
// The schema is strict JSON Schema: every property required, nullable ones
// typed ["number", "null"], no extra properties.

export type JSONResult =
  | { ok: true; text: string; inputTokens: number | null; outputTokens: number | null; model: string }
  | { ok: false; status: number; model: string; detail: string };

const TIMEOUT_MS = 30_000;

export function textModel(): string {
  return Deno.env.get("OPENAI_TEXT_MODEL") ?? "gpt-5.6-luna";
}

export async function generateJSON(
  system: string,
  user: string,
  name: string,
  schema: Record<string, unknown>,
  model = textModel(),
  options: { timeoutMs?: number } = {},
): Promise<JSONResult> {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) return { ok: false, status: 500, model, detail: "OPENAI_API_KEY is not configured" };

  let response: Response;
  try {
    response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        reasoning_effort: Deno.env.get("OPENAI_REASONING") ?? "low",
        messages: [
          { role: "system", content: system },
          { role: "user", content: user },
        ],
        response_format: {
          type: "json_schema",
          json_schema: { name, strict: true, schema },
        },
      }),
      signal: AbortSignal.timeout(options.timeoutMs ?? TIMEOUT_MS),
    });
  } catch (error) {
    return { ok: false, status: 504, model, detail: `${error}` };
  }
  if (!response.ok) {
    const detail = await response.text();
    console.error(`openai error ${response.status} model=${model}: ${detail}`);
    return { ok: false, status: response.status, model, detail };
  }
  const data = await response.json();
  const text = data?.choices?.[0]?.message?.content;
  if (!text) return { ok: false, status: 502, model, detail: "empty response" };
  return {
    ok: true,
    text,
    inputTokens: data?.usage?.prompt_tokens ?? null,
    outputTokens: data?.usage?.completion_tokens ?? null,
    model: data?.model ?? model,
  };
}
