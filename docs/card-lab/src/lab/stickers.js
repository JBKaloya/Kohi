// ───────────────────────── Stickers ─────────────────────────
// One origin = one sticker. Drawn from a recipe (shape, palette, scene, lettering), never from the card,
// so every Kenyan coffee wears the same Kenya sticker. Only its tilt and corner on a card come from the card seed.

const SHAPES = {
  oval: { d: 'M16 120 A104 72 0 1 1 224 120 A104 72 0 1 1 16 120 Z', top: 48, bottom: 192 },
  circle: { d: 'M26 120 A94 94 0 1 1 214 120 A94 94 0 1 1 26 120 Z', top: 26, bottom: 214, arc: 'M44 128 A76 76 0 0 1 196 128' },
  ticket: { d: 'M28 72 H212 Q228 72 228 88 V152 Q228 168 212 168 H28 Q12 168 12 152 V88 Q12 72 28 72 Z', top: 72, bottom: 168 },
  shield: { d: 'M40 40 H200 Q206 40 206 46 V118 Q206 182 120 218 Q34 182 34 118 V46 Q34 40 40 40 Z', top: 40, bottom: 218 },
  arch: { d: 'M26 200 V124 A94 94 0 0 1 214 124 V200 Q214 206 208 206 H32 Q26 206 26 200 Z', top: 30, bottom: 206 },
  hexa: { d: 'M14 120 L58 56 H182 L226 120 L182 184 H58 Z', top: 56, bottom: 184 },
  tri: { d: 'M120 22 Q126 22 129 27 L226 196 Q229 204 220 204 H20 Q11 204 14 196 L111 27 Q114 22 120 22 Z', top: 22, bottom: 204 },
  scallop: { d: null, top: 24, bottom: 216, arc: 'M46 126 A74 74 0 0 1 194 126' },
  banner: { d: 'M10 76 H230 L212 120 L230 164 H10 L28 120 Z', top: 76, bottom: 164 },
};
(function () { // scalloped badge edge
  let d = ''; const n = 22;
  for (let i = 0; i <= n * 2; i++) {
    const a = (i / (n * 2)) * Math.PI * 2 - Math.PI / 2, r = i % 2 ? 90 : 96;
    d += (i ? 'L' : 'M') + (120 + r * Math.cos(a)).toFixed(1) + ' ' + (120 + r * Math.sin(a)).toFixed(1) + ' ';
  }
  SHAPES.scallop.d = d + 'Z';
})();

