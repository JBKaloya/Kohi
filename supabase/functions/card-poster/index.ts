// card-poster: generates a 4:5 stamp-on-paper flyer from a coffee card
// photo using OpenAI's gpt-image-2 model. The API key stays server-side;
// the app only sends a base64 image and receives one back.
//
// Secrets:   OPENAI_API_KEY (required)
// Optional:  OPENAI_IMAGE_MODEL (defaults to gpt-image-2)

const PROMPT = `\
Create a "Rubber Stamp Field Notes" flyer from the uploaded photo.

Overall composition: a 4:5 portrait. The entire frame is the same warm \
off-white paper as the Kohi archive cards: #FAF8F4, RGB 250, 248, 244 \
(sRGB 0.980, 0.973, 0.957). Soft, slightly warm, not cream, not yellowed \
parchment, not cool white. Only the faintest grain — the flyer should \
read as printed on that same default card paper. Generous whitespace \
is a deliberate part of the layout.

Analyse the photo and extract the most recognisable subject outlines, \
compressing them into a small multi-colour rubber stamp image placed in \
the centre of the 4:5 frame. The stamp occupies about 45–55 % of the \
frame height, surrounded by ample blank paper on every side.

Do not replicate every element. Retain only the information strictly \
necessary to recognise the original subject and its identity. Remove \
backgrounds, surfaces, hands, and irrelevant context.

Determine the stamp's content based on the photo's subject:

- Coffee bag or pouch: retain the distinctive silhouette and cut, brand \
  mark or logo shape, label block geometry, and any iconic pictogram.
- Coffee card or label (folded or flat): retain the fold lines, panel \
  layout, world-map or graphic block if present, and any distinctive \
  border or frame.
- Brewing equipment: retain the tool's outline — dripper cone, server \
  silhouette, portafilter shape — simplified to its most recognisable \
  contour.
- Foreground objects (cup, saucer, beans): retain as simplified foreground \
  stamp outlines only when they are narratively important.

Extract 2–4 spot ink colours from the photo. Prioritise desaturated \
tones: carbon black, deep green, brick red, ochre yellow, slate blue, \
taupe brown. Do not force a fixed palette — preserve the most \
distinctive colour character from the original photo.

Render each colour as a separately hand-stamped layer:
Authentic rubber stamp carving texture, hand-engraved marks, uneven \
line widths, partial ink transfer, ink accumulation at edges, ink seep \
through, granular ink, uneven pressure, partial ghosting, and about \
1–2 mm of subtle misregistration between colour layers.

Allow natural misalignment between layers; edges must not be digitally \
smoothed. The print must resemble a real carved stamp pressed onto that same \
#FAF8F4 card paper, not a filtered photo, smooth vector illustration, \
or fine-art logo.

There must be absolutely no text, no lettering, no numerals, no \
captions, no typography of any kind anywhere in the image. The stamp \
and the paper texture are the only elements.

Overall vibe: quiet, meticulous, understated. Ink imperfections stay; \
the paper stays the default Kohi card colour #FAF8F4 throughout, edge \
to edge, with no vignette and no darker margins.

Avoid: Circular seals, Chinese red stamps, postage stamp perforations, \
wax seals, sticker collages, tourist souvenir templates, smooth vector \
logos, generic icons, dense detailing, childlike craftiness, cartoon \
style, 3D rendering, plastic textures, glossy digital gradients, \
overexaggeration, decorative clutter, any text or lettering of any kind.`;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "POST only" }, 405);
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    return json({ error: "OPENAI_API_KEY is not configured" }, 500);
  }

  let image: string | undefined;
  let mime: string | undefined;
  let card_id: string | undefined;
  try {
    ({ image, mime, card_id } = await req.json());
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  if (!image) {
    return json({ error: "missing image" }, 400);
  }

  // Decode the base64 image into raw bytes for the multipart upload.
  const imageBytes = Uint8Array.from(atob(image), (c) => c.charCodeAt(0));
  const ext = (mime ?? "image/jpeg").split("/")[1] ?? "jpg";

  const model = Deno.env.get("OPENAI_IMAGE_MODEL") ?? "gpt-image-2";

  const form = new FormData();
  form.append("model", model);
  form.append(
    "image[]",
    new Blob([imageBytes], { type: mime ?? "image/jpeg" }),
    `input.${ext}`,
  );
  form.append("prompt", PROMPT);
  form.append("size", "1024x1280");
  form.append("quality", "high");
  form.append("output_format", "png");

  const response = await fetch("https://api.openai.com/v1/images/edits", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}` },
    body: form,
  });

  if (!response.ok) {
    const detail = await response.text();
    console.error(`openai error ${response.status}: ${detail}`);
    const reason =
      response.status === 429
        ? "image generation rate limit exceeded"
        : `image model returned ${response.status}`;
    return json({ error: reason }, 502);
  }

  const data = await response.json();
  const b64 = data?.data?.[0]?.b64_json;
  if (!b64) {
    console.error("openai returned no image");
    return json({ error: "empty model response" }, 502);
  }

  const pngBytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  if (card_id) {
    try {
      await persistPoster(card_id, pngBytes);
    } catch (err) {
      console.error("persist poster failed", err);
    }
  }

  return json({ image: b64, mime: "image/png" });
});

async function persistPoster(cardId: string, pngBytes: Uint8Array) {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    console.error("persist skipped: missing SUPABASE_URL or SERVICE_ROLE");
    return;
  }

  const headers = {
    Authorization: `Bearer ${key}`,
    apikey: key,
  };

  const lookup = await fetch(
    `${url}/rest/v1/coffee_cards?id=eq.${cardId}&select=user_id`,
    { headers },
  );
  if (!lookup.ok) {
    console.error(`persist lookup ${lookup.status}: ${await lookup.text()}`);
    return;
  }
  const rows = await lookup.json();
  const userId = rows?.[0]?.user_id as string | undefined;
  if (!userId) {
    console.error(`persist: no coffee_cards row for ${cardId}`);
    return;
  }

  const path = `${userId.toLowerCase()}/${cardId.toLowerCase()}/poster.png`;
  const upload = await fetch(`${url}/storage/v1/object/cards/${path}`, {
    method: "POST",
    headers: {
      ...headers,
      "Content-Type": "image/png",
      "x-upsert": "true",
    },
    body: pngBytes,
  });
  if (!upload.ok) {
    console.error(`persist upload ${upload.status}: ${await upload.text()}`);
    return;
  }

  const patch = await fetch(`${url}/rest/v1/coffee_cards?id=eq.${cardId}`, {
    method: "PATCH",
    headers: {
      ...headers,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify({ poster: "ready", updated_at: new Date().toISOString() }),
  });
  if (!patch.ok) {
    console.error(`persist row ${patch.status}: ${await patch.text()}`);
    return;
  }
  console.log(`persisted poster for ${cardId}`);
}
