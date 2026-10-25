// ───────────────────────── Page ─────────────────────────
const $ = (s, r = document) => r.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const DPR = Math.min(2, window.devicePixelRatio || 1);

// ── symbols: marks cut from real bags (backstages/planche.png) + two neutral demo shapes
const SYMBOLS = {};
const SYMBOL_META = [
  { key: 'klover', label: 'Trèfle', from: 'Klover Coffee Paris', url: MARKS.klover, small: true },
  { key: 'angel', label: 'Ange', from: 'Clima Cafecito', url: MARKS.angel },
  { key: 'panama', label: 'Carte', from: 'Gallardo Family', url: MARKS.panama },
  { key: 'bottle', label: 'Bouteille', from: 'Blue Bottle', url: MARKS.bottle, small: true },
  { key: 'demo-sun', label: 'Démo soleil', from: 'forme neutre', draw: 'sun' },
  { key: 'demo-leaf', label: 'Démo feuille', from: 'forme neutre', draw: 'leaf' },
];
function demoMark(kind) {
  const c = offscreen(400, 400), x = c.getContext('2d');
  x.fillStyle = '#1a1815'; x.strokeStyle = '#1a1815';
  if (kind === 'sun') {
    x.beginPath(); x.arc(200, 200, 70, 0, Math.PI * 2); x.fill();
    for (let i = 0; i < 16; i++) { const a = i / 16 * Math.PI * 2; x.lineWidth = 14; x.lineCap = 'round'; x.beginPath(); x.moveTo(200 + 100 * Math.cos(a), 200 + 100 * Math.sin(a)); x.lineTo(200 + 180 * Math.cos(a), 200 + 180 * Math.sin(a)); x.stroke(); }
  } else {
    x.beginPath(); x.moveTo(200, 20); x.bezierCurveTo(330, 110, 330, 290, 200, 380); x.bezierCurveTo(70, 290, 70, 110, 200, 20); x.fill();
    x.globalCompositeOperation = 'destination-out'; x.lineWidth = 9; x.beginPath(); x.moveTo(200, 60); x.lineTo(200, 370); x.stroke();
    for (let i = 0; i < 6; i++) { const y = 110 + i * 42; x.beginPath(); x.moveTo(200, y + 30); x.lineTo(270, y - 10); x.moveTo(200, y + 30); x.lineTo(130, y - 10); x.stroke(); }
  }
  return c;
}
function measureCoverage(img) {
  const w = 120, h = Math.max(1, Math.round(120 * img.height / img.width)), c = offscreen(w, h), x = c.getContext('2d');
  x.drawImage(img, 0, 0, w, h);
  const d = x.getImageData(0, 0, w, h).data; let on = 0;
  for (let i = 3; i < d.length; i += 4) if (d[i] > 100) on++;
  return on / (w * h);
}
function loadSymbols() {
  return Promise.all(SYMBOL_META.map(m => new Promise(res => {
    if (m.draw) { const img = demoMark(m.draw); SYMBOLS[m.key] = { ...m, img, coverage: measureCoverage(img) }; return res(); }
    const img = new Image(); img.onload = () => { SYMBOLS[m.key] = { ...m, img, coverage: measureCoverage(img) }; res(); }; img.onerror = res; img.src = m.url;
  })));
}

