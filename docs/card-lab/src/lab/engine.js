// ───────────────────────── Engine ─────────────────────────
// Pure functions first (seed, colour, art). Same input, same card, on every device and every launch.

function fnv1a(str) {
  let h = 0x811c9dc5;
  const bytes = new TextEncoder().encode(str);
  for (const b of bytes) { h ^= b; h = Math.imul(h, 0x01000193) >>> 0; }
  return h >>> 0;
}
function rngFrom(seed) { // mulberry32
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const clamp = (x, a = 0, b = 1) => Math.max(a, Math.min(b, x));
const lerp = (a, b, t) => a + (b - a) * t;

// ── colour
function hexToRgb(hex) { const v = parseInt(hex.replace('#', ''), 16); return [(v >> 16) & 255, (v >> 8) & 255, v & 255]; }
function rgbToHex([r, g, b]) { return '#' + [r, g, b].map(x => Math.round(clamp(x, 0, 255)).toString(16).padStart(2, '0')).join(''); }
const s2l = c => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
const l2s = c => { c = c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(Math.max(c, 0), 1 / 2.4) - 0.055; return clamp(c, 0, 1) * 255; };
function rgbToLab(rgb) {
  const [r, g, b] = rgb.map(s2l);
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s, 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s];
}
function labToRgb([L, A, B]) {
  const l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3;
  const m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3;
  const s = (L - 0.0894841775 * A - 1.2914855480 * B) ** 3;
  return [l2s(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s), l2s(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s), l2s(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)];
}
const hexLab = h => rgbToLab(hexToRgb(h));
const labHex = l => rgbToHex(labToRgb(l));
function mixLab(a, b, t) { return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)]; }
function hsvToRgb(h, s, v) {
  const i = Math.floor(h * 6) % 6, f = h * 6 - Math.floor(h * 6), p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
  const [r, g, b] = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][i];
  return [r * 255, g * 255, b * 255];
}
const luminance = rgb => { const [r, g, b] = rgb.map(s2l); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };

// ── value noise (seeded), for the domain warp
function hash2(ix, iy, s) {
  let h = Math.imul(ix, 374761393) ^ Math.imul(iy, 668265263) ^ Math.imul(s, 1442695041);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
}
function vnoise(x, y, s) {
  const ix = Math.floor(x), iy = Math.floor(y), fx = x - ix, fy = y - iy;
  const ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
  const a = hash2(ix, iy, s), b = hash2(ix + 1, iy, s), c = hash2(ix, iy + 1, s), d = hash2(ix + 1, iy + 1, s);
  return lerp(lerp(a, b, ux), lerp(c, d, ux), uy);
}
const fbm = (x, y, s) => 0.65 * vnoise(x, y, s) + 0.35 * vnoise(x * 2.03 + 11.1, y * 2.03 + 7.7, s + 7);

// ── inputs → numbers
function altitudeMeters(raw) {
  const nums = String(raw || '').replace(/[\s .]/g, '').match(/\d{3,4}/g);
  if (!nums) return null;
  const v = nums.slice(0, 2).map(Number);
  return v.reduce((a, b) => a + b, 0) / v.length;
}

