// Renders the 47 stickers (42 origins + 5 process seals) from lab/stickers.js into ../OriginStickers.xcassets.
// One-time setup in this folder:
//   npm i playwright @fontsource-variable/archivo@5.2.5 @fontsource/dm-serif-display@5.2.5 @fontsource/ibm-plex-mono@5.2.5
//   npx playwright install chromium
// Then:
//   node render-stickers.js        (writes PNG 720 px into ./stickers-png)
//   python3 build-xcassets.py      (480 px, 256 colours, Contents.json → ../OriginStickers.xcassets)
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const font = (pkg, file) => fs.readFileSync(require.resolve(`${pkg}/files/${file}`)).toString('base64');
const face = (name, data, extra) => `@font-face{font-family:'${name}';src:url(data:font/woff2;base64,${data}) format('woff2');${extra}}`;
const css = [
  face('Archivo', font('@fontsource-variable/archivo', 'archivo-latin-wdth-normal.woff2'), 'font-weight:100 900;font-stretch:62% 125%;font-style:normal;'),
  face('DM Serif Display', font('@fontsource/dm-serif-display', 'dm-serif-display-latin-400-normal.woff2'), 'font-style:normal;'),
  face('DM Serif Display', font('@fontsource/dm-serif-display', 'dm-serif-display-latin-400-italic.woff2'), 'font-style:italic;'),
  face('IBM Plex Mono', font('@fontsource/ibm-plex-mono', 'ibm-plex-mono-latin-500-normal.woff2'), 'font-weight:500;'),
].join('\n');
const js = ['data.js', 'engine.js', 'stickers.js'].map(f => fs.readFileSync(path.join(__dirname, 'lab', f), 'utf8')).join('\n');
const html = `<!doctype html><html><head><meta charset="utf-8"><style>${css} body{margin:0;background:transparent} .s{width:720px;height:720px} .s svg{width:720px;height:720px;display:block}</style></head><body><div id="root"></div><script>${js}
const out=[]; const codes=[...new Set(Object.values(ORIGIN_CODE))];
for (const iso of codes) { const spec = STICKERS[iso] ? { ...STICKERS[iso], key: iso } : { ...genericSticker(iso), key: iso }; out.push(['origin-' + iso.toLowerCase(), stickerSVG(spec)]); }
for (const k of Object.keys(SEALS)) out.push(['seal-' + k.toLowerCase(), stickerSVG(sealSpec(k))]);
document.getElementById('root').innerHTML = out.map(([n, s]) => '<div class="s" id="' + n + '">' + s + '</div>').join('');
window.NAMES = out.map(o => o[0]);
</script></body></html>`;
const tmp = path.join(__dirname, 'stickers-render.html');
fs.writeFileSync(tmp, html);
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 760, height: 760 } });
  await page.goto('file://' + tmp);
  await page.evaluate(() => document.fonts.ready);
  const names = await page.evaluate(() => window.NAMES);
  const dir = path.join(__dirname, 'stickers-png');
  fs.mkdirSync(dir, { recursive: true });
  for (const n of names) await (await page.$('#' + n)).screenshot({ path: path.join(dir, n + '.png'), omitBackground: true });
  console.log(names.length, 'stickers rendered into', dir);
  await browser.close();
})();
