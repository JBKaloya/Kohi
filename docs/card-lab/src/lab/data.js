// ───────────────────────── Data ─────────────────────────
// AROMA: one colour per note. Keys follow flavor-wheel.json ids where the wheel has the note;
// extra specialty notes the wheel lacks (lychee, passion fruit, red currant…) are added with a parent family.
// Matching: longest key or synonym contained in the note wins.
const AROMA = [
  // Fruity / berry
  { id: 'fruity-berry-blackberry', c: '#4A2152', fam: 'fruity', syn: ['blackberry', 'blackberries', 'mure'] },
  { id: 'fruity-berry-raspberry', c: '#D6265B', fam: 'fruity', syn: ['raspberry', 'framboise'] },
  { id: 'fruity-berry-blueberry', c: '#4B4BC0', fam: 'fruity', syn: ['blueberry', 'blueberries', 'myrtille'] },
  { id: 'fruity-berry-strawberry', c: '#F0414B', fam: 'fruity', syn: ['strawberry', 'strawberries', 'fraise'] },
  { id: 'fruity-berry', c: '#B8235A', fam: 'fruity', syn: ['berry', 'berries', 'red fruit', 'red fruits', 'fruits rouges'] },
  { id: 'x-red-currant', c: '#D3123E', fam: 'fruity', syn: ['red currant', 'redcurrant', 'groseille'] },
  { id: 'x-blackcurrant', c: '#3A1240', fam: 'fruity', syn: ['blackcurrant', 'black currant', 'cassis'] },
  { id: 'x-cranberry', c: '#B5163A', fam: 'fruity', syn: ['cranberry', 'cranberries'] },
  { id: 'x-gooseberry', c: '#B9C95A', fam: 'fruity', syn: ['gooseberry', 'gooseberries'] },
  // Fruity / dried
  { id: 'fruity-dried-fruit-raisin', c: '#7A3046', fam: 'fruity', syn: ['raisin', 'raisins', 'sultana', 'golden raisin'] },
  { id: 'fruity-dried-fruit-prune', c: '#4E2440', fam: 'fruity', syn: ['prune', 'prunes', 'pruneau'] },
  { id: 'fruity-dried-fruit', c: '#7A3B2E', fam: 'fruity', syn: ['dried fruit', 'fruits secs'] },
  { id: 'x-fig', c: '#6B3A5A', fam: 'fruity', syn: ['fig', 'figue'] },
  { id: 'x-date', c: '#7A4428', fam: 'fruity', syn: ['date', 'datte'] },
  { id: 'x-plum', c: '#6A1F4D', fam: 'fruity', syn: ['plum', 'prune rouge', 'plum jam'] },
  // Fruity / other
  { id: 'fruity-other-fruit-coconut', c: '#EFE4D2', fam: 'fruity', syn: ['coconut', 'noix de coco'] },
  { id: 'fruity-other-fruit-cherry', c: '#B5122E', fam: 'fruity', syn: ['cherry', 'cherries', 'cerise', 'griotte'] },
  { id: 'x-black-cherry', c: '#5E0E26', fam: 'fruity', syn: ['black cherry', 'cereza negra'] },
  { id: 'fruity-other-fruit-pomegranate', c: '#C2213F', fam: 'fruity', syn: ['pomegranate', 'grenade'] },
  { id: 'fruity-other-fruit-pineapple', c: '#F6C639', fam: 'fruity', syn: ['pineapple', 'ananas'] },
  { id: 'fruity-other-fruit-grape', c: '#6B3A8C', fam: 'fruity', syn: ['grape', 'grapes', 'muscat'] },
  { id: 'fruity-other-fruit-apple', c: '#9CCB4A', fam: 'fruity', syn: ['apple', 'green apple', 'pomme', 'crisp apple', 'manzana'] },
  { id: 'fruity-other-fruit-peach', c: '#FF9A6B', fam: 'fruity', syn: ['peach', 'apricot', 'abricot', 'nectarine', 'peche'] },
  { id: 'fruity-other-fruit-pear', c: '#D6D66A', fam: 'fruity', syn: ['pear', 'poire'] },
  { id: 'fruity-other-fruit', c: '#FF8C5A', fam: 'fruity', syn: ['fruit', 'fruity', 'other fruit'] },
  { id: 'x-stone-fruit', c: '#FF9F6B', fam: 'fruity', syn: ['stone fruit', 'stonefruit', 'stonefruits', 'stone fruits', 'fruits a noyau'] },
  { id: 'x-lychee', c: '#F7A9BE', fam: 'fruity', syn: ['lychee', 'litchi', 'lichi'] },
  { id: 'x-passion-fruit', c: '#FFB21E', fam: 'fruity', syn: ['passion fruit', 'passionfruit', 'maracuja', 'fruit de la passion'] },
  { id: 'x-mango', c: '#FFA62B', fam: 'fruity', syn: ['mango', 'mangue', 'dried mango'] },
  { id: 'x-papaya', c: '#FF8A5C', fam: 'fruity', syn: ['papaya', 'papaye'] },
  { id: 'x-guava', c: '#FF7A8A', fam: 'fruity', syn: ['guava', 'goyave'] },
  { id: 'x-watermelon', c: '#FF5A6E', fam: 'fruity', syn: ['watermelon', 'pasteque'] },
  { id: 'x-kiwi', c: '#8DC63F', fam: 'fruity', syn: ['kiwi'] },
  { id: 'x-tropical', c: '#FFB238', fam: 'fruity', syn: ['tropical', 'tropical fruit', 'fruits tropicaux'] },
  { id: 'x-rhubarb', c: '#D9576B', fam: 'fruity', syn: ['rhubarb', 'rhubarbe', 'rebarbora'] },
  { id: 'x-tamarind', c: '#8A4A2A', fam: 'fruity', syn: ['tamarind', 'tamarin'] },
  // Fruity / citrus
  { id: 'fruity-citrus-fruit-grapefruit', c: '#F26B5B', fam: 'fruity', syn: ['grapefruit', 'pamplemousse'] },
  { id: 'fruity-citrus-fruit-orange', c: '#FF8A1F', fam: 'fruity', syn: ['orange', 'mandarin', 'tangerine', 'clementine', 'naranja', 'blood orange'] },
  { id: 'fruity-citrus-fruit-lemon', c: '#F7E04B', fam: 'fruity', syn: ['lemon', 'citron', 'lemon zest', 'zeste'] },
  { id: 'fruity-citrus-fruit-lime', c: '#9BD13B', fam: 'fruity', syn: ['lime', 'citron vert'] },
  { id: 'fruity-citrus-fruit', c: '#FFB020', fam: 'fruity', syn: ['citrus', 'agrumes', 'citrus fruit'] },
  { id: 'x-yuzu', c: '#F2D43A', fam: 'fruity', syn: ['yuzu'] },
  { id: 'x-bergamot', c: '#CDD94A', fam: 'floral', syn: ['bergamot', 'bergamote', 'earl grey'] },
  { id: 'x-lemongrass', c: '#C9D96A', fam: 'green-vegetative', syn: ['lemongrass', 'lemon grass', 'citronnelle'] },
  // Sour / fermented
  { id: 'sour-fermented-sour-citric-acid', c: '#F3DE3C', fam: 'sour-fermented', syn: ['citric', 'citric acid', 'bright'] },
  { id: 'sour-fermented-sour-malic-acid', c: '#B8D648', fam: 'sour-fermented', syn: ['malic', 'malic acid'] },
  { id: 'sour-fermented-sour', c: '#E1C315', fam: 'sour-fermented', syn: ['sour', 'acidic', 'tart'] },
  { id: 'sour-fermented-alcohol-fermented-winey', c: '#7E1F3D', fam: 'sour-fermented', syn: ['winey', 'wine', 'vineux', 'red wine', 'boozy'] },
  { id: 'x-white-wine', c: '#E6D98A', fam: 'sour-fermented', syn: ['white wine', 'vin blanc'] },
  { id: 'sour-fermented-alcohol-fermented-whiskey', c: '#9C5A23', fam: 'sour-fermented', syn: ['whiskey', 'whisky', 'rum', 'rhum', 'brandy'] },
  { id: 'sour-fermented-alcohol-fermented-fermented', c: '#8E3B5A', fam: 'sour-fermented', syn: ['fermented', 'funky', 'ferment'] },
  { id: 'sour-fermented-alcohol-fermented-overripe', c: '#A8483A', fam: 'sour-fermented', syn: ['overripe'] },
  // Green / vegetative
  { id: 'green-vegetative-green-vegetative-herb-like', c: '#5FA97A', fam: 'green-vegetative', syn: ['herbal', 'herbs', 'mint', 'menthe', 'eucalyptus', 'green tea', 'basil'] },
  { id: 'green-vegetative-green-vegetative-fresh', c: '#6CC48A', fam: 'green-vegetative', syn: ['fresh'] },
  { id: 'green-vegetative-green-vegetative-hay-like', c: '#CDB86A', fam: 'green-vegetative', syn: ['hay', 'straw', 'foin'] },
  { id: 'green-vegetative-olive-oil', c: '#9A9A3A', fam: 'green-vegetative', syn: ['olive oil', 'olive'] },
  { id: 'green-vegetative', c: '#3E8E4E', fam: 'green-vegetative', syn: ['vegetal', 'green', 'grassy'] },
  // Other
  { id: 'other-papery-musty-woody', c: '#8A6A4A', fam: 'other', syn: ['woody', 'wood', 'cedar', 'oak', 'boise'] },
  { id: 'other-papery-musty-musty-earthy', c: '#6B4E36', fam: 'other', syn: ['earthy', 'terreux'] },
  { id: 'other-papery-musty-animalic', c: '#5E3F2E', fam: 'other', syn: ['leather', 'cuir'] },
  { id: 'other-chemical-salty', c: '#BFD3D9', fam: 'other', syn: ['salty', 'saline', 'sea salt'] },
  // Roasted
  { id: 'roasted-tobacco', c: '#8A5A32', fam: 'roasted', syn: ['tobacco', 'tabac', 'pipe tobacco'] },
  { id: 'roasted-burnt-smoky', c: '#5A4E48', fam: 'roasted', syn: ['smoky', 'smoke', 'fume'] },
  { id: 'roasted-cereal-grain', c: '#D2A867', fam: 'roasted', syn: ['biscuit', 'bread', 'cookie', 'butter cookie', 'galleta', 'grain', 'toast', 'cereal'] },
  { id: 'roasted-cereal-malt', c: '#B98244', fam: 'roasted', syn: ['malt', 'malty'] },
  // Spices
  { id: 'spices-pepper', c: '#3D3532', fam: 'spices', syn: ['pepper', 'poivre', 'black pepper', 'pink pepper'] },
  { id: 'spices-brown-spice-anise', c: '#4A3B5C', fam: 'spices', syn: ['anise', 'anis', 'licorice', 'reglisse'] },
  { id: 'spices-brown-spice-nutmeg', c: '#A0603A', fam: 'spices', syn: ['nutmeg', 'muscade'] },
  { id: 'spices-brown-spice-cinnamon', c: '#B5562A', fam: 'spices', syn: ['cinnamon', 'cannelle'] },
  { id: 'spices-brown-spice-clove', c: '#6A2E22', fam: 'spices', syn: ['clove', 'cloves', 'girofle'] },
  { id: 'spices', c: '#9E4A2A', fam: 'spices', syn: ['spice', 'spices', 'spicy', 'epices', 'cardamom', 'ginger'] },
  // Nutty / cocoa
  { id: 'nutty-cocoa-nutty-peanuts', c: '#C89A5A', fam: 'nutty-cocoa', syn: ['peanut', 'peanuts', 'cacahuete'] },
  { id: 'nutty-cocoa-nutty-hazelnut', c: '#A8693A', fam: 'nutty-cocoa', syn: ['hazelnut', 'noisette', 'praline'] },
  { id: 'nutty-cocoa-nutty-almond', c: '#E2C49A', fam: 'nutty-cocoa', syn: ['almond', 'amande', 'marzipan', 'cashew', 'pecan', 'walnut', 'nougat'] },
  { id: 'nutty-cocoa-nutty', c: '#B98552', fam: 'nutty-cocoa', syn: ['nutty', 'nuts'] },
  { id: 'nutty-cocoa-cocoa-chocolate', c: '#6B3A26', fam: 'nutty-cocoa', syn: ['chocolate', 'chocolat', 'cocoa', 'cacao', 'cacao nibs', 'cocoa nibs'] },
  { id: 'x-milk-chocolate', c: '#8B5A3C', fam: 'nutty-cocoa', syn: ['milk chocolate', 'chocolat au lait'] },
  { id: 'nutty-cocoa-cocoa-dark-chocolate', c: '#3E2218', fam: 'nutty-cocoa', syn: ['dark chocolate', 'chocolat noir', 'bittersweet', 'chocolate amargo'] },
  { id: 'x-cola', c: '#4A1E14', fam: 'nutty-cocoa', syn: ['cola'] },
  // Sweet
  { id: 'sweet-brown-sugar-molasses', c: '#4A2A1A', fam: 'sweet', syn: ['molasses', 'melasse'] },
  { id: 'sweet-brown-sugar-maple-syrup', c: '#C2702A', fam: 'sweet', syn: ['maple', 'maple syrup', 'erable'] },
  { id: 'sweet-brown-sugar-caramelized', c: '#D08A2E', fam: 'sweet', syn: ['caramel', 'caramelized', 'butterscotch', 'dulce de leche'] },
  { id: 'x-toffee', c: '#B8661F', fam: 'sweet', syn: ['toffee'] },
  { id: 'sweet-brown-sugar-honey', c: '#F0B23A', fam: 'sweet', syn: ['honey', 'miel', 'honeyed'] },
  { id: 'sweet-brown-sugar', c: '#C47A35', fam: 'sweet', syn: ['brown sugar', 'cassonade', 'sucre brun'] },
  { id: 'x-cane-sugar', c: '#E2B878', fam: 'sweet', syn: ['cane sugar', 'panela', 'raw sugar', 'sucre de canne'] },
  { id: 'sweet-vanilla', c: '#F2DFAE', fam: 'sweet', syn: ['vanilla', 'vanille', 'vanilla bean'] },
  { id: 'sweet-sweet-aromatics', c: '#FFB3D1', fam: 'sweet', syn: ['candy', 'cotton candy', 'marshmallow', 'bonbon'] },
  { id: 'sweet-overall-sweet', c: '#F2B8A0', fam: 'sweet', syn: ['sweet', 'sweetness', 'sucre'] },
  { id: 'x-cream', c: '#F3E7CF', fam: 'sweet', syn: ['cream', 'creamy', 'butter', 'buttery', 'creme'] },
  // Floral
  { id: 'floral-black-tea', c: '#B5652E', fam: 'floral', syn: ['black tea', 'tea', 'the noir'] },
  { id: 'floral-floral-chamomile', c: '#F2D46B', fam: 'floral', syn: ['chamomile', 'camomille'] },
  { id: 'floral-floral-rose', c: '#E85A8A', fam: 'floral', syn: ['rose', 'rosewater', 'eau de rose'] },
  { id: 'x-hibiscus', c: '#C2185B', fam: 'floral', syn: ['hibiscus'] },
  { id: 'floral-floral-jasmine', c: '#F5EDD6', fam: 'floral', syn: ['jasmine', 'jasmin', 'orange blossom', 'fleur d oranger', 'elderflower'] },
  { id: 'x-lavender', c: '#9A86C8', fam: 'floral', syn: ['lavender', 'lavande', 'violet'] },
  { id: 'x-honeysuckle', c: '#F5DC86', fam: 'floral', syn: ['honeysuckle', 'chevrefeuille'] },
  { id: 'floral-floral', c: '#E58FB8', fam: 'floral', syn: ['floral', 'flowers', 'flowery'] },
];

