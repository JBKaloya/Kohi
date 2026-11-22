// Who answers an assistant call. By default OpenAI first, then Gemini's
// light model: on 21–22 Nov 2026 gemini-3.8-flash answered none of our calls
// (503 or timeout), while gpt-5.6-luna answered every one in 1 to 2 s
// (docs/assistants-gemini-vs-openai.md). A body can ask for one provider
// alone, which the beta's model comparisons do.

export type Provider = "openai-first" | "gemini" | "openai";

export function provider(body: unknown): Provider {
  const asked = (body as { provider?: unknown })?.provider;
  return asked === "openai" || asked === "gemini" ? asked : "openai-first";
}