// ── scene primitives (240 × 240 box)
const S = {
  rect: (y0, y1, c) => `<rect x="-10" y="${y0}" width="260" height="${y1 - y0}" fill="${c}"/>`,
  sun: ({ x, y, r, c, rays = 0, rc, spread = 0.09 }) => {
    let s = '';
    for (let i = 0; i < rays; i++) {
      const a = (i / rays) * Math.PI * 2, a1 = a - spread, a2 = a + spread, R = 260;
      s += `<path d="M${x} ${y} L${x + R * Math.cos(a1)} ${y + R * Math.sin(a1)} L${x + R * Math.cos(a2)} ${y + R * Math.sin(a2)} Z" fill="${rc}"/>`;
    }
    return s + `<circle cx="${x}" cy="${y}" r="${r}" fill="${c}"/>`;
  },
  range: ({ base, peaks, c, snow, valley = 0.38, floor = 260 }) => {
    const pts = [[-12, base]];
    peaks.forEach(([x, h], i) => {
      if (i) { const [px, ph] = peaks[i - 1]; pts.push([(px + x) / 2, base - Math.min(h, ph) * valley]); }
      pts.push([x, base - h]);
    });
    pts.push([252, base]);
    let s = `<path d="M${pts.map(p => p.join(' ')).join(' L')} L252 ${floor} L-12 ${floor} Z" fill="${c}"/>`;
    if (snow) {
      peaks.forEach(([x, h], i) => {
        const idx = pts.findIndex(p => p[0] === x && p[1] === base - h);
        const L = pts[idx - 1], R = pts[idx + 1], P = pts[idx], t = 0.3;
        const l = [lerp(P[0], L[0], t), lerp(P[1], L[1], t)], r = [lerp(P[0], R[0], t), lerp(P[1], R[1], t)];
        const z = (k, dy) => [lerp(l[0], r[0], k), lerp(l[1], r[1], k) + dy];
        const zz = [l, z(0.25, 5), z(0.5, -2), z(0.75, 5), r];
        s += `<path d="M${P.join(' ')} L${zz.map(p => p.map(v => v.toFixed(1)).join(' ')).join(' L')} Z" fill="${snow}"/>`;
      });
    }
    return s;
  },
  volcano: ({ x, base, w, h, c, plume, lip }) => {
    let s = `<path d="M${x - w / 2} ${base} L${x - w * 0.1} ${base - h} Q${x} ${base - h + 5} ${x + w * 0.1} ${base - h} L${x + w / 2} ${base} Z" fill="${c}"/>`;
    if (lip) s += `<path d="M${x - w * 0.1} ${base - h} Q${x} ${base - h + 5} ${x + w * 0.1} ${base - h} L${x + w * 0.16} ${base - h + 12} Q${x} ${base - h + 16} ${x - w * 0.16} ${base - h + 12} Z" fill="${lip}"/>`;
    if (plume) s += [[4, -10, 8], [14, -22, 11], [30, -32, 10], [46, -36, 8]].map(([dx, dy, r]) => `<circle cx="${x + dx}" cy="${base - h + dy}" r="${r}" fill="${plume}"/>`).join('');
    return s;
  },
  hills: ({ y, amp, freq = 0.035, phase = 0, c }) => {
    let d = `M-12 260 L-12 ${y}`;
    for (let x = -12; x <= 252; x += 8) d += ` L${x} ${(y + amp * Math.sin(x * freq + phase)).toFixed(1)}`;
    return `<path d="${d} L252 260 Z" fill="${c}"/>`;
  },
  rows: ({ y, amp, freq = 0.035, phase = 0, c, n = 4, gap = 7, sw = 2 }) => {
    let s = '';
    for (let k = 1; k <= n; k++) {
      let d = '';
      for (let x = -12; x <= 252; x += 8) d += (x === -12 ? 'M' : ' L') + `${x} ${(y + k * gap + amp * Math.sin(x * freq + phase)).toFixed(1)}`;
      s += `<path d="${d}" fill="none" stroke="${c}" stroke-width="${sw}" stroke-linecap="round"/>`;
    }
    return s;
  },
  waves: ({ y, c, n = 3, gap = 8, sw = 2.4 }) => {
    let s = '';
    for (let k = 0; k < n; k++) {
      let d = `M-12 ${y + k * gap}`;
      for (let x = -12; x < 252; x += 20) d += ` q5 -4 10 0 t10 0`;
      s += `<path d="${d}" fill="none" stroke="${c}" stroke-width="${sw}" stroke-linecap="round"/>`;
    }
    return s;
  },
  palm: ({ x, base, h, c, lean = 6 }) => {
    const tx = x + lean, ty = base - h;
    let s = `<path d="M${x} ${base} Q${x + lean * 0.2} ${base - h * 0.5} ${tx} ${ty}" fill="none" stroke="${c}" stroke-width="3.4" stroke-linecap="round"/>`;
    [[-20, 8], [-14, -6], [-4, -12], [8, -12], [18, -4], [22, 10]].forEach(([dx, dy]) => {
      s += `<path d="M${tx} ${ty} Q${tx + dx * 0.5} ${ty + dy - 8} ${tx + dx} ${ty + dy}" fill="none" stroke="${c}" stroke-width="3" stroke-linecap="round"/>`;
    });
    return s;
  },
  acacia: ({ x, base, s = 1, c }) => `<path d="M${x} ${base} L${x} ${base - 22 * s} M${x} ${base - 14 * s} L${x - 9 * s} ${base - 26 * s} M${x} ${base - 16 * s} L${x + 10 * s} ${base - 27 * s}" stroke="${c}" stroke-width="${3 * s}" stroke-linecap="round" fill="none"/><ellipse cx="${x}" cy="${base - 29 * s}" rx="${30 * s}" ry="${7 * s}" fill="${c}"/>`,
  pines: ({ base, xs, c }) => xs.map(([x, h]) => `<path d="M${x} ${base - h} L${x + h * 0.3} ${base - h * 0.45} L${x + h * 0.16} ${base - h * 0.47} L${x + h * 0.38} ${base} L${x - h * 0.38} ${base} L${x - h * 0.16} ${base - h * 0.47} L${x - h * 0.3} ${base - h * 0.45} Z" fill="${c}"/>`).join(''),
  baobab: ({ x, base, h, c }) => `<path d="M${x - 9} ${base} L${x - 7} ${base - h * 0.62} Q${x} ${base - h * 0.68} ${x + 7} ${base - h * 0.62} L${x + 9} ${base} Z" fill="${c}"/><path d="M${x - 5} ${base - h * 0.6} L${x - 16} ${base - h * 0.9} M${x} ${base - h * 0.62} L${x} ${base - h} M${x + 5} ${base - h * 0.6} L${x + 17} ${base - h * 0.86}" stroke="${c}" stroke-width="3" stroke-linecap="round"/><circle cx="${x - 16}" cy="${base - h * 0.92}" r="6" fill="${c}"/><circle cx="${x}" cy="${base - h - 2}" r="7" fill="${c}"/><circle cx="${x + 17}" cy="${base - h * 0.88}" r="6" fill="${c}"/>`,
  agave: ({ x, base, s = 1, c, tip }) => [-70, -48, -26, -8, 8, 26, 48, 70].map((deg, i) => {
    const a = (deg - 90) * Math.PI / 180, L = (i % 2 ? 50 : 40) * s, w = 6 * s;
    const tx = x + L * Math.cos(a), ty = base + L * Math.sin(a), nx = -Math.sin(a) * w, ny = Math.cos(a) * w;
    return `<path d="M${x + nx} ${base + ny} L${tx} ${ty} L${x - nx} ${base - ny} Z" fill="${i % 2 ? c : tip || c}"/>`;
  }).join(''),
  towers: ({ base, c, win }) => [[62, 70, 26], [96, 104, 30], [134, 86, 28], [168, 60, 24]].map(([x, h, w]) => {
    let s = `<rect x="${x - w / 2}" y="${base - h}" width="${w}" height="${h + 20}" fill="${c}"/>`;
    for (let yy = base - h + 10; yy < base - 8; yy += 14) for (let xx = x - w / 2 + 6; xx < x + w / 2 - 6; xx += 9) s += `<rect x="${xx}" y="${yy}" width="4" height="6" rx="2" fill="${win}"/>`;
    return s + `<rect x="${x - w / 2}" y="${base - h + 3}" width="${w}" height="2.4" fill="${win}"/>`;
  }).join(''),
  terraces: ({ y0, n, gap, c1, c2, bow = 16 }) => {
    let s = '';
    for (let i = 0; i < n; i++) { const y = y0 + i * gap; s += `<path d="M-12 ${y + bow} Q120 ${y - bow} 252 ${y + bow} L252 ${y + bow + gap + 2} Q120 ${y - bow + gap + 2} -12 ${y + bow + gap + 2} Z" fill="${i % 2 ? c2 : c1}"/>`; }
    return s;
  },
  cherries: ({ x, y, s = 1, c, leaf, stem }) => `<path d="M${x - 30 * s} ${y - 18 * s} Q${x} ${y - 30 * s} ${x + 30 * s} ${y - 14 * s}" fill="none" stroke="${stem}" stroke-width="${2.6 * s}" stroke-linecap="round"/><ellipse cx="${x - 16 * s}" cy="${y - 34 * s}" rx="${13 * s}" ry="${5.5 * s}" transform="rotate(-28 ${x - 16 * s} ${y - 34 * s})" fill="${leaf}"/><ellipse cx="${x + 18 * s}" cy="${y - 30 * s}" rx="${13 * s}" ry="${5.5 * s}" transform="rotate(24 ${x + 18 * s} ${y - 30 * s})" fill="${leaf}"/>` + [[-9, -8], [3, -4], [14, -9]].map(([dx, dy]) => `<circle cx="${x + dx * s}" cy="${y + dy * s}" r="${7 * s}" fill="${c}"/><circle cx="${x + dx * s - 2.4 * s}" cy="${y + dy * s - 2.4 * s}" r="${1.8 * s}" fill="#fff" opacity=".8"/>`).join(''),
  birds: ({ pts, c }) => pts.map(([x, y, s]) => `<path d="M${x - s} ${y} Q${x - s / 2} ${y - s * 0.6} ${x} ${y} Q${x + s / 2} ${y - s * 0.6} ${x + s} ${y}" fill="none" stroke="${c}" stroke-width="2.2" stroke-linecap="round"/>`).join(''),
  clouds: ({ pts, c }) => pts.map(([x, y, s]) => `<path d="M${x - 16 * s} ${y} a${7 * s} ${7 * s} 0 0 1 ${10 * s} ${-7 * s} a${9 * s} ${9 * s} 0 0 1 ${16 * s} ${-2 * s} a${7 * s} ${7 * s} 0 0 1 ${8 * s} ${9 * s} Z" fill="${c}"/>`).join(''),
  lake: ({ x, y, rx, ry, c }) => `<ellipse cx="${x}" cy="${y}" rx="${rx}" ry="${ry}" fill="${c}"/>`,
  karst: ({ base, xs, c }) => xs.map(([x, h, w]) => `<path d="M${x - w / 2} ${base} C${x - w / 2} ${base - h * 0.7} ${x - w * 0.35} ${base - h} ${x} ${base - h} C${x + w * 0.35} ${base - h} ${x + w / 2} ${base - h * 0.7} ${x + w / 2} ${base} Z" fill="${c}"/>`).join(''),
  line: ({ y, c, dash = '6 5', sw = 2 }) => `<path d="M-12 ${y} H252" stroke="${c}" stroke-width="${sw}" stroke-dasharray="${dash}"/>`,
  drop: ({ x, y, s = 1, c }) => `<path d="M${x} ${y - 30 * s} C${x + 4 * s} ${y - 18 * s} ${x + 20 * s} ${y - 4 * s} ${x + 20 * s} ${y + 8 * s} A${20 * s} ${20 * s} 0 0 1 ${x - 20 * s} ${y + 8 * s} C${x - 20 * s} ${y - 4 * s} ${x - 4 * s} ${y - 18 * s} ${x} ${y - 30 * s} Z" fill="${c}"/>`,
  combs: ({ x, y, r = 11, c, c2 }) => [[0, 0], [r * 1.73, 0], [-r * 1.73, 0], [r * 0.87, r * 1.5], [-r * 0.87, r * 1.5], [r * 0.87, -r * 1.5], [-r * 0.87, -r * 1.5]].map(([dx, dy], i) => {
    let d = ''; for (let k = 0; k < 6; k++) { const a = Math.PI / 6 + k * Math.PI / 3; d += (k ? 'L' : 'M') + (x + dx + (r - 1.6) * Math.cos(a)).toFixed(1) + ' ' + (y + dy + (r - 1.6) * Math.sin(a)).toFixed(1); }
    return `<path d="${d}Z" fill="${i % 3 ? c : c2}"/>`;
  }).join(''),
  bubbles: ({ x, y, c }) => [[0, 0, 12], [-18, 14, 8], [16, 16, 9], [-6, -22, 7], [20, -12, 5], [-22, -6, 5]].map(([dx, dy, r]) => `<circle cx="${x + dx}" cy="${y + dy}" r="${r}" fill="none" stroke="${c}" stroke-width="3"/>`).join(''),
  bean: ({ x, y, s = 1, c, cut }) => `<ellipse cx="${x}" cy="${y}" rx="${17 * s}" ry="${24 * s}" transform="rotate(-28 ${x} ${y})" fill="${c}"/><path d="M${x - 6 * s} ${y - 20 * s} Q${x + 6 * s} ${y} ${x + 4 * s} ${y + 20 * s}" stroke="${cut}" stroke-width="${3 * s}" fill="none" stroke-linecap="round"/>`,
};

