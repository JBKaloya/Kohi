# AI flyers — retired

Kohi used to generate a 4:5 “rubber stamp on paper” flyer from each bag scan and show that flyer on the home grid. The scan stayed the archive; the flyer was a face. This document is the archive of that work. The feature is **removed from the app**. Scan and OCR remain.

## Why it left

Generation took one to two minutes per card (`gpt-image-2` sat silent for ~2 minutes before the first byte). It cost about **$0.22 per image** at `1024×1280` / `high`. It needed a live Supabase edge function and an OpenAI key. Testers still had the scan; the flyer was a second, slower picture of the same bag. Keeping scan-only is the product.

## Architecture

```
flat.heic  →  CardPoster.generate
           →  downsample 1024 px JPEG 0.8
           →  POST { image, mime, card_id }  /functions/v1/card-poster
           →  OpenAI POST /v1/images/edits  (model gpt-image-2)
           →  PNG 1024×1280
           →  ImagePipeline.installPoster  →  poster.heic
           →  optional Storage  {user}/{card}/poster.png  +  coffee_cards.poster = ready
```

The API key never left the server. The client timeout was 300 s because `URLSession`’s 60 s default marked every card `failed` while the function was still running.

Lifecycle on `CoffeeCard.poster`: `none | pending | ready | failed`.

## Client

- `Kohi/Process/CardPoster.swift` — availability from `Supabase.plist`, upload, install.
- `Kohi/Model/PosterState.swift` — state + `PosterLayout.aspectRatio` (4:5).
- New card: chips **Scan** / **AI flyer** in `CardEditSheet` (`generateFlyer`, default on).
- After save: `RootView.generatePoster` if `flags.isOn(.poster)`.
- Grid: `CardTile` asked `CardImageView` for `variant: .poster`; pending tiles used `paperShade` + `ShimmerBar`.
- Detail: Flyer / Scan chips, **Regenerate poster**, alert on failure.
- Account: backfill N posters (~$0.22 each) and restore from Storage.
- Profile: `AIFeature.poster` — **Make flyers**, not behind Experimental AI.
- Files on disk: `poster.heic`, `poster-thumb-{n}-v2.heic`.

`flags.isOn(.poster)` was only enforced on first generate. Regenerate and Account backfill called `CardPoster.generate` whenever Supabase was configured. Server kill-switch `ai_flags.feature = 'card-poster'` did not map onto `AIFeature.poster` (`rawValue` `"poster"`).

## Server

Edge function `supabase/functions/card-poster/index.ts`:

- Secrets: `OPENAI_API_KEY` (required), `OPENAI_IMAGE_MODEL` (default `gpt-image-2`).
- Body: `{ image: base64, mime, card_id }`.
- OpenAI `images/edits`: `size` `1024x1280`, `quality` `high`, `output_format` `png`.
- Persist: Storage `cards/{user}/{card}/poster.png`, PATCH `poster: "ready"`.

Column `coffee_cards.poster text not null default 'none'` (migration `0004_poster.sql`) is **kept**. The app no longer writes it as a live feature. The `ai_flags` row `card-poster` is left in place, unused.

Local bench: `Tools/PosterBench/` (`prompt.ts` kept in sync with the edge function, `bench.ts` against every `.jpg` in `input/`).

## Prompt

Canonical text, from `card-poster/index.ts`:

```
Create a "Rubber Stamp Field Notes" flyer from the uploaded photo.

Overall composition: a 4:5 portrait. The entire frame is the same warm
off-white paper as the Kohi archive cards: #FAF8F4, RGB 250, 248, 244
(sRGB 0.980, 0.973, 0.957). Soft, slightly warm, not cream, not yellowed
parchment, not cool white. Only the faintest grain — the flyer should
read as printed on that same default card paper. Generous whitespace
is a deliberate part of the layout.

Analyse the photo and extract the most recognisable subject outlines,
compressing them into a small multi-colour rubber stamp image placed in
the centre of the 4:5 frame. The stamp occupies about 45–55 % of the
frame height, surrounded by ample blank paper on every side.

Do not replicate every element. Retain only the information strictly
necessary to recognise the original subject and its identity. Remove
backgrounds, surfaces, hands, and irrelevant context.

Determine the stamp's content based on the photo's subject:

- Coffee bag or pouch: retain the distinctive silhouette and cut, brand
  mark or logo shape, label block geometry, and any iconic pictogram.
- Coffee card or label (folded or flat): retain the fold lines, panel
  layout, world-map or graphic block if present, and any distinctive
  border or frame.
- Brewing equipment: retain the tool's outline — dripper cone, server
  silhouette, portafilter shape — simplified to its most recognisable
  contour.
- Foreground objects (cup, saucer, beans): retain as simplified foreground
  stamp outlines only when they are narratively important.

Extract 2–4 spot ink colours from the photo. Prioritise desaturated
tones: carbon black, deep green, brick red, ochre yellow, slate blue,
taupe brown. Do not force a fixed palette — preserve the most
distinctive colour character from the original photo.

Render each colour as a separately hand-stamped layer:
Authentic rubber stamp carving texture, hand-engraved marks, uneven
line widths, partial ink transfer, ink accumulation at edges, ink seep
through, granular ink, uneven pressure, partial ghosting, and about
1–2 mm of subtle misregistration between colour layers.

Allow natural misalignment between layers; edges must not be digitally
smoothed. The print must resemble a real carved stamp pressed onto that same
#FAF8F4 card paper, not a filtered photo, smooth vector illustration,
or fine-art logo.

There must be absolutely no text, no lettering, no numerals, no
captions, no typography of any kind anywhere in the image. The stamp
and the paper texture are the only elements.

Overall vibe: quiet, meticulous, understated. Ink imperfections stay;
the paper stays the default Kohi card colour #FAF8F4 throughout, edge
to edge, with no vignette and no darker margins.

Avoid: Circular seals, Chinese red stamps, postage stamp perforations,
wax seals, sticker collages, tourist souvenir templates, smooth vector
logos, generic icons, dense detailing, childlike craftiness, cartoon
style, 3D rendering, plastic textures, glossy digital gradients,
overexaggeration, decorative clutter, any text or lettering of any kind.
```

Origin: a “Rubber Stamp Travel Field Notes Poster” concept, rewritten for coffee bags, cards, and brew tools, with Kohi paper `#FAF8F4` filling the frame and all typography forbidden.

## What stayed

The grid still lays a card as a 4:5 object when we need a shared ratio (`CardTileLayout.aspectRatio`). That geometry is not generation. Existing `poster.heic` files on disk are leftover; the grid and detail now show the scan.