// ── extraction for an uploaded photo (port of PackInk + PackMark, with the darkness chain as fallback)
function extractMark(img) {
  const max = 900, sc = Math.min(1, max / Math.max(img.width, img.height));
  const W = Math.round(img.width * sc), H = Math.round(img.height * sc);
  const c = offscreen(W, H), x = c.getContext('2d'); x.drawImage(img, 0, 0, W, H);
  const d = x.getImageData(0, 0, W, H).data, n = W * H;
  const mask = new Float32Array(n);
  let transparent = 0; for (let i = 3; i < d.length; i += 4) if (d[i] < 200) transparent++;
  let how;
  if (transparent > n * 0.02) {
    for (let i = 0; i < n; i++) mask[i] = d[i * 4 + 3] > 128 && (d[i * 4] + d[i * 4 + 1] + d[i * 4 + 2]) < 700 ? 1 : 0; how = 'transparence du PNG';
  } else {
    const hsv = i => { const r = d[i * 4] / 255, g = d[i * 4 + 1] / 255, b = d[i * 4 + 2] / 255, mx = Math.max(r, g, b), mn = Math.min(r, g, b), dd = mx - mn; let h = 0; if (dd > 1e-4) { h = mx === r ? ((g - b) / dd) % 6 : mx === g ? (b - r) / dd + 2 : (r - g) / dd + 4; h /= 6; if (h < 0) h += 1; } return [h, mx ? dd / mx : 0, mx]; };
    const hist = new Array(24).fill(0); let tot = 0;
    for (let i = 0; i < n; i += 3) { const [h, s, v] = hsv(i); tot++; if (s > 0.32 && v > 0.12 && v < 0.92) hist[Math.min(23, Math.floor(h * 24))]++; }
    const peak = arr => { let b = 0; arr.forEach((v, i) => { if (v > arr[b]) b = i; }); const own = arr[(b + 23) % 24] + arr[b] + arr[(b + 1) % 24]; return { b, share: own / tot }; };
    let p = peak(hist), hue = null;
    if (p.share >= 0.18) { const rest = hist.slice(); [-1, 0, 1].forEach(o => rest[(p.b + o + 24) % 24] = 0); const q = peak(rest); if (q.share >= 0.005) hue = (q.b + 0.5) / 24; }
    else if (p.share >= 0.005) hue = (p.b + 0.5) / 24;
    if (hue != null) {
      for (let i = 0; i < n; i++) { const [h, s, v] = hsv(i); const dh = Math.min(Math.abs(h - hue), 1 - Math.abs(h - hue)); mask[i] = s > 0.25 && v > 0.1 && v < 0.97 && dh <= 1.6 / 24 ? 1 : 0; }
      how = 'encre colorée du sachet (comme PackMark)';
    } else {
      const lum = new Float32Array(n), histL = new Array(256).fill(0);
      for (let i = 0; i < n; i++) { lum[i] = (0.2126 * d[i * 4] + 0.7152 * d[i * 4 + 1] + 0.0722 * d[i * 4 + 2]); histL[Math.round(lum[i])]++; }
      let sum = 0; for (let i = 0; i < 256; i++) sum += i * histL[i];
      let sB = 0, wB = 0, best = 0, th = 128;
      for (let i = 0; i < 256; i++) { wB += histL[i]; if (!wB) continue; const wF = n - wB; if (!wF) break; sB += i * histL[i]; const mB = sB / wB, mF = (sum - sB) / wF, v = wB * wF * (mB - mF) ** 2; if (v > best) { best = v; th = i; } }
      for (let i = 0; i < n; i++) mask[i] = lum[i] <= th ? 1 : 0; how = 'encre sombre, seuil d’Otsu';
    }
  }
  // smooth: two box-blur passes, then a soft threshold → clean edges at any size
  const r = Math.max(1, Math.round(Math.max(W, H) * 0.004));
  const blur = (src) => { const t = new Float32Array(n), o = new Float32Array(n);
    for (let y = 0; y < H; y++) { let acc = 0; for (let x0 = -r; x0 <= r; x0++) acc += src[y * W + clamp(x0, 0, W - 1)]; for (let x0 = 0; x0 < W; x0++) { t[y * W + x0] = acc / (2 * r + 1); acc += src[y * W + Math.min(W - 1, x0 + r + 1)] - src[y * W + Math.max(0, x0 - r)]; } }
    for (let x0 = 0; x0 < W; x0++) { let acc = 0; for (let y0 = -r; y0 <= r; y0++) acc += t[clamp(y0, 0, H - 1) * W + x0]; for (let y0 = 0; y0 < H; y0++) { o[y0 * W + x0] = acc / (2 * r + 1); acc += t[Math.min(H - 1, y0 + r + 1) * W + x0] - t[Math.max(0, y0 - r) * W + x0]; } }
    return o; };
  const f = blur(blur(mask));
  let minX = W, minY = H, maxX = 0, maxY = 0;
  const out = x.createImageData(W, H);
  for (let i = 0; i < n; i++) { const a = clamp((f[i] - 0.35) / 0.3); if (a > 0.05) { const px = i % W, py = (i / W) | 0; minX = Math.min(minX, px); maxX = Math.max(maxX, px); minY = Math.min(minY, py); maxY = Math.max(maxY, py); } out.data[i * 4] = 26; out.data[i * 4 + 1] = 24; out.data[i * 4 + 2] = 21; out.data[i * 4 + 3] = a * 255; }
  if (maxX <= minX || maxY <= minY) return null;
  x.clearRect(0, 0, W, H); x.putImageData(out, 0, 0);
  const crop = offscreen(maxX - minX + 1, maxY - minY + 1); crop.getContext('2d').drawImage(c, minX, minY, crop.width, crop.height, 0, 0, crop.width, crop.height);
  return { img: crop, how };
}