const TYPE = {
  italic: "font-family:'DM Serif Display',Georgia,serif;font-style:italic;font-weight:400",
  condensed: "font-family:Archivo,'Arial Narrow',sans-serif;font-stretch:62%;font-weight:900",
  expanded: "font-family:Archivo,'Arial Black',sans-serif;font-stretch:125%;font-weight:800",
  spaced: "font-family:Archivo,Arial,sans-serif;font-stretch:100%;font-weight:700;letter-spacing:.24em",
  arched: "font-family:Archivo,Arial,sans-serif;font-stretch:112%;font-weight:800;letter-spacing:.06em",
};

// Recipes. Palettes are vintage-printed (slightly off, slightly warm). Scenes are landscapes and plants
// of each origin: no flags, no monuments, no animals that read as a brand.
const P = { ink: '#21201f', cream: '#F4E7C8', paper: '#FBF6EA' };
const STICKERS = {
  ET: { shape: 'shield', bg: '#F1DFAF', ink: '#1F2A1C', scene: () =>
      S.sun({ x: 120, y: 112, r: 26, c: '#E9A93B', rays: 14, rc: '#F3CB6E' }) + S.hills({ y: 118, amp: 7, phase: 1, c: '#5E8A3E' }) + S.hills({ y: 132, amp: 6, freq: 0.05, c: '#2E4A2A' }) +
      S.cherries({ x: 120, y: 150, s: 0.9, c: '#C63A2E', leaf: '#8FB55A', stem: '#F1DFAF' }) + S.rect(164, 196, '#B83A2B'),
    name: { t: 'ETHIOPIA', style: 'spaced', y: 186, w: 104, size: 15, fill: P.paper, stroke: 'none', shadow: '#5a1a12' } },
  KE: { shape: 'oval', bg: '#F4D59C', ink: '#2A1F1A', scene: () =>
      S.sun({ x: 156, y: 90, r: 22, c: '#D9482B' }) + S.range({ base: 140, peaks: [[86, 52], [112, 76], [136, 58], [168, 34]], c: '#4D5E8C', snow: '#F6F1E6' }) +
      S.rect(138, 200, '#B5562A') + S.acacia({ x: 58, base: 140, s: 0.9, c: '#2A1F1A' }),
    name: { t: 'KENYA', style: 'italic', y: 180, w: 132, size: 44, fill: '#F6C343', stroke: '#2A1F1A', shadow: '#2A1F1A' } },
  CO: { shape: 'banner', bg: '#9CCFE0', ink: '#14283A', scene: () =>
      S.hills({ y: 120, amp: 9, phase: 2, c: '#4E8F3E' }) + S.palm({ x: 40, base: 128, h: 48, c: '#173B2C', lean: 4 }) + S.palm({ x: 206, base: 128, h: 54, c: '#173B2C', lean: -6 }) +
      S.rect(128, 170, '#173B2C'),
    name: { t: 'COLOMBIA', style: 'condensed', y: 113, w: 128, size: 40, fill: '#F4C531', stroke: '#14283A', shadow: '#14283A' } },
  BR: { shape: 'arch', bg: '#F6DE9C', ink: '#203018', scene: () =>
      S.sun({ x: 120, y: 92, r: 30, c: '#E8A33A', rays: 18, rc: '#F2C86A' }) + S.hills({ y: 118, amp: 10, freq: 0.03, c: '#6FA34A' }) + S.rows({ y: 116, amp: 10, freq: 0.03, c: '#3E7B3A', n: 5, gap: 8 }) +
      S.rect(164, 210, '#2F6B3A'),
    name: { t: 'BRAZIL', style: 'condensed', y: 196, w: 120, size: 34, fill: P.paper, stroke: '#203018', shadow: '#1b2a14' } },
  PE: { shape: 'hexa', bg: '#F3D3A6', ink: '#3A1A1A', scene: () =>
      S.range({ base: 128, peaks: [[48, 46], [92, 70], [140, 54], [190, 64]], c: '#7A4A6E', snow: '#FBF2E4' }) + S.terraces({ y0: 124, n: 5, gap: 9, c1: '#C2452E', c2: '#D9853A', bow: 6 }),
    name: { t: 'PERU', style: 'expanded', y: 104, w: 112, size: 30, fill: '#FBF2E4', stroke: '#3A1A1A', shadow: '#3A1A1A' } },
  GT: { shape: 'scallop', bg: '#BFE0E3', ink: '#1E2533', scene: () =>
      S.volcano({ x: 72, base: 150, w: 92, h: 66, c: '#3B4A5E' }) + S.volcano({ x: 168, base: 150, w: 100, h: 78, c: '#2E3B4E', plume: '#EEF4F2' }) + S.volcano({ x: 120, base: 150, w: 70, h: 44, c: '#4D5E74' }) +
      S.rect(148, 220, '#3A8EA8') + S.waves({ y: 158, c: '#BFE0E3', n: 1, gap: 9, sw: 2 }) + S.rect(170, 196, '#E0563A'),
    name: { t: 'GUATEMALA', style: 'condensed', y: 191, w: 112, size: 22, fill: P.paper, stroke: 'none', shadow: '#7a2412' } },
  PA: { shape: 'arch', bg: '#F7CF9A', ink: '#17262E', scene: () =>
      S.sun({ x: 150, y: 100, r: 20, c: '#F06A3A' }) + S.volcano({ x: 104, base: 160, w: 170, h: 96, c: '#23434A' }) + S.hills({ y: 146, amp: 6, freq: 0.06, c: '#2E8B7A' }) + S.clouds({ pts: [[74, 104, 1], [168, 126, 0.8]], c: '#FBEFE0' }) +
      S.birds({ pts: [[176, 74, 7], [190, 84, 5]], c: '#17262E' }) + S.rect(160, 210, '#17262E'),
    name: { t: 'PANAMA', style: 'italic', y: 194, w: 124, size: 36, fill: '#F7CF9A', stroke: 'none', shadow: '#0b1418' } },
  HN: { shape: 'oval', bg: '#CFE6E2', ink: '#162C38', scene: () =>
      S.range({ base: 130, peaks: [[60, 40], [110, 58], [170, 48]], c: '#6B8FA8' }) + S.pines({ base: 140, xs: [[40, 34], [62, 44], [86, 30], [150, 38], [176, 46], [200, 32]], c: '#2E5A3E' }) + S.rect(138, 200, '#E0A32E'),
    name: { t: 'HONDURAS', style: 'expanded', y: 170, w: 150, size: 24, fill: '#162C38', stroke: 'none', shadow: '#F7E3B0' } },
  CR: { shape: 'hexa', bg: '#F5D8B0', ink: '#16281E', scene: () =>
      S.volcano({ x: 118, base: 140, w: 140, h: 78, c: '#6E4A3E', lip: '#E2643A', plume: '#FBF2E4' }) + S.hills({ y: 132, amp: 8, freq: 0.05, c: '#2F7A48' }) + S.hills({ y: 146, amp: 6, freq: 0.07, phase: 2, c: '#1B3828' }),
    name: { t: 'COSTA RICA', style: 'condensed', y: 177, w: 140, size: 30, fill: '#F5D8B0', stroke: '#16281E', shadow: '#16281E' } },
  SV: { shape: 'ticket', bg: '#F0D9A0', ink: '#1E2836', scene: () =>
      S.volcano({ x: 58, base: 132, w: 92, h: 50, c: '#3A4A62' }) + S.rect(126, 170, '#3A6EA5') + S.waves({ y: 138, c: '#9CC2E0', n: 2, gap: 9, sw: 2 }),
    name: { t: 'EL SALVADOR', style: 'condensed', y: 114, w: 104, size: 26, fill: '#1E2836', stroke: 'none', shadow: '#E3B23A', x: 158 } },
  NI: { shape: 'circle', bg: '#F2E2B6', ink: '#1F2A22', scene: () =>
      S.rect(130, 230, '#3A7EA0') + S.volcano({ x: 96, base: 136, w: 74, h: 56, c: '#2B3828' }) + S.volcano({ x: 146, base: 136, w: 62, h: 42, c: '#3E5236' }) + S.waves({ y: 150, c: '#A8D0E0', n: 3, gap: 10, sw: 2 }),
    name: { t: 'NICARAGUA', style: 'arched', size: 21, fill: '#1F2A22', arc: true } },
  MX: { shape: 'scallop', bg: '#F7C9B8', ink: '#2A1A14', scene: () =>
      S.sun({ x: 120, y: 98, r: 34, c: '#F2A33A' }) + S.agave({ x: 120, base: 160, s: 1.1, c: '#2E8A6A', tip: '#1E5E48' }) + S.rect(158, 220, '#D2483A'),
    name: { t: 'MEXICO', style: 'italic', y: 192, w: 110, size: 32, fill: P.paper, stroke: 'none', shadow: '#6a1a12' } },
  RW: { shape: 'banner', bg: '#F2E3A0', ink: '#14281E', scene: () =>
      S.sun({ x: 186, y: 100, r: 14, c: '#E8A33A' }) + S.hills({ y: 112, amp: 6, freq: 0.06, c: '#A9C76A' }) + S.hills({ y: 124, amp: 7, freq: 0.05, phase: 2, c: '#6FA35A' }) +
      S.hills({ y: 138, amp: 6, freq: 0.07, phase: 4, c: '#3E7B4A' }) + S.hills({ y: 152, amp: 5, freq: 0.06, phase: 1, c: '#1E4434' }),
    name: { t: 'RWANDA', style: 'condensed', y: 106, w: 92, size: 30, fill: '#14281E', stroke: 'none', shadow: '#F7EFC8', x: 92 } },
  BI: { shape: 'shield', bg: '#F0E2BE', ink: '#1F2A20', scene: () =>
      S.sun({ x: 120, y: 98, r: 28, c: '#C4483A' }) + S.hills({ y: 112, amp: 8, freq: 0.05, c: '#6E9A4E' }) + S.hills({ y: 128, amp: 7, freq: 0.06, phase: 3, c: '#3E6B3A' }) + S.rows({ y: 126, amp: 7, freq: 0.06, phase: 3, c: '#2A4A2A', n: 3, gap: 8 }) + S.rect(160, 220, '#233F2C'),
    name: { t: 'BURUNDI', style: 'spaced', y: 186, w: 118, size: 16, fill: '#F0E2BE', stroke: 'none', shadow: '#0f1a12' } },
  TZ: { shape: 'arch', bg: '#BFD9E6', ink: '#2A2018', scene: () =>
      S.range({ base: 140, peaks: [[84, 40], [120, 64], [162, 44]], c: '#4E6E8C', snow: '#FBF7EE', valley: 0.6 }) + S.rect(138, 210, '#D9A85A') + S.acacia({ x: 176, base: 150, s: 1, c: '#2F2620' }),
    name: { t: 'TANZANIA', style: 'italic', y: 190, w: 140, size: 32, fill: '#2F2620', stroke: 'none', shadow: '#F4E2B8' } },
  UG: { shape: 'oval', bg: '#F3D7A0', ink: '#1F2A16', scene: () =>
      S.sun({ x: 120, y: 92, r: 22, c: '#C9982E', rays: 12, rc: '#F0C77A' }) + S.range({ base: 136, peaks: [[64, 40], [100, 56], [140, 46], [176, 60]], c: '#2B3820', snow: '#F6F1E6' }) + S.rect(134, 200, '#A23A2A'),
    name: { t: 'UGANDA', style: 'expanded', y: 170, w: 128, size: 26, fill: P.paper, stroke: 'none', shadow: '#4a120c' } },
  ID: { shape: 'hexa', bg: '#F2D29C', ink: '#132420', scene: () =>
      S.volcano({ x: 130, base: 130, w: 150, h: 68, c: '#1B2B23', plume: '#FBF2E4' }) + S.terraces({ y0: 120, n: 3, gap: 9, c1: '#6FA34A', c2: '#A9C76A', bow: 8 }) + S.rect(146, 190, '#2E7A6A') + S.waves({ y: 156, c: '#9CD0C2', n: 2, gap: 9, sw: 2 }),
    name: { t: 'INDONESIA', style: 'condensed', y: 98, w: 84, size: 24, fill: '#132420', stroke: 'none', shadow: '#F7E7C2', x: 90 } },
  YE: { shape: 'shield', bg: '#F0D2A0', ink: '#2A1A10', scene: () =>
      S.sun({ x: 168, y: 78, r: 16, c: '#E06A3A' }) + S.towers({ base: 160, c: '#9A5A30', win: '#FBF2E4' }) + S.rect(160, 220, '#4A311F'),
    name: { t: 'YEMEN', style: 'spaced', y: 192, w: 104, size: 17, fill: '#F0D2A0', stroke: 'none', shadow: '#1a0e06' } },
  IN: { shape: 'scallop', bg: '#F3D19A', ink: '#1E2A18', scene: () =>
      S.sun({ x: 120, y: 104, r: 28, c: '#E07A2A' }) + S.clouds({ pts: [[86, 98, 1.1], [168, 88, 0.9]], c: '#FBF2E4' }) + S.hills({ y: 132, amp: 8, freq: 0.05, c: '#3A6A4A' }) + S.rows({ y: 132, amp: 8, freq: 0.05, c: '#2B3824', n: 3, gap: 8 }) + S.rect(164, 220, '#3A6A8A'),
    name: { t: 'INDIA', style: 'expanded', y: 196, w: 100, size: 26, fill: P.paper, stroke: 'none', shadow: '#16283a' } },
  VN: { shape: 'ticket', bg: '#F2E2B0', ink: '#162A1E', scene: () =>
      S.karst({ base: 150, xs: [[36, 56, 30], [64, 40, 26], [204, 60, 32]], c: '#2E5A3E' }) + S.rect(140, 170, '#3A8A7A') + S.sun({ x: 182, y: 96, r: 12, c: '#C2342A' }),
    name: { t: 'VIETNAM', style: 'italic', y: 132, w: 108, size: 34, fill: '#C2342A', stroke: 'none', shadow: '#162A1E', x: 126 } },
  TH: { shape: 'tri', bg: '#F4DCB4', ink: '#1E1A2A', scene: () =>
      S.sun({ x: 120, y: 96, r: 18, c: '#E0603A' }) + S.hills({ y: 118, amp: 9, freq: 0.04, c: '#9A9AB8' }) + S.hills({ y: 134, amp: 8, freq: 0.05, phase: 2, c: '#6A6A90' }) + S.hills({ y: 150, amp: 7, freq: 0.06, phase: 4, c: '#3A7A5A' }) + S.rect(166, 210, '#2C2838'),
    name: { t: 'THAILAND', style: 'condensed', y: 194, w: 120, size: 24, fill: '#F4DCB4', stroke: 'none', shadow: '#0a0810' } },
  CN: { shape: 'circle', bg: '#F2DDB0', ink: '#1E2A20', scene: () =>
      S.sun({ x: 120, y: 112, r: 22, c: '#B83A2E' }) + S.terraces({ y0: 124, n: 6, gap: 10, c1: '#8AB06A', c2: '#5E8A4E', bow: 12 }),
    name: { t: 'CHINA', style: 'arched', size: 26, fill: '#1E2A20', arc: true } },
  PG: { shape: 'shield', bg: '#F4D3A0', ink: '#1E1410', scene: () =>
      S.range({ base: 132, peaks: [[56, 50], [104, 74], [150, 56], [190, 66]], c: '#2A1C18' }) + S.hills({ y: 132, amp: 6, freq: 0.06, c: '#3A6A3A' }) + S.birds({ pts: [[86, 82, 8], [104, 74, 6]], c: '#C23A2E' }) + S.rect(158, 220, '#C23A2E'),
    name: { t: 'PAPUA N.G.', style: 'condensed', y: 190, w: 114, size: 24, fill: '#F4D3A0', stroke: 'none', shadow: '#3a0e08' } },
  JM: { shape: 'oval', bg: '#F7D98C', ink: '#122436', scene: () =>
      S.sun({ x: 176, y: 92, r: 18, c: '#E06A3A' }) + S.range({ base: 132, peaks: [[54, 36], [96, 58], [140, 44]], c: '#2E4E7A' }) + S.range({ base: 140, peaks: [[120, 26], [176, 34]], c: '#3A8A4A' }) + S.rect(138, 200, '#1C3756') + S.waves({ y: 150, c: '#7FB0D8', n: 2, gap: 9, sw: 2 }),
    name: { t: 'JAMAICA', style: 'italic', y: 186, w: 120, size: 32, fill: '#F7D98C', stroke: 'none', shadow: '#0a1420' } },
  US: { shape: 'arch', bg: '#F7C8A0', ink: '#1E1410', scene: () =>
      S.volcano({ x: 112, base: 148, w: 180, h: 70, c: '#3A2A26', lip: '#E06A3A' }) + S.palm({ x: 184, base: 160, h: 64, c: '#1E1410', lean: -8 }) + S.rect(150, 210, '#2E7A8A') + S.waves({ y: 160, c: '#9CD0D8', n: 2, gap: 9, sw: 2 }),
    name: { t: 'HAWAII', style: 'italic', y: 196, w: 110, size: 30, fill: '#F7C8A0', stroke: 'none', shadow: '#0e1a1e' } },
  EC: { shape: 'circle', bg: '#CFE2EC', ink: '#13262E', scene: () =>
      S.range({ base: 140, peaks: [[86, 36], [124, 66], [166, 40]], c: '#3A5A70', snow: '#FBF7EE' }) + S.rect(138, 230, '#3A7A5A') + S.line({ y: 156, c: '#E5C13A', dash: '7 5', sw: 2.4 }) +
      `<text x="120" y="174" text-anchor="middle" style="font-family:'IBM Plex Mono',ui-monospace,monospace;font-size:10px;font-weight:500;letter-spacing:.08em" fill="#E5C13A">0°00′00″</text>`,
    name: { t: 'ECUADOR', style: 'arched', size: 25, fill: '#13262E', arc: true } },
  BO: { shape: 'ticket', bg: '#E8E2D6', ink: '#1E2436', scene: () =>
      S.rect(120, 180, '#F7F4EE') + S.range({ base: 120, peaks: [[150, 30], [184, 42], [214, 28]], c: '#2C3350', valley: 0.5, floor: 120 }) + `<g transform="translate(0 240) scale(1 -1)" opacity=".3">${S.range({ base: 120, peaks: [[150, 30], [184, 42], [214, 28]], c: '#2C3350', valley: 0.5, floor: 120 })}</g>` + S.line({ y: 120, c: '#C25A3A', dash: '0', sw: 1.4 }),
    name: { t: 'BOLIVIA', style: 'expanded', y: 112, w: 104, size: 22, fill: '#C25A3A', stroke: 'none', shadow: '#1E2436', x: 72 } },
  MG: { shape: 'oval', bg: '#F6B98C', ink: '#2A140C', scene: () =>
      S.sun({ x: 120, y: 112, r: 34, c: '#F4D06A' }) + S.rect(138, 200, '#7A3A1E') + S.baobab({ x: 70, base: 140, h: 64, c: '#2A140C' }) + S.baobab({ x: 120, base: 140, h: 80, c: '#2A140C' }) + S.baobab({ x: 170, base: 140, h: 58, c: '#2A140C' }),
    name: { t: 'MADAGASCAR', style: 'condensed', y: 174, w: 130, size: 26, fill: '#F6B98C', stroke: 'none', shadow: '#1a0a04' } },
  LK: { shape: 'scallop', bg: '#E2E8B0', ink: '#16241A', scene: () =>
      S.hills({ y: 100, amp: 10, freq: 0.04, c: '#8AB06A' }) + S.rows({ y: 98, amp: 10, freq: 0.04, c: '#5E8A4E', n: 7, gap: 8, sw: 2.4 }) + S.rect(160, 220, '#A0302E'),
    name: { t: 'SRI LANKA', style: 'condensed', y: 192, w: 118, size: 26, fill: '#F7EFC8', stroke: 'none', shadow: '#3a0e0c' } },
  NP: { shape: 'tri', bg: '#D6E2EE', ink: '#1C2234', scene: () =>
      S.range({ base: 150, peaks: [[70, 54], [112, 96], [150, 70], [184, 50]], c: '#3A4A70', snow: '#FBF9F4' }) + S.rect(150, 210, '#B83A3A'),
    name: { t: 'NEPAL', style: 'spaced', y: 186, w: 104, size: 18, fill: '#FBF9F4', stroke: 'none', shadow: '#3a0e0e' } },
  MW: { shape: 'oval', bg: '#F3D7A6', ink: '#16243A', scene: () =>
      S.sun({ x: 120, y: 118, r: 26, c: '#C9483A' }) + S.rect(124, 200, '#3A6E9A') + S.waves({ y: 136, c: '#A8C8E2', n: 3, gap: 9, sw: 2 }) + S.range({ base: 126, peaks: [[40, 18], [70, 26]], c: '#3A7A4A' }),
    name: { t: 'MALAWI', style: 'expanded', y: 178, w: 116, size: 24, fill: P.paper, stroke: 'none', shadow: '#0e1828' } },
  TW: { shape: 'hexa', bg: '#E4EEE6', ink: '#16262E', scene: () =>
      S.range({ base: 132, peaks: [[60, 42], [100, 60], [146, 50], [186, 38]], c: '#3A8A7A' }) + S.clouds({ pts: [[86, 120, 1.1], [160, 112, 0.9]], c: '#FBFBF6' }) + S.rect(132, 190, '#22323A'),
    name: { t: 'TAIWAN', style: 'expanded', y: 166, w: 118, size: 22, fill: '#E0603A', stroke: 'none', shadow: '#0a1216' } },
};