function makeArt(card) {
  const seed = fnv1a(String(card.id).toLowerCase());
  const rnd = rngFrom(seed);
  const iso = ORIGIN_CODE[(card.country || '').trim()] || null;
  const terroir = (iso && TERROIR[iso]) || TERROIR_UNKNOWN;
  const procKey = classifyProcess(card.process);
  const proc = PROCESS[procKey];
  const roast = ROAST[card.roast] || null;
  const alt = altitudeMeters(card.altitude);
  const h = alt == null ? 0.5 : clamp((alt - 900) / 1300);

  // Notes → aroma colours (max three, the face rule)
  const notes = (card.notes || []).filter(n => n && n.trim()).slice(0, 3);
  const aromas = notes.map(n => ({ note: n, a: matchAroma(n) })).filter(x => x.a);
  let fieldColors = aromas.map(x => x.a.c);
  let notesSource = 'notes';
  if (fieldColors.length === 0) {
    notesSource = card.inkHue != null ? 'ink+terroir' : 'terroir';
    fieldColors = [terroir[1], terroir[2], labHex(mixLab(hexLab(terroir[1]), hexLab(terroir[0]), 0.45))];
    if (card.inkHue != null) fieldColors[0] = rgbToHex(hsvToRgb(card.inkHue, 0.62, 0.78));
  } else if (fieldColors.length < 3) {
    fieldColors = fieldColors.concat([terroir[1], terroir[2]]).slice(0, 3);
  }

  // Sky: warm haze at low altitude, cool clear air up high, tinted by the lightest field colour.
  const lightest = fieldColors.map(hexLab).sort((a, b) => b[0] - a[0])[0];
  let sky = mixLab(hexLab('#F4DDB7'), hexLab('#EAF1EF'), h);
  sky = mixLab(sky, lightest, 0.18);
  sky[0] = Math.max(sky[0], 0.9);

  const blobs = [];
  const j = (a) => (rnd() - 0.5) * 2 * a;
  // ground: the terroir, under the label
  blobs.push({ x: 0.5 + j(0.15), y: 1.06 + 0.06 * h, sx: 0.78, sy: 0.30, rot: j(0.4), w: 1.15, lab: hexLab(terroir[0]), role: 'ground' });
  blobs.push({ x: rnd() < 0.5 ? 0.08 : 0.92, y: 0.9, sx: 0.28, sy: 0.18, rot: j(0.6), w: 0.5, lab: hexLab(terroir[1]), role: 'terroir' });
  // sky: altitude sets how much air there is above the coffee
  blobs.push({ x: 0.5 + j(0.2), y: -0.1, sx: 0.85, sy: 0.18 + 0.26 * h, rot: j(0.3), w: 0.5 + 0.75 * h, lab: sky, role: 'sky' });
  // notes: the middle of the card
  const layouts = [
    [[0.28, 0.36], [0.74, 0.52], [0.38, 0.72]],
    [[0.72, 0.32], [0.26, 0.54], [0.66, 0.76]],
    [[0.5, 0.38], [0.18, 0.66], [0.84, 0.64]],
    [[0.3, 0.28], [0.72, 0.44], [0.5, 0.7]],
  ];
  const slots = layouts[Math.floor(rnd() * layouts.length)];
  const weights = [1.0, 0.86, 0.74];
  fieldColors.forEach((c, i) => {
    const s = slots[i];
    let lab = hexLab(c);
    if (proc.warm) lab = [lab[0], lab[1] + proc.warm, lab[2] + proc.warm * 0.6];
    blobs.push({ x: s[0] + j(0.06), y: s[1] + j(0.06), sx: 0.2 + rnd() * 0.12, sy: 0.18 + rnd() * 0.12, rot: j(1.5), w: weights[i], lab, role: 'note' });
  });
  // the bag's own ink, small, near an edge
  let inkHex = null;
  if (card.inkHue != null) {
    inkHex = rgbToHex(hsvToRgb(card.inkHue, 0.72, 0.84));
    blobs.push({ x: rnd() < 0.5 ? 0.06 + rnd() * 0.12 : 0.82 + rnd() * 0.12, y: 0.16 + rnd() * 0.4, sx: 0.12, sy: 0.12, rot: 0, w: 0.62, lab: hexLab(inkHex), role: 'ink' });
  }
  if (proc.extra) {
    blobs.push({ x: 0.2 + rnd() * 0.6, y: 0.45 + rnd() * 0.3, sx: proc.extra.s, sy: proc.extra.s * 0.9, rot: j(1), w: proc.extra.w, lab: hexLab(proc.extra.c), role: 'process' });
  }
  for (const b of blobs) { b.cos = Math.cos(b.rot); b.sin = Math.sin(b.rot); }

  // Title ink for the label: the first note, deepened (the current card darkens the wheel family instead).
  const titleBase = aromas.length ? hexLab(aromas[0].a.c) : card.inkHue != null ? hexLab(rgbToHex(hsvToRgb(card.inkHue, 0.62, 0.5))) : hexLab(terroir[0]);
  const chromaT = Math.hypot(titleBase[1], titleBase[2]);
  const k = chromaT > 0.0001 ? Math.min(1, 0.13 / chromaT) : 1;
  const titleInk = labHex([0.36, titleBase[1] * k, titleBase[2] * k]);

  return {
    seed, rnd, iso, terroir, procKey, proc, roast, alt, h, aromas, notesSource, fieldColors, sky, blobs, inkHex, titleInk,
    warpSeed: seed % 9973, chroma: proc.chroma * (card.decaf ? 0.7 : 1), dL: (roast ? roast.dL : 0.02) - (proc.darken || 0),
    side: rnd() < 0.68 ? 'right' : 'left', stickerRot: j(9), symbolRnd: [rnd(), rnd(), rnd(), rnd(), rnd()],
  };
}

