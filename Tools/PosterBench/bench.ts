#!/usr/bin/env -S deno run -A
/**
 * Poster bench: calls gpt-image-2 /v1/images/edits on every .jpg in input/,
 * writes PNG results to out/, and produces a report.json with latency and
 * token-based cost for each generation.
 *
 * Usage:   deno run -A bench.ts
 * Env:     OPENAI_API_KEY, OPENAI_IMAGE_MODEL (default gpt-image-2)
 *          Read from .env in the script's directory.
 */

import "jsr:@std/dotenv/load";
import { POSTER_PROMPT } from "./prompt.ts";

const API_KEY = Deno.env.get("OPENAI_API_KEY");
if (!API_KEY) {
  console.error("OPENAI_API_KEY not set. Copy .env.example to .env and fill it in.");
  Deno.exit(1);
}

const MODEL = Deno.env.get("OPENAI_IMAGE_MODEL") ?? "gpt-image-2";
const INPUT_DIR = new URL("./input/", import.meta.url).pathname;
const OUTPUT_DIR = new URL("./out/", import.meta.url).pathname;

const IMAGE_TOKEN_OUTPUT_COST = 30; // $ per 1M output image tokens
const IMAGE_TOKEN_INPUT_COST = 8;   // $ per 1M input image tokens
const TEXT_TOKEN_INPUT_COST = 5;     // $ per 1M text input tokens

interface RunResult {
  source: string;
  model: string;
  latencyMs: number;
  usage: Record<string, unknown> | null;
  costEstimate: number | null;
  outputFile: string;
  error?: string;
}

async function generate(sourceFile: string): Promise<RunResult> {
  const sourceName = sourceFile.replace(/\.[^.]+$/, "");
  const imageBytes = await Deno.readFile(`${INPUT_DIR}${sourceFile}`);
  const blob = new Blob([imageBytes], { type: "image/jpeg" });

  const form = new FormData();
  form.append("model", MODEL);
  form.append("image[]", blob, sourceFile);
  form.append("prompt", POSTER_PROMPT);
  form.append("size", "1024x1280");
  form.append("quality", "high");
  form.append("output_format", "png");

  console.log(`  → generating poster for ${sourceFile}…`);
  const t0 = performance.now();

  const response = await fetch("https://api.openai.com/v1/images/edits", {
    method: "POST",
    headers: { Authorization: `Bearer ${API_KEY}` },
    body: form,
  });

  const latencyMs = Math.round(performance.now() - t0);

  if (!response.ok) {
    const detail = await response.text();
    console.error(`    ✗ ${response.status}: ${detail}`);
    return {
      source: sourceFile, model: MODEL, latencyMs,
      usage: null, costEstimate: null,
      outputFile: "", error: `${response.status}: ${detail}`,
    };
  }

  const data = await response.json();
  const usage = data.usage ?? null;

  let costEstimate: number | null = null;
  if (usage) {
    const inputImageTokens = usage.input_tokens_details?.image_tokens ?? 0;
    const inputTextTokens = usage.input_tokens_details?.text_tokens ?? 0;
    const outputTokens = usage.output_tokens ?? 0;
    costEstimate =
      (inputImageTokens / 1_000_000) * IMAGE_TOKEN_INPUT_COST +
      (inputTextTokens / 1_000_000) * TEXT_TOKEN_INPUT_COST +
      (outputTokens / 1_000_000) * IMAGE_TOKEN_OUTPUT_COST;
  }

  const b64 = data.data?.[0]?.b64_json;
  if (!b64) {
    console.error("    ✗ no image in response");
    return {
      source: sourceFile, model: MODEL, latencyMs,
      usage, costEstimate,
      outputFile: "", error: "no b64_json in response",
    };
  }

  const outputFile = `${sourceName}.png`;
  const decoded = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  await Deno.writeFile(`${OUTPUT_DIR}${outputFile}`, decoded);
  console.log(`    ✓ ${outputFile} (${latencyMs}ms, ~$${costEstimate?.toFixed(3) ?? "?"})`);

  return {
    source: sourceFile, model: MODEL, latencyMs,
    usage, costEstimate, outputFile,
  };
}

// ---- main ----------------------------------------------------------------

console.log(`\nPoster bench — model: ${MODEL}\n`);

const inputs: string[] = [];
for await (const entry of Deno.readDir(INPUT_DIR)) {
  if (entry.isFile && /\.(jpe?g|png|webp)$/i.test(entry.name)) {
    inputs.push(entry.name);
  }
}
inputs.sort();

if (inputs.length === 0) {
  console.error("No images found in input/. Drop .jpg files there and re-run.");
  Deno.exit(1);
}

console.log(`Found ${inputs.length} input(s): ${inputs.join(", ")}\n`);

const results: RunResult[] = [];
for (const file of inputs) {
  results.push(await generate(file));
}

const report = {
  timestamp: new Date().toISOString(),
  model: MODEL,
  results,
};

await Deno.writeTextFile(
  `${OUTPUT_DIR}report.json`,
  JSON.stringify(report, null, 2) + "\n",
);

console.log(`\n✓ report.json written to out/`);
console.log(`  total cost: ~$${results.reduce((s, r) => s + (r.costEstimate ?? 0), 0).toFixed(3)}`);
console.log(`  total latency: ${results.reduce((s, r) => s + r.latencyMs, 0)}ms\n`);