// Level-1 wheel colours from flavor-wheel.json (what the current card darkens for its title).
const WHEEL_FAMILY = {
  'fruity': '#DA1D23', 'sour-fermented': '#E1C315', 'green-vegetative': '#1F8A3B', 'other': '#2C6FB0',
  'roasted': '#C0392B', 'spices': '#8E2B22', 'nutty-cocoa': '#A0674B', 'sweet': '#E86A5A', 'floral': '#DA5C8C',
};

// OriginCode whitelist (Kohi/Process/OriginCode.swift)
const ORIGIN_CODE = {
  'Ethiopia': 'ET', 'Kenya': 'KE', 'Rwanda': 'RW', 'Burundi': 'BI', 'Tanzania': 'TZ', 'Uganda': 'UG', 'Colombia': 'CO',
  'Brazil': 'BR', 'Peru': 'PE', 'Bolivia': 'BO', 'Ecuador': 'EC', 'Guatemala': 'GT', 'Honduras': 'HN', 'El Salvador': 'SV',
  'Nicaragua': 'NI', 'Costa Rica': 'CR', 'Panama': 'PA', 'Mexico': 'MX', 'Jamaica': 'JM', 'Indonesia': 'ID', 'Sumatra': 'ID',
  'Java': 'ID', 'Sulawesi': 'ID', 'Papua New Guinea': 'PG', 'India': 'IN', 'Vietnam': 'VN', 'Thailand': 'TH', 'China': 'CN',
  'Yemen': 'YE', 'Myanmar': 'MM', 'Laos': 'LA', 'Taiwan': 'TW', 'Philippines': 'PH', 'Malawi': 'MW', 'Zambia': 'ZM',
  'Nepal': 'NP', 'Zimbabwe': 'ZW', 'Cameroon': 'CM', 'Madagascar': 'MG', 'Haiti': 'HT', 'Dominican Republic': 'DO',
  'Cuba': 'CU', 'Venezuela': 'VE', 'Sri Lanka': 'LK', 'Hawaii': 'US',
};