// The field: normalised gaussian mix in OKLab ("mesh" without muddy alpha stacking), domain-warped.
function fieldColor(art, u, v) {
  const p = art.proc;
  let x = u, y = v;
  if (p.warp > 0) {
    x += p.warp * (fbm(u * 2.2 + 3.1, v * 2.2, art.warpSeed) - 0.5) * 2;
    y += p.warp * (fbm(u * 2.2, v * 2.2 + 5.3, art.warpSeed + 1) - 0.5) * 2;
  }
  if (p.swirl) {
    const dx = x - 0.5, dy = (y - 0.55) * 1.25, r = Math.hypot(dx, dy);
    const a = p.swirl * Math.exp(-r * r * 6);
    const ca = Math.cos(a), sa = Math.sin(a);
    x = 0.5 + dx * ca - dy * sa; y = 0.55 + (dx * sa + dy * ca) / 1.25;
  }
  let L = 0, A = 0, B = 0, W = 0;
  for (const b of art.blobs) {
    const dx = x - b.x, dy = (y - b.y) * 1.25;
    const rx = (dx * b.cos + dy * b.sin) / b.sx, ry = (-dx * b.sin + dy * b.cos) / b.sy;
    const w = Math.pow(b.w * Math.exp(-0.5 * (rx * rx + ry * ry)), p.sharp);
    L += w * b.lab[0]; A += w * b.lab[1]; B += w * b.lab[2]; W += w;
  }
  const g = art.blobs[0].lab, e = 1e-4;
  L = (L + e * g[0]) / (W + e); A = (A + e * g[1]) / (W + e); B = (B + e * g[2]) / (W + e);
  L += art.dL + 0.03 * (1 - v) * art.h - 0.02 * v;
  return [L, A * art.chroma, B * art.chroma];
}

// Low-res field (smooth by nature), upscaled, then grain at full resolution.
const FIELD_W = 96, FIELD_H = 120;
function renderField(art) {
  const c = document.createElement('canvas');
  c.width = FIELD_W; c.height = FIELD_H;
  const ctx = c.getContext('2d');
  const img = ctx.createImageData(FIELD_W, FIELD_H);
  let lumSum = 0, lumTop = 0, nTop = 0;
  for (let y = 0; y < FIELD_H; y++) {
    for (let x = 0; x < FIELD_W; x++) {
      const rgb = labToRgb(fieldColor(art, (x + 0.5) / FIELD_W, (y + 0.5) / FIELD_H));
      const i = (y * FIELD_W + x) * 4;
      img.data[i] = rgb[0]; img.data[i + 1] = rgb[1]; img.data[i + 2] = rgb[2]; img.data[i + 3] = 255;
      const lu = luminance(rgb);
      lumSum += lu;
      if (y < FIELD_H * 0.36 && x < FIELD_W * 0.75) { lumTop += lu; nTop++; }
    }
  }
  ctx.putImageData(img, 0, 0);
  art.lumMean = lumSum / (FIELD_W * FIELD_H);
  art.lumTop = lumTop / nTop;
  art.textTone = art.lumTop > 0.42 ? 'ink' : 'paper';
  return c;
}

