/**
 * The poster prompt, adapted from the user's original "Rubber Stamp Travel
 * Field Notes Poster" concept. Keep in sync with
 * supabase/functions/card-poster/index.ts.
 *
 *  1. Frame: 4:5 portrait. Pale archival paper fills the frame; the stamp
 *     sits centred, occupying 45-55 % of the height.
 *  2. Text: all typography removed.
 *  3. Paper: Palette.paper / #FAF8F4, the default Kohi card colour.
 *  4. Subject taxonomy: coffee objects instead of travel landscapes.
 */

export const POSTER_PROMPT = `\
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