// TERROIR: ground (the soil the card stands on) + two landscape tones used when notes are missing.
const TERROIR = {
  ET: ['#2C3B22', '#C99A2E', '#9C3A2A'], KE: ['#5A1F17', '#D7742F', '#2F5B3A'], RW: ['#1E4434', '#6FA35A', '#E3BF4A'],
  BI: ['#233F2C', '#C4483A', '#E6D2A0'], TZ: ['#2F2620', '#4E8FB0', '#E6D6AE'], UG: ['#2B3820', '#C9982E', '#A23A2A'],
  CO: ['#173B2C', '#F0BE2F', '#3C6E9E'], BR: ['#37451B', '#E0B23A', '#8A3A1E'], PE: ['#3A2433', '#C2452E', '#E3A13A'],
  BO: ['#2C3350', '#D8D2C6', '#C25A3A'], EC: ['#1D3849', '#E5C13A', '#3A7A5A'], GT: ['#262B37', '#3A8EA8', '#E0563A'],
  HN: ['#1C3747', '#E0A32E', '#2E7A6A'], SV: ['#27303E', '#3A6EA5', '#E3B23A'], NI: ['#2B3828', '#3A7EA0', '#E8C24A'],
  CR: ['#1B3828', '#E2643A', '#6FB8C9'], PA: ['#20323C', '#2E8B7A', '#F0A93A'], MX: ['#3A261C', '#D2483A', '#2E8A6A'],
  JM: ['#1C3756', '#3A8A4A', '#F2C12E'], ID: ['#1B2B23', '#2E7A6A', '#C9822E'], PG: ['#2A1C18', '#C23A2E', '#E8B23A'],
  IN: ['#2B3824', '#E07A2A', '#3A6A8A'], VN: ['#26382A', '#C2342A', '#E8C23A'], TH: ['#2C2838', '#C99A2E', '#3A7A5A'],
  CN: ['#26382E', '#B83A2E', '#8AB06A'], YE: ['#4A311F', '#C99A5A', '#3A6A7A'], MM: ['#3A2C1C', '#D2A23A', '#5A3A6A'],
  LA: ['#23362B', '#C2502E', '#E3C46A'], TW: ['#22323A', '#3A8A7A', '#E0603A'], PH: ['#1C3848', '#E3B23A', '#C23A3A'],
  MW: ['#26364A', '#3A7A4A', '#C9483A'], ZM: ['#2C381C', '#D2702E', '#3A8A4A'], NP: ['#282E42', '#E3E0D8', '#B83A3A'],
  ZW: ['#3A2C1C', '#E0B23A', '#3A7A3A'], CM: ['#2C381C', '#C9452E', '#E8C23A'], MG: ['#47271B', '#C2502A', '#3A7A5A'],
  HT: ['#1C2C48', '#C23A3A', '#3A8A6A'], DO: ['#1C3858', '#C23A3A', '#3A8A5A'], CU: ['#1C384E', '#3A8A6A', '#E0B23A'],
  VE: ['#2C3828', '#E0B23A', '#3A5AA0'], LK: ['#243828', '#E0A02E', '#A0302E'], US: ['#241E1C', '#3A8A6A', '#E06A3A'],
};
const TERROIR_UNKNOWN = ['#3A2E26', '#B98552', '#6B4E36'];