let GRAIN_TILE = null;
function grainTile() {
  if (GRAIN_TILE) return GRAIN_TILE;
  const c = document.createElement('canvas'); c.width = c.height = 256;
  const ctx = c.getContext('2d'); const img = ctx.createImageData(256, 256); const r = rngFrom(20261025);
  for (let i = 0; i < 256 * 256; i++) {
    const g = (r() + r() + r() - 1.5) * 1.15; // roughly gaussian
    const sparkle = r() < 0.012 ? (r() < 0.5 ? -70 : 70) : 0; // airbrush spatter
    const v = clamp(128 + g * 52 + sparkle, 0, 255);
    img.data[i * 4] = img.data[i * 4 + 1] = img.data[i * 4 + 2] = v; img.data[i * 4 + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
  GRAIN_TILE = c; return c;
}

// ── symbol treatments. `mask` is the extracted drawing: dark ink on transparent.
function offscreen(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
function tinted(mask, color) {
  const c = offscreen(mask.width, mask.height), x = c.getContext('2d');
  x.drawImage(mask, 0, 0); x.globalCompositeOperation = 'source-in'; x.fillStyle = color; x.fillRect(0, 0, c.width, c.height);
  return c;
}
function placedMask(sym, art, W, H, kind) {
  const r = art.symbolRnd;
  const m = offscreen(W, H), x = m.getContext('2d');
  const asp = sym.img.width / sym.img.height;
  let w = W * (1.0 + r[0] * 0.35);
  if (w / asp > H * 1.05) w = H * 1.05 * asp;
  const cx = W * (0.56 + r[1] * 0.18), cy = H * (0.3 + r[2] * 0.14), rot = (r[3] - 0.5) * 0.45;
  x.translate(cx, cy); x.rotate(rot);
  x.drawImage(sym.img, -w / 2, -w / asp / 2, w, w / asp);
  return m;
}
function drawSymbol(ctx, art, sym, kind, W, H) {
  if (!sym || kind === 'none') return;
  const o = Math.max(2, W * 0.0055);
  if (kind === 'pattern') {
    const m = offscreen(W, H), x = m.getContext('2d');
    const asp = sym.img.width / sym.img.height, s = W * 0.15, gap = s * 1.55;
    x.translate(W / 2, H / 2); x.rotate(-0.21); x.translate(-W, -H);
    for (let row = 0, yy = 0; yy < H * 2; row++, yy += gap * 0.9) {
      for (let xx = (row % 2) * gap / 2; xx < W * 2; xx += gap) {
        const w = asp >= 1 ? s : s * asp, h = asp >= 1 ? s / asp : s;
        x.drawImage(sym.img, xx - w / 2, yy - h / 2, w, h);
      }
    }
    const dark = art.textTone === 'ink';
    ctx.save(); ctx.globalCompositeOperation = dark ? 'multiply' : 'screen'; ctx.globalAlpha = dark ? 0.2 : 0.17;
    ctx.drawImage(tinted(m, dark ? '#3a2a20' : '#fff6e6'), 0, 0); ctx.restore();
    return;
  }
  const m = placedMask(sym, art, W, H, kind);
  if (kind === 'emboss') {
    // raised blind emboss: light top-left edge, shadow bottom-right edge, face barely lifted
    const hl = offscreen(W, H), hx = hl.getContext('2d');
    hx.drawImage(m, 0, 0); hx.globalCompositeOperation = 'destination-out'; hx.drawImage(m, o, o);
    const sh = offscreen(W, H), sx = sh.getContext('2d');
    sx.drawImage(m, o, o); sx.globalCompositeOperation = 'destination-out'; sx.drawImage(m, 0, 0);
    ctx.save();
    ctx.globalCompositeOperation = 'screen'; ctx.globalAlpha = 0.07; ctx.drawImage(tinted(m, '#ffffff'), 0, 0);
    ctx.globalAlpha = 0.55; ctx.drawImage(tinted(hl, '#fffaf0'), 0, 0);
    ctx.globalCompositeOperation = 'multiply'; ctx.globalAlpha = 0.5; ctx.drawImage(tinted(sh, '#2a1c12'), 0, 0);
    ctx.restore();
  } else if (kind === 'ink') {
    // screen-printed ink: misregistered second pass, speckled transfer
    const deep = labHex([0.3, art.blobs[3].lab[1] * 0.6, art.blobs[3].lab[2] * 0.6]);
    const pass = tinted(m, deep);
    const px = pass.getContext('2d');
    px.globalCompositeOperation = 'destination-out'; px.globalAlpha = 0.5;
    px.fillStyle = px.createPattern(grainTile(), 'repeat'); px.fillRect(0, 0, W, H);
    ctx.save();
    ctx.globalCompositeOperation = 'multiply';
    ctx.globalAlpha = 0.28; ctx.drawImage(tinted(m, art.inkHex || labHex(art.blobs[4] ? art.blobs[4].lab : art.blobs[1].lab)), o * 1.4, -o);
    ctx.globalAlpha = 0.62; ctx.drawImage(pass, 0, 0);
    ctx.restore();
  } else if (kind === 'halftone') {
    const cell = Math.max(5, W * 0.016), cols = Math.ceil(W / cell) + 2, rows = Math.ceil(H / cell) + 2;
    const small = offscreen(cols, rows), sx = small.getContext('2d');
    sx.drawImage(m, 0, 0, cols, rows);
    const data = sx.getImageData(0, 0, cols, rows).data;
    const dark = art.textTone === 'ink';
    ctx.save(); ctx.globalCompositeOperation = dark ? 'multiply' : 'screen';
    ctx.fillStyle = dark ? labHex([0.32, art.blobs[3].lab[1] * 0.5, art.blobs[3].lab[2] * 0.5]) : '#fff3df';
    ctx.globalAlpha = dark ? 0.75 : 0.7;
    for (let yy = 0; yy < rows; yy++) for (let xx = 0; xx < cols; xx++) {
      const a = data[(yy * cols + xx) * 4 + 3] / 255;
      if (a < 0.04) continue;
      const rr = cell * 0.52 * Math.sqrt(a);
      ctx.beginPath(); ctx.arc((xx + 0.5) * W / cols, (yy + 0.5) * H / rows, rr, 0, Math.PI * 2); ctx.fill();
    }
    ctx.restore();
  }
}

function autoTreatment(sym, art) {
  if (!sym) return { kind: 'none', why: 'pas de symbole extrait — le fond porte seul la carte' };
  const pick = art.symbolRnd[4];
  if (sym.small) return { kind: 'pattern', why: 'marque minuscule → motif répété (agrandie, elle serait floue)' };
  if (sym.coverage < 0.3) return pick < 0.55 ? { kind: 'emboss', why: 'dessin au trait → gaufrage' } : { kind: 'ink', why: 'dessin au trait → encre sérigraphiée' };
  return pick < 0.6 ? { kind: 'emboss', why: 'marque pleine → gaufrage' } : { kind: 'halftone', why: 'marque pleine → trame' };
}

// Full backdrop: field + symbol + grain + a whisper of vignette.
function paintBackdrop(canvas, art, sym, kind) {
  const W = canvas.width, H = canvas.height, ctx = canvas.getContext('2d');
  const field = art._field || (art._field = renderField(art));
  ctx.save(); ctx.imageSmoothingEnabled = true; ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(field, 0, 0, W, H); ctx.restore();
  drawSymbol(ctx, art, sym, kind, W, H);
  ctx.save(); ctx.globalCompositeOperation = 'overlay'; ctx.globalAlpha = art.proc.grain;
  const pat = ctx.createPattern(grainTile(), 'repeat');
  if (pat.setTransform) pat.setTransform(new DOMMatrix().scale(W / 720));
  ctx.fillStyle = pat; ctx.fillRect(0, 0, W, H); ctx.restore();
  ctx.save(); ctx.globalCompositeOperation = 'multiply';
  const g = ctx.createRadialGradient(W * 0.5, H * 0.45, W * 0.35, W * 0.5, H * 0.5, W * 0.95);
  g.addColorStop(0, 'rgba(255,255,255,0)'); g.addColorStop(1, 'rgba(60,40,25,0.22)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H); ctx.restore();
}