// ── card faces
function displayTitle(card) {
  const t = (card.name || '').trim();
  if (t) return t;
  return [card.region, card.country, card.roaster].map(s => (s || '').split(',')[0].trim()).find(Boolean) || '';
}
function altitudeText(raw) {
  const a = String(raw || '').trim(); if (!a) return '';
  if (/^\d{3,4}$/.test(a)) return a.replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + ' m';
  return a.replace('-', '–') + ' m';
}
function placeLine(card) {
  const place = [card.region, card.country].filter(s => s && s.trim()).join(', ');
  const alt = altitudeText(card.altitude);
  return { place, alt };
}

function stickerHTML(card, cls = '') {
  const st = stickerFor(card);
  if (!st) return '';
  return `<div class="kc-sticker ${cls}">${stickerSVG(st.spec)}</div>`;
}

function newCard(card, opt = {}) {
  const density = opt.density || 'tile', layout = opt.layout || 'label';
  const art = makeArt(card);
  const symKey = opt.symbol !== undefined ? opt.symbol : card.symbol;
  const sym = (symKey && SYMBOLS[symKey]) || (opt.upload && symKey === 'upload' ? opt.upload : null);
  const auto = autoTreatment(sym, art);
  const kind = !opt.treatment || opt.treatment === 'auto' ? auto.kind : opt.treatment;
  const el = document.createElement('div');
  el.className = `kc kc-${density} lay-${layout}`;
  const cv = document.createElement('canvas');
  const cssW = density === 'tile' ? 300 : 400;
  cv.width = Math.round(cssW * DPR); cv.height = Math.round(cssW * 1.25 * DPR);
  cv.className = 'kc-bg';
  paintBackdrop(cv, art, sym, kind);
  el.appendChild(cv);
  const { place, alt } = placeLine(card);
  const title = displayTitle(card);
  const proc = [card.process, card.variety].filter(s => s && s.trim()).join(' · ');
  const notes = (card.notes || []).filter(Boolean).slice(0, 3);
  const st = stickerFor(card);
  const stickerSide = art.side;
  const rot = art.stickerRot.toFixed(1);
  const stk = st ? `<div class="kc-sticker side-${stickerSide}" style="--rot:${rot}deg">${stickerSVG(st.spec)}</div>` : '';
  if (layout === 'label') {
    el.insertAdjacentHTML('beforeend', `<div class="kc-label ${st ? 'has-stk side-' + stickerSide : ''}">
      ${stk}
      ${card.roaster ? `<div class="kc-roaster">${esc(card.roaster)}</div>` : ''}
      ${title ? `<div class="kc-title" style="color:${art.titleInk}">${esc(title)}</div>` : ''}
      ${(place || alt) ? `<div class="kc-rule"></div><div class="kc-place">${esc(place)}${place && alt ? ' <span>· ' + esc(alt) + '</span>' : alt ? '<span>' + esc(alt) + '</span>' : ''}</div>` : ''}
      ${density === 'detail' && proc ? `<div class="kc-place kc-proc">${esc(proc)}</div>` : ''}
      ${density === 'detail' && notes.length ? `<div class="kc-notes"><span class="kc-cap">Notes</span>${notes.map(esc).join(' · ')}</div>` : ''}
      ${density === 'detail' ? `<div class="kc-foot">ADDED 25 OCT 2026 · FROM THE PACK</div>` : ''}
    </div>`);
  } else {
    el.insertAdjacentHTML('beforeend', `<div class="kc-bleed tone-${art.textTone}">
      ${card.roaster ? `<div class="kc-roaster">${esc(card.roaster)}</div>` : ''}
      ${title ? `<div class="kc-title">${esc(title)}</div>` : ''}
      ${(place || alt) ? `<div class="kc-place">${esc(place)}${place && alt ? ' · ' : ''}${esc(alt)}</div>` : ''}
      ${density === 'detail' && notes.length ? `<div class="kc-place">${notes.map(esc).join(' · ')}</div>` : ''}
    </div>${st ? `<div class="kc-sticker kc-sticker-free side-${stickerSide}" style="--rot:${rot}deg">${stickerSVG(st.spec)}</div>` : ''}`);
  }
  el._art = art; el._kind = kind; el._auto = auto; el._sym = sym; el._sticker = st;
  return el;
}