// Origins on the whitelist without a hand-tuned recipe still get a stable sticker built from their terroir.
const GENERIC_SHAPES = ['oval', 'ticket', 'hexa', 'shield', 'scallop', 'arch'];
const COUNTRY_NAME = Object.fromEntries(Object.entries(ORIGIN_CODE).filter(([n]) => !['Sumatra', 'Java', 'Sulawesi'].includes(n)).map(([n, c]) => [c, n]));
function genericSticker(iso) {
  const t = TERROIR[iso] || TERROIR_UNKNOWN, r = rngFrom(fnv1a('sticker-' + iso));
  const shape = GENERIC_SHAPES[Math.floor(r() * GENERIC_SHAPES.length)];
  const sky = labHex(mixLab(hexLab(t[1]), hexLab('#FBF3E2'), 0.72));
  const peaks = [[50 + r() * 20, 30 + r() * 20], [110 + r() * 20, 50 + r() * 26], [170 + r() * 20, 30 + r() * 24]];
  const name = ({ DO: 'Dominican Rep.' }[iso] || COUNTRY_NAME[iso] || iso).toUpperCase();
  const sh = SHAPES[shape];
  return {
    shape, bg: sky, ink: t[0], generic: true,
    scene: () => S.sun({ x: 120, y: sh.top + 54, r: 18, c: t[2] }) + S.range({ base: 136, peaks, c: t[0] }) + S.rect(134, 230, t[1]),
    name: { t: name, style: 'condensed', y: Math.min(sh.bottom - 18, 172), w: Math.min(132, 26 + name.length * 13), size: 26, fill: t[0], stroke: 'none', shadow: sky },
  };
}