// PROCESS: how the coffee was processed decides the energy of the field.
const PROCESS = {
  washed:    { label: 'Washed', fr: 'lavé — net, clair', warp: 0.05, grain: 0.30, chroma: 1.00, sharp: 1.25, swirl: 0 },
  natural:   { label: 'Natural', fr: 'nature — chaud, dense', warp: 0.11, grain: 0.40, chroma: 1.12, sharp: 1.5, swirl: 0, warm: 0.012 },
  honey:     { label: 'Honey', fr: 'honey — halo doré', warp: 0.08, grain: 0.36, chroma: 1.08, sharp: 1.4, swirl: 0, extra: { c: '#EDB13B', w: 0.8, s: 0.2 } },
  anaerobic: { label: 'Anaerobic', fr: 'fermentation — saturé, tourbillon', warp: 0.18, grain: 0.46, chroma: 1.24, sharp: 1.8, swirl: 1.1, extra: { c: '#7A1E46', w: 0.75, s: 0.16 } },
  wetHulled: { label: 'Wet-hulled', fr: 'wet-hulled — terreux, grain lourd', warp: 0.07, grain: 0.58, chroma: 0.95, sharp: 1.3, swirl: 0, darken: 0.05 },
  unknown:   { label: '—', fr: 'inconnu — réglage moyen', warp: 0.08, grain: 0.36, chroma: 1.05, sharp: 1.4, swirl: 0 },
};