// Today's KohiCard tile (Design/KohiCard.swift), for the before / after.
function oldCard(card) {
  const el = document.createElement('div');
  el.className = 'kc kc-tile kc-old';
  const iso = ORIGIN_CODE[(card.country || '').trim()];
  let color = null;
  if (card.inkHue != null) color = rgbToHex(hsvToRgb((Math.floor(card.inkHue * 24) + 0.5) / 24, 0.62, 0.36));
  else { const a = (card.notes || []).map(matchAroma).find(Boolean); if (a) color = rgbToHex(hexToRgb(WHEEL_FAMILY[a.fam]).map(v => v * 0.62)); }
  const sym = card.symbol && SYMBOLS[card.symbol];
  const { place, alt } = placeLine(card);
  el.innerHTML = `${sym ? `<img class="kc-old-mark" alt="" src="${sym.img.toDataURL ? sym.img.toDataURL() : sym.url}">` : ''}
    <div class="kc-old-body">
      <div class="kc-old-head"><span class="kc-roaster">${esc(card.roaster || '')}</span>${iso ? `<span class="kc-old-circle">${iso}</span>` : ''}</div>
      ${card.name ? `<div class="kc-title" style="color:${color || 'var(--ink)'}">${esc(card.name)}</div>` : ''}
      ${(place || alt) ? `${card.name ? '<div class="kc-rule"></div>' : ''}<div class="kc-place">${esc(place)}${alt ? ' <span>· ' + esc(alt) + '</span>' : ''}</div>` : ''}
    </div>`;
  return el;
}

// ── collection grid
const state = { mode: 'new', layout: 'label', sel: 4, edit: null, treatment: 'auto', symbol: undefined, upload: null, edLayout: 'label' };