// No origin on the card: a process seal, so the card still carries a mark. No process either: nothing.
const SEALS = {
  washed: { word: 'WASHED', bg: '#E6EEF0', ink: '#1E3A4A', motif: () => S.drop({ x: 120, y: 124, s: 1.15, c: '#3A7EA8' }) },
  natural: { word: 'NATURAL', bg: '#F6E2BC', ink: '#4A2210', motif: () => S.sun({ x: 120, y: 122, r: 22, c: '#E08A2A', rays: 12, rc: '#F0B86A', spread: 0.12 }) },
  honey: { word: 'HONEY', bg: '#F8E4A8', ink: '#4A2E08', motif: () => S.combs({ x: 120, y: 122, r: 12, c: '#E8A93A', c2: '#C47A1E' }) },
  anaerobic: { word: 'FERMENTED', bg: '#F0D6DE', ink: '#4A1028', motif: () => S.bubbles({ x: 120, y: 124, c: '#7A1E46' }) },
  wetHulled: { word: 'WET-HULLED', bg: '#E2DCC8', ink: '#2A2418', motif: () => S.bean({ x: 120, y: 124, c: '#6B4E36', cut: '#E2DCC8' }) },
};

let UID = 0;
function stickerSVG(spec, opts = {}) {
  const u = 's' + (++UID), sh = SHAPES[spec.shape];
  const seed = fnv1a(spec.key || spec.name?.t || 'k') % 97;
  const n = spec.name;
  let text = '';
  if (n) {
    const style = TYPE[n.style];
    if (n.arc) {
      const arcId = u + 'a';
      text = `<path id="${arcId}" d="${sh.arc}" fill="none"/>` +
        `<text style="${style};font-size:${n.size}px" fill="${n.fill}"><textPath href="#${arcId}" startOffset="50%" text-anchor="middle">${n.t}</textPath></text>`;
    } else {
      const x = n.x || 120, fit = n.style === 'spaced' ? `textLength="${n.w}" lengthAdjust="spacing"` : `textLength="${n.w}" lengthAdjust="spacingAndGlyphs"`;
      const base = `x="${x}" y="${n.y}" text-anchor="middle" ${fit} style="${style};font-size:${n.size}px"`;
      text = (n.shadow ? `<text ${base} fill="${n.shadow}" transform="translate(2.2 2.2)">${n.t}</text>` : '') +
        `<text ${base} fill="${n.fill}" ${n.stroke && n.stroke !== 'none' ? `stroke="${n.stroke}" stroke-width="3" paint-order="stroke" stroke-linejoin="round"` : ''}>${n.t}</text>`;
    }
  }
  const scene = spec.scene ? spec.scene() : '';
  return `<svg class="stk" viewBox="0 0 240 240" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
<defs>
<clipPath id="${u}c"><path d="${sh.d}"/></clipPath>
<pattern id="${u}h" width="4.2" height="4.2" patternUnits="userSpaceOnUse" patternTransform="rotate(28)"><circle cx="2.1" cy="2.1" r=".95" fill="${spec.ink}"/></pattern>
<filter id="${u}w" x="-5%" y="-5%" width="110%" height="110%"><feTurbulence type="fractalNoise" baseFrequency=".7" numOctaves="2" seed="${seed}" result="n"/><feColorMatrix in="n" type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 -18 0 0 0 13.6" result="m"/><feComposite in="SourceGraphic" in2="m" operator="in"/></filter>
<filter id="${u}s" x="-15%" y="-15%" width="130%" height="135%"><feDropShadow dx="0" dy="2" stdDeviation="2.2" flood-color="#24180e" flood-opacity=".38"/></filter>
</defs>
<path d="${sh.d}" fill="${P.paper}" stroke="${P.paper}" stroke-width="15" stroke-linejoin="round" filter="url(#${u}s)"/>
<g filter="url(#${u}w)">
<g clip-path="url(#${u}c)"><rect width="240" height="240" fill="${spec.bg}"/>${scene}<rect width="240" height="240" fill="url(#${u}h)" opacity=".13"/></g>
${text}
<path d="${sh.d}" fill="none" stroke="${spec.ink}" stroke-width="3.4" stroke-linejoin="round" transform="translate(1.1 -.9)"/>
</g></svg>`;
}

function sealSpec(procKey) {
  const s = SEALS[procKey];
  if (!s) return null;
  return {
    key: 'seal-' + procKey, shape: 'scallop', bg: s.bg, ink: s.ink,
    scene: () => s.motif() + `<path d="M66 170 H174" stroke="${s.ink}" stroke-width="1.6"/>` +
      `<text x="120" y="186" text-anchor="middle" style="font-family:'IBM Plex Mono',ui-monospace,monospace;font-size:9px;font-weight:500;letter-spacing:.16em" fill="${s.ink}">KOHI · PROCESS</text>`,
    name: { t: s.word, style: 'arched', size: s.word.length > 8 ? 19 : 23, fill: s.ink, arc: true },
  };
}

// What a card wears: its origin sticker, else its process seal, else nothing.
function stickerFor(card) {
  const iso = ORIGIN_CODE[(card.country || '').trim()];
  if (iso) {
    const r = STICKERS[iso] ? { ...STICKERS[iso], key: iso } : { ...genericSticker(iso), key: iso };
    return { spec: r, kind: STICKERS[iso] ? 'origin' : 'origin-generic', iso };
  }
  const seal = sealSpec(classifyProcess(card.process));
  return seal ? { spec: seal, kind: 'seal' } : null;
}