function classifyProcess(raw) {
  const p = norm(raw);
  if (!p) return 'unknown';
  if (/anaer|carbon|macera|thermal|co ?ferm|infus|lactic|yeast|koji|experimental|double/.test(p)) return 'anaerobic';
  if (/wet ?hull|giling/.test(p)) return 'wetHulled';
  if (/honey|miel|pulped|semi ?wash/.test(p)) return 'honey';
  if (/natur|dry|sun ?dried/.test(p)) return 'natural';
  if (/wash|lavad|lave|fully/.test(p)) return 'washed';
  return 'unknown';
}

const ROAST = {
  superLight: { label: 'Super light', dL: 0.07 }, light: { label: 'Light', dL: 0.04 }, mediumLight: { label: 'Medium light', dL: 0.02 },
  medium: { label: 'Medium', dL: 0 }, mediumDark: { label: 'Medium dark', dL: -0.05 }, dark: { label: 'Dark', dL: -0.1 },
};

// The archive. Real coffees from the grid and from backstages/planche.png; notes only where the bag or the
// sample archive states them. Empty fields are left empty on purpose: that is the fallback path.
const COLLECTION = [
  { id: '0b6e2c1a-7d4f-4e8a-9a51-3c2f8e6b1d01', roaster: 'Klover Coffee Paris', name: 'Nano Challa', country: 'Ethiopia', region: 'Geera, Jimma', altitude: '2048', process: 'Washed', variety: 'Heirloom', roast: 'light', notes: ['Floral', 'Citrus', 'Stonefruits'], inkHue: 0.64, symbol: 'klover' },
  { id: '5c1d9f02-3b8e-41f7-8d2c-6a4e0f9b7c12', roaster: 'Coffee Collective', name: 'Kenya Tekangu', country: 'Kenya', region: 'Nyeri', altitude: '1800', process: 'Washed', variety: '', roast: 'light', notes: ['Floral', 'Red Currant', 'Vanilla'] },
  { id: '9a7e3c44-1f2b-4d6e-b0a8-2e5c7d9f1a23', roaster: '', name: 'Chelbesa', country: 'Ethiopia', region: 'Gedeb, Gedeo', altitude: '2050', process: 'Natural', variety: 'Heirloom Landrace', roast: 'light', notes: ['Blueberry', 'Jasmine', 'Cane Sugar'] },
  { id: 'e2f4a6b8-c0d2-4e6f-8a0b-1c3d5e7f9a34', roaster: 'Manhattan', name: 'El Paraíso Lychee', country: 'Colombia', region: 'Piendamó, Cauca', altitude: '1930', process: 'Double Anaerobic', variety: 'Castillo', roast: 'light', notes: ['Lychee', 'Rose', 'Passionfruit'] },
  { id: '3d5f7a9c-b1e3-4f5a-9c7e-0b2d4f6a8c45', roaster: 'Clima Cafecito', name: 'Huabal', country: 'Peru', region: 'Huabal', altitude: '1825', process: 'Lavado', variety: '', roast: '', notes: ['Orange', 'Crisp Apple', 'Dark Chocolate'], inkHue: 0.60, symbol: 'angel' },
  { id: '7b9d1f3a-5c7e-4a9b-8d1f-3a5c7e9b1d56', roaster: 'Tim Wendelboe', name: 'El Injerto Pacamara', country: 'Guatemala', region: 'La Libertad, Huehuetenango', altitude: '1650', process: 'Washed', variety: 'Pacamara', roast: 'light', notes: ['Toffee', 'Orange', 'Cocoa'] },
  { id: 'c4e6a8b0-d2f4-4a6c-8e0b-2d4f6a8c0e67', roaster: 'La Cabra', name: 'Hartmann Geisha', country: 'Panama', region: 'Santa Clara, Volcán', altitude: '1500', process: 'Honey', variety: 'Geisha', roast: 'light', notes: ['Peach', 'Bergamot', 'Honeysuckle'] },
  { id: '1a3c5e7b-9d1f-4b3d-a5e7-9c1e3a5b7d78', roaster: '', name: 'Gallardo Family', country: 'Panama', region: '', altitude: '', process: '', variety: '', roast: '', notes: [], inkHue: 0.20, symbol: 'panama' },
  { id: '8f0b2d4c-6e8a-4c2e-b4f6-8a0c2e4d6f89', roaster: 'Nomad', name: 'Lychee Sidra', country: 'Colombia', region: 'Acevedo, Huila', altitude: '', process: '', variety: 'Bourbon Sidra', roast: '', notes: ['Lychee', 'Pineapple', 'Cacao Nibs'] },
  { id: '4c6e8a0d-2f4b-4d6f-8b0d-4f6b8d0f2a90', roaster: 'Raw Sugar', name: 'Rio Ata Geisha', country: 'Colombia', region: 'Planadas, Tolima', altitude: '1800-1900', process: 'Washed', variety: 'Geisha', roast: '', notes: ['Lemon Grass', 'Pineapple', 'Pear'] },
  { id: 'a0c2e4f6-8b0d-4f2a-9c4e-6b8d0f2a4ca1', roaster: 'Brut', name: 'Hacienda La Papaya', country: 'Ecuador', region: '', altitude: '', process: 'Washed', variety: 'Gesha', roast: '', notes: ['Lime', 'Grapefruit', 'Dried Mango'], inkHue: 0.11 },
  { id: '6e8a0c2f-4b6d-4f8b-a0c2-8d0f2b4d6eb2', roaster: 'Industra Coffee', name: 'Kiamugumo AA', country: 'Kenya', region: '', altitude: '', process: '', variety: '', roast: '', notes: ['Blackcurrant', 'Rhubarb'], inkHue: 0.93 },
  { id: 'b2d4f6a8-0c2e-4a4c-b6e8-0f2b4d6f8ac3', roaster: 'Beanroom', name: 'Beanroom', country: 'Ethiopia', region: 'Bench Maji', altitude: '2060', process: '', variety: '', roast: '', notes: [] },
  { id: 'd4f6b8c0-2e4a-4c6e-8f0a-2b4d6f8b0ce4', roaster: 'Townsfolk Coffee', name: 'Ethiopia Chelchele', country: 'Ethiopia', region: '', altitude: '', process: 'Washed', variety: '', roast: '', notes: [] },
  { id: 'f6b8d0e2-4a6c-4e8a-b0c2-4d6f8b0d2ef5', roaster: 'Blue Bottle', name: 'Three Africas', country: '', region: '', altitude: '', process: '', variety: '', roast: '', notes: ['Golden Raisin', 'Winey Blueberry', 'Lemon Zest'], inkHue: 0.58, symbol: 'bottle' },
  { id: '2f4b6d8e-0a2c-4e4f-a6b8-6f8b0d2f4a06', roaster: '', name: 'Fazenda Sertão', country: 'Brazil', region: 'Carmo de Minas, Minas Gerais', altitude: '1150', process: 'Pulped Natural', variety: 'Yellow Bourbon', roast: 'medium', notes: ['Hazelnut', 'Milk Chocolate', 'Almond'] },
];

function norm(s) {
  return String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
}

// Note → aroma entry. Longest synonym found inside the note wins ("Winey Blueberry" → blueberry).
function matchAroma(note) {
  const n = ' ' + norm(note) + ' ';
  if (n.trim() === '') return null;
  let best = null, bestLen = 0;
  for (const a of AROMA) {
    for (const s of a.syn) {
      const k = ' ' + s + ' ';
      if (n.includes(k) && s.length > bestLen) { best = a; bestLen = s.length; }
      else if (s.length > 4 && n.includes(' ' + s) && s.length > bestLen) { best = a; bestLen = s.length; }
    }
  }
  return best;
}
