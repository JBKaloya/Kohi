const fs = require('fs');
const path = require('path');
// Rewrites ../aroma-palette.json, ../card-terroir.json, ../origin-stickers.json, ../card-art-vectors.json from lab/*.js.
//   node export.js
const src = ['data.js','engine.js','stickers.js'].map(f => fs.readFileSync(path.join(__dirname,'lab',f),'utf8')).join('\n');
const api = new Function(src + '\nreturn {AROMA, WHEEL_FAMILY, ORIGIN_CODE, TERROIR, TERROIR_UNKNOWN, PROCESS, ROAST, COLLECTION, STICKERS, SEALS, SHAPES, S, TYPE, P, makeArt, fieldColor, labToRgb, rgbToHex, fnv1a, rngFrom, matchAroma, genericSticker, sealSpec, classifyProcess, altitudeMeters};')();
// 1. aroma palette
const aroma = { schema: 'kohi.aroma-palette/1', note: 'One colour per note. ids without x- are flavor-wheel.json node ids; x- ids are specialty notes the wheel lacks. Match: FlavorMatcher first, then the longest synonym contained in the note.', entries: api.AROMA.map(a => ({ id: a.id, color: a.c, family: a.fam, synonyms: a.syn })) };
fs.writeFileSync(path.join(__dirname,'..','aroma-palette.json'), JSON.stringify(aroma, null, 2));
// 2. terroir + process + roast
const terroir = { schema: 'kohi.card-terroir/1',
  origins: Object.fromEntries(Object.entries(api.TERROIR).map(([k, v]) => [k, { ground: v[0], tone1: v[1], tone2: v[2] }])),
  unknownOrigin: { ground: api.TERROIR_UNKNOWN[0], tone1: api.TERROIR_UNKNOWN[1], tone2: api.TERROIR_UNKNOWN[2] },
  process: Object.fromEntries(Object.entries(api.PROCESS).map(([k, v]) => [k, { warp: v.warp, grainOverlay: v.grain, chroma: v.chroma, sharpness: v.sharp, swirl: v.swirl, warmShift: v.warm || 0, darken: v.darken || 0, extraBlob: v.extra ? { color: v.extra.c, weight: v.extra.w, sigma: v.extra.s } : null }])),
  roastLightness: Object.fromEntries(Object.entries(api.ROAST).map(([k, v]) => [k, v.dL])), roastUnknown: 0.02,
  sky: { lowAltitude: '#F4DDB7', highAltitude: '#EAF1EF', tintFromLightestNote: 0.18, minL: 0.9, altitudeRange: [900, 2200] },
};
fs.writeFileSync(path.join(__dirname,'..','card-terroir.json'), JSON.stringify(terroir, null, 2));
// 3. sticker recipes, recorded as layer lists
const realS = { ...api.S }; let rec = null;
for (const k of Object.keys(api.S)) api.S[k] = (...args) => { rec.push({ kind: k, args: args.length === 1 ? args[0] : args }); return ''; };
const recipe = (spec) => { rec = []; if (spec.scene) spec.scene(); const layers = rec; rec = null; return { shape: spec.shape, background: spec.bg, ink: spec.ink, layers, name: spec.name ? { text: spec.name.t, style: spec.name.style, x: spec.name.x || 120, y: spec.name.y ?? null, width: spec.name.w ?? null, size: spec.name.size, fill: spec.name.fill, stroke: spec.name.stroke || 'none', shadow: spec.name.shadow || null, onArc: !!spec.name.arc } : null }; };
const stickers = { schema: 'kohi.origin-stickers/1', box: 240, paper: api.P.paper,
  texture: { halftone: { cell: 4.2, dotRadius: 0.95, angleDeg: 28, opacity: 0.13, color: 'ink' }, keyline: { width: 3.4, offset: [1.1, -0.9] }, dieCut: { width: 15, color: 'paper' }, shadow: { dy: 2, blur: 2.2, opacity: 0.38, color: '#24180e' }, wear: { noiseFrequency: 0.7, octaves: 2, holeAbove: 0.756 } },
  shapes: Object.fromEntries(Object.entries(api.SHAPES).map(([k, v]) => [k, { svgPath: v.d, top: v.top, bottom: v.bottom, textArc: v.arc || null }])),
  typeStyles: { italic: 'DM Serif Display Italic (or New York italic, black)', condensed: 'Archivo wdth 62 wght 900 (or SF Pro .compressed .black)', expanded: 'Archivo wdth 125 wght 800 (or SF Pro .expanded .heavy)', spaced: 'Archivo wdth 100 wght 700, tracking 0.24 em', arched: 'Archivo wdth 112 wght 800, tracking 0.06 em, set on textArc' },
  origins: Object.fromEntries(Object.entries(api.STICKERS).map(([k, v]) => [k, recipe(v)])),
  generic: { note: 'Origins on the whitelist without a recipe: shape picked by mulberry32(fnv1a("sticker-"+ISO)) from [oval, ticket, hexa, shield, scallop, arch]; sky = mix(tone1, #FBF3E2, 0.72) in OKLab; sun r18 in tone2 at top+54; range base 136 with 3 seeded peaks in ground; band from 134 in tone1; condensed name in ground with sky shadow.', examples: Object.fromEntries(['MM','LA','PH','ZM','ZW','CM','HT','DO','CU','VE'].map(k => [k, recipe(api.genericSticker(k))])) },
  seals: Object.fromEntries(Object.keys(api.SEALS).map(k => [k, recipe(api.sealSpec(k))])),
};
Object.assign(api.S, realS);
fs.writeFileSync(path.join(__dirname,'..','origin-stickers.json'), JSON.stringify(stickers, null, 2));
// 4. test vectors
const vec = api.COLLECTION.slice(0, 5).map(c => { const a = api.makeArt(c); const mid = api.rgbToHex(api.labToRgb(api.fieldColor(a, 0.5, 0.5))); const top = api.rgbToHex(api.labToRgb(api.fieldColor(a, 0.5, 0.06))); return { id: c.id, name: c.name, seedHex: a.seed.toString(16).padStart(8,'0'), firstRandoms: (() => { const r = api.rngFrom(a.seed); return [r(), r(), r()].map(x => +x.toFixed(6)); })(), process: a.procKey, altitudeShare: +a.h.toFixed(3), side: a.side, stickerRotationDeg: +a.stickerRot.toFixed(2), titleInk: a.titleInk, fieldAtCenter: mid, fieldAtTop: top }; });
fs.writeFileSync(path.join(__dirname,'..','card-art-vectors.json'), JSON.stringify({ schema: 'kohi.card-art-vectors/1', tolerance: 'colour ±2/255 per channel (exp/pow differ slightly across languages)', vectors: vec }, null, 2));
console.log(JSON.stringify(vec.slice(0,2), null, 1));
console.log(['Winey Blueberry','Lemon Grass','Cacao Nibs','Stonefruits','Crisp Apple','Golden Raisin'].map(n => n + ' -> ' + (api.matchAroma(n)||{}).id).join('\n'));
console.log('json written');