function renderGrid() {
  const g = $('#grid'); g.innerHTML = '';
  COLLECTION.forEach((card, i) => {
    const b = document.createElement('button');
    b.className = 'tile'; b.type = 'button';
    b.setAttribute('aria-label', `Ouvrir ${displayTitle(card)} dans l’atelier`);
    b.appendChild(state.mode === 'new' ? newCard(card, { layout: state.layout }) : oldCard(card));
    b.addEventListener('click', () => { selectCard(i); $('#atelier').scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' }); });
    g.appendChild(b);
  });
}

// ── atelier
function fillSelects() {
  $('#ed-card').innerHTML = COLLECTION.map((c, i) => `<option value="${i}">${esc(displayTitle(c))}${c.roaster ? ' — ' + esc(c.roaster) : ''}</option>`).join('');
  const countries = Object.keys(ORIGIN_CODE).sort();
  $('#ed-country').innerHTML = `<option value="">— aucun pays</option>` + countries.map(c => `<option>${c}</option>`).join('');
  $('#ed-process').innerHTML = ['', 'Washed', 'Natural', 'Honey', 'Pulped Natural', 'Anaerobic', 'Double Anaerobic', 'Carbonic Maceration', 'Wet-hulled', 'Lavado'].map(p => `<option value="${p}">${p || '— inconnu'}</option>`).join('');
  $('#ed-roast').innerHTML = `<option value="">— inconnue</option>` + Object.entries(ROAST).map(([k, v]) => `<option value="${k}">${v.label}</option>`).join('');
  $('#ed-symbol').innerHTML = `<button type="button" data-v="">Aucun</button>` + SYMBOL_META.map(m => `<button type="button" data-v="${m.key}" title="${esc(m.from)}">${esc(m.label)}</button>`).join('') + `<button type="button" data-v="upload" id="ed-upload-btn">Importer…</button>`;
}
function selectCard(i) {
  state.sel = i; state.edit = JSON.parse(JSON.stringify(COLLECTION[i])); state.symbol = undefined; state.treatment = 'auto';
  $('#ed-card').value = i; writeForm(); renderAtelier();
}
function writeForm() {
  const c = state.edit;
  $('#ed-name').value = c.name || ''; $('#ed-roaster').value = c.roaster || ''; $('#ed-country').value = c.country || '';
  $('#ed-region').value = c.region || ''; $('#ed-alt').value = c.altitude || ''; $('#ed-process').value = c.process || '';
  if (![...$('#ed-process').options].some(o => o.value === (c.process || ''))) $('#ed-process').insertAdjacentHTML('beforeend', `<option value="${esc(c.process)}">${esc(c.process)}</option>`), $('#ed-process').value = c.process;
  $('#ed-roast').value = c.roast || ''; $('#ed-notes').value = (c.notes || []).join(', ');
  $('#ed-ink-on').checked = c.inkHue != null; $('#ed-ink').value = c.inkHue != null ? c.inkHue : 0.6; $('#ed-ink').disabled = c.inkHue == null;
  syncSeg();
}
function readForm() {
  const c = state.edit;
  c.name = $('#ed-name').value; c.roaster = $('#ed-roaster').value; c.country = $('#ed-country').value; c.region = $('#ed-region').value;
  c.altitude = $('#ed-alt').value; c.process = $('#ed-process').value; c.roast = $('#ed-roast').value;
  c.notes = $('#ed-notes').value.split(',').map(s => s.trim()).filter(Boolean);
  $('#ed-ink').disabled = !$('#ed-ink-on').checked;
  c.inkHue = $('#ed-ink-on').checked ? parseFloat($('#ed-ink').value) : null;
}
function syncSeg() {
  const symNow = state.symbol !== undefined ? state.symbol : (state.edit.symbol || '');
  document.querySelectorAll('#ed-symbol button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.v === symNow)));
  document.querySelectorAll('#ed-treat button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.v === state.treatment)));
  document.querySelectorAll('#ed-layout button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.v === state.edLayout)));
  const up = $('#ed-upload-btn'); if (up) up.disabled = false;
}
const FAM_LABEL = { 'fruity': 'Fruity', 'sour-fermented': 'Sour/Fermented', 'green-vegetative': 'Green', 'other': 'Other', 'roasted': 'Roasted', 'spices': 'Spices', 'nutty-cocoa': 'Nutty/Cocoa', 'sweet': 'Sweet', 'floral': 'Floral' };
const TREAT_FR = { emboss: 'Gaufrage', ink: 'Encre', halftone: 'Trame', pattern: 'Motif', none: 'Aucun' };
function swatch(c, title = '') { return `<i class="sw" style="background:${c}" title="${esc(title || c)}"></i>`; }

function renderAtelier() {
  const c = state.edit;
  const opt = { density: 'detail', layout: state.edLayout, treatment: state.treatment, symbol: state.symbol, upload: state.upload };
  const card = newCard(c, opt);
  const stage = $('#ed-stage'); stage.innerHTML = ''; stage.appendChild(card);
  const minis = $('#ed-minis'); minis.innerHTML = '';
  const m1 = document.createElement('figure'); m1.appendChild(oldCard(c)); m1.insertAdjacentHTML('beforeend', '<figcaption>Aujourd’hui</figcaption>');
  const m2 = document.createElement('figure'); m2.appendChild(newCard(c, { ...opt, density: 'tile', layout: 'label' })); m2.insertAdjacentHTML('beforeend', '<figcaption>Tuile</figcaption>');
  minis.append(m1, m2);

  const a = card._art;
  const terr = a.iso ? `${esc(c.country)} (${a.iso})` : c.country ? `${esc(c.country)} — hors liste, terre neutre` : 'aucun pays — terre neutre';
  const notesHTML = (c.notes || []).slice(0, 3).map(n => { const m = matchAroma(n); return m ? `<span class="chip">${swatch(m.c)}${esc(n)} <em>→ ${FAM_LABEL[m.fam] || m.fam} · ${esc(m.syn[0])}${m.id.startsWith('x-') ? ' (hors roue)' : ''}</em></span>` : `<span class="chip miss">${esc(n)} <em>non reconnue</em></span>`; }).join('') || '<span class="muted">aucune note — les teintes viennent de la terre' + (c.inkHue != null ? ' et de l’encre du sachet' : '') + '</span>';
  const st = card._sticker;
  const symName = card._sym ? (card._sym.label + (card._sym.from ? ' · ' + card._sym.from : '')) : '—';
  $('#ed-recipe').innerHTML = `
    <div class="rrow"><dt>Terre · origine</dt><dd>${a.terroir.map(x => swatch(x)).join('')} ${terr}</dd></div>
    <div class="rrow"><dt>Arômes · notes</dt><dd class="chips">${notesHTML}</dd></div>
    <div class="rrow"><dt>Ciel · altitude</dt><dd>${swatch(labHex(a.sky))} ${a.alt ? Math.round(a.alt).toLocaleString('fr-FR') + ' m' : 'inconnue'} → ${Math.round(a.h * 100)} % d’air au-dessus du café</dd></div>
    <div class="rrow"><dt>Énergie · process</dt><dd>${esc(c.process || '—')} → ${a.proc.fr} · grain ${Math.round(a.proc.grain * 100)} % · torsion ${Math.round(a.proc.warp * 100)} %</dd></div>
    <div class="rrow"><dt>Valeur · torréfaction</dt><dd>${a.roast ? a.roast.label : 'inconnue (light par défaut)'} → ${a.dL >= 0 ? '+' : '−'}${Math.abs(a.dL).toFixed(2).replace('.', ',')} de luminosité</dd></div>
    <div class="rrow"><dt>Encre du sachet</dt><dd>${a.inkHex ? swatch(a.inkHex) + ' mesurée, posée en accent' : 'non mesurée'}</dd></div>
    <div class="rrow"><dt>Symbole</dt><dd>${esc(symName)} → <b>${TREAT_FR[card._kind]}</b>${state.treatment === 'auto' ? ` <span class="muted">(${card._auto.why})</span>` : ''}</dd></div>
    <div class="rrow"><dt>Sticker</dt><dd>${st ? (st.kind === 'seal' ? 'pas de pays → sceau de process' : st.kind === 'origin' ? `${st.iso} · recette dédiée, identique pour tous les cafés de ce pays` : `${st.iso} · recette générée depuis la terre`) : 'aucun (ni pays ni process)'}</dd></div>
    <div class="rrow"><dt>Graine</dt><dd><code>${a.seed.toString(16).padStart(8, '0')}</code> <span class="muted">tirée de l’identifiant : même café, même carte</span></dd></div>`;
  syncSeg();
}

// ── sticker board
function renderBoard() {
  const b = $('#board'); b.innerHTML = '';
  const codes = [...new Set(Object.values(ORIGIN_CODE))];
  const items = codes.map(iso => ({ iso, spec: STICKERS[iso] ? { ...STICKERS[iso], key: iso } : { ...genericSticker(iso), key: iso }, generic: !STICKERS[iso] }));
  items.sort((x, y) => (x.generic - y.generic));
  items.forEach(it => {
    const r = rngFrom(fnv1a('board-' + it.iso));
    const f = document.createElement('figure'); f.className = 'bd' + (it.generic ? ' gen' : '');
    f.innerHTML = `<div class="bd-s" style="transform:rotate(${((r() - 0.5) * 14).toFixed(1)}deg)">${stickerSVG(it.spec)}</div><figcaption>${it.iso}<span>${esc(COUNTRY_NAME[it.iso] || '')}${it.generic ? ' · générée' : ''}</span></figcaption>`;
    b.appendChild(f);
  });
  const s = $('#seals'); s.innerHTML = '';
  Object.keys(SEALS).forEach(k => {
    const f = document.createElement('figure'); f.className = 'bd';
    f.innerHTML = `<div class="bd-s">${stickerSVG(sealSpec(k))}</div><figcaption>${PROCESS[k].label}<span>sans pays</span></figcaption>`;
    s.appendChild(f);
  });
}

// ── wiring
function seg(id, key, after) {
  $(id).addEventListener('click', e => { const b = e.target.closest('button'); if (!b || b.disabled) return; state[key] = b.dataset.v; after(); });
}
async function boot() {
  await loadSymbols();
  fillSelects();
  seg('#mode', 'mode', () => { document.querySelectorAll('#mode button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.v === state.mode))); renderGrid(); });
  seg('#layout', 'layout', () => { document.querySelectorAll('#layout button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.v === state.layout))); renderGrid(); });
  $('#ed-card').addEventListener('change', e => selectCard(+e.target.value));
  ['#ed-name', '#ed-roaster', '#ed-region', '#ed-alt', '#ed-notes'].forEach(id => $(id).addEventListener('input', () => { readForm(); renderAtelier(); }));
  ['#ed-country', '#ed-process', '#ed-roast', '#ed-ink-on', '#ed-ink'].forEach(id => $(id).addEventListener(id === '#ed-ink' ? 'input' : 'change', () => { readForm(); renderAtelier(); }));
  $('#ed-symbol').addEventListener('click', e => {
    const b = e.target.closest('button'); if (!b) return;
    if (b.dataset.v === 'upload') { $('#ed-file').click(); return; }
    state.symbol = b.dataset.v; renderAtelier();
  });
  $('#ed-file').addEventListener('change', e => {
    const f = e.target.files[0]; if (!f) return;
    const img = new Image();
    img.onload = () => {
      const r = extractMark(img);
      if (!r) { $('#ed-upload-note').textContent = 'Rien d’isolable sur cette photo. Essaie un cadrage plus serré sur le symbole.'; return; }
      state.upload = { key: 'upload', label: 'Import', from: r.how, img: r.img, coverage: measureCoverage(r.img) };
      SYMBOLS.upload = state.upload; state.symbol = 'upload';
      $('#ed-upload-note').textContent = `Symbole isolé par ${r.how}.`;
      renderAtelier();
    };
    img.src = URL.createObjectURL(f);
  });
  seg('#ed-treat', 'treatment', renderAtelier);
  seg('#ed-layout', 'edLayout', renderAtelier);
  renderGrid();
  selectCard(state.sel);
  renderBoard();
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(() => { renderAtelier(); });
}
boot();
