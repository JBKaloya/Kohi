const TASTINGS = [
  { name: "Panama Geisha", roaster: "La Cabra", place: "April Coffee", date: "12 Oct", method: "V60", price: "€7.50", rating: 5 },
  { name: "Ethiopia Gesha Village", roaster: "Coffee Collective", place: "April Coffee", date: "12 Oct", method: "Espresso", price: "€4.00", rating: 4 },
  { name: "Kenya Kiambu", roaster: "La Cabra", place: "ACID", date: "3 Oct", method: "Batch", price: "¥800", rating: 4 },
  { name: "House filter", roaster: "Ten Belles", place: "Ten Belles", date: "28 Sep", method: "Filter", price: "", rating: 3 },
];

const SUGGESTIONS = [
  { name: "Colombia Geisha", roaster: "Hydrangea", source: "In My Coffees" },
  { name: "Panama Geisha", roaster: "La Cabra", source: "Tasted before" },
  { name: "Ethiopia Gesha Village", roaster: "Coffee Collective", source: "Tasted before" },
  { name: "Kenya Kiambu", roaster: "La Cabra", source: "Tasted before" },
];

const NEARBY = [
  { name: "April Coffee", line: "40 m · served La Cabra", source: "Paris seed" },
  { name: "Fringe", line: "120 m", source: "Maps" },
  { name: "Ten Belles", line: "260 m", source: "Paris seed" },
];

const METHODS = ["Espresso", "Filter", "V60", "Kalita", "AeroPress", "Batch", "Other"];
const AXES = ["acidity", "bitterness", "body", "complexity"];
const HEADINGS = {
  correction: "Correction",
  next: "For next time",
  better: "For better coffee next time",
};

const state = {
  step: "list",
  listView: "coffees",
  empty: false,
  location: "granted",
  placeState: "suggested",
  placeName: "",
  coffee: "",
  roaster: "",
  linked: false,
  detailsOpen: false,
  method: "V60",
  rating: 0,
  heading: "next",
  wishes: { acidity: -1, bitterness: 0, body: 0, complexity: 1 },
  muddy: false,
  better: false,
};

const phone = document.getElementById("after-phone");
const notes = document.getElementById("after-notes");
const pills = document.getElementById("pills");
const correctionPhone = document.getElementById("correction-phone");
const correctionSignals = document.getElementById("correction-signals");
const correctionResult = document.getElementById("correction-result");
const headings = document.getElementById("headings");

function getState() {
  return structuredClone(state);
}

function setState(patch) {
  const previousLocation = state.location;
  Object.assign(state, patch);
  if (patch.wishes) state.wishes = { ...patch.wishes };
  if (
    patch.location &&
    patch.location !== previousLocation &&
    patch.placeState == null &&
    state.placeState !== "confirmed"
  ) {
    state.placeState = patch.location === "granted" ? "suggested" : "none";
  }
  render();
  document.dispatchEvent(new CustomEvent("kohi-review-sync"));
}

function startCompose() {
  setState({
    step: "compose",
    placeState: state.location === "granted" ? "suggested" : "none",
    placeName: "",
    coffee: "",
    roaster: "",
    linked: false,
    detailsOpen: false,
    rating: 0,
  });
}

function render() {
  const focusKey = document.activeElement?.dataset?.focus;
  const caret = document.activeElement?.selectionStart;
  const canSave = state.coffee.trim().length > 0 && state.placeState === "confirmed";

  pills.replaceChildren(
    pill("1 · Liste", state.step === "list", () => setState({ step: "list" })),
    pill("2 · Nouvelle dégustation", state.step === "compose", startCompose),
    pill("3 · Détail", state.step === "detail", () => setState({ step: "detail" })),
    pill("4 · Lieu", state.step === "place", () => setState({ step: "place" })),
    pill("Localisation autorisée", state.location === "granted", () => setState({ location: "granted" })),
    pill("Localisation refusée", state.location === "denied", () => setState({ location: "denied" })),
    pill("Aucune dégustation", state.empty, () => setState({ empty: !state.empty })),
  );

  phone.replaceChildren();
  if (state.step === "list") phone.append(listScreen());
  if (state.step === "compose") phone.append(composeScreen(canSave));
  if (state.step === "detail") phone.append(detailScreen());
  if (state.step === "place") phone.append(placeScreen());

  notes.replaceChildren(notesBlock(canSave));
  renderCorrection();

  if (focusKey) {
    const next = document.querySelector(`[data-focus="${focusKey}"]`);
    if (next) {
      next.focus();
      if (caret != null && next.setSelectionRange) next.setSelectionRange(caret, caret);
    }
  }
}

function listScreen() {
  const body = el("div", { class: "phone-body stack gap-18" });
  body.append(tabRail());
  if (state.empty) {
    const empty = el("div", { class: "stack gap-10", style: "align-items:center;text-align:center;padding:48px 12px" });
    empty.append(
      el("div", { class: "empty-art" }),
      el("div", {}, "Your coffee discoveries start here."),
      el("p", { class: "note", style: "text-align:center" }, "Save a coffee you’ve tasted at a coffee shop."),
      el("button", { type: "button", class: "linkish", onclick: startCompose }, "Add your first tasting"),
    );
    body.append(empty);
  } else {
    const sub = el("div", { class: "sub" });
    sub.append(
      subButton("Coffees", state.listView === "coffees", () => setState({ listView: "coffees" })),
      subButton("Places", state.listView === "places", () => setState({ listView: "places" })),
    );
    body.append(sub);
    if (state.listView === "coffees") {
      body.append(el("span", { class: "cat" }, "October 2026"));
      TASTINGS.slice(0, 3).forEach((tasting) => body.append(tastingRow(tasting)));
      body.append(el("span", { class: "cat", style: "margin-top:14px" }, "September 2026"));
      body.append(tastingRow(TASTINGS[3]));
    } else {
      body.append(placeRow("April Coffee", "Paris", "3 visits · 4 coffees · last 12 Oct"));
      body.append(placeRow("ACID", "Tokyo", "1 visit · 1 coffee · 3 Oct"));
      body.append(placeRow("Ten Belles", "Paris", "2 visits · 2 coffees · 28 Sep"));
    }
  }
  const fab = el("div", { class: "fab" });
  fab.append(el("button", { type: "button", "aria-label": "Add a tasting", onclick: startCompose }, "+"));
  const frame = el("div");
  frame.append(pad(wordmark()), body, fab);
  return frame;
}

function composeScreen(canSave) {
  const body = el("div", { class: "phone-body stack gap-18" });
  const where = el("div", { class: "stack gap-8" });
  where.append(el("span", { class: "cat" }, "Where"), placeBlock());
  const what = el("div", { class: "stack gap-8" });
  what.append(el("span", { class: "cat" }, "What"));
  const input = el("input", {
    class: "coffee-input",
    "data-focus": "coffee",
    placeholder: "Panama Geisha",
    oninput: (event) => setState({ coffee: event.target.value, linked: false }),
  });
  input.value = state.coffee;
  what.append(input);
  const query = state.coffee.trim().toLowerCase();
  const matches =
    query.length >= 2 && !SUGGESTIONS.some((item) => item.name.toLowerCase() === query)
      ? SUGGESTIONS.filter((item) => item.name.toLowerCase().includes(query) || item.roaster.toLowerCase().includes(query))
      : [];
  for (const match of matches) {
    what.append(
      el("button", {
        type: "button",
        class: "hit",
        onclick: () => setState({
          coffee: match.name,
          roaster: match.roaster,
          linked: match.source === "In My Coffees",
        }),
      }, `${match.name} · ${match.roaster} · ${match.source}`),
    );
  }
  if (state.linked) what.append(el("span", { class: "mono muted" }, "Linked to your card · the card is not edited"));
  const chips = el("div", { class: "row gap-6 wrap" });
  chips.append(el("span", { class: "chip" }, "From My Coffees"), el("span", { class: "chip" }, "Scan bag"), el("span", { class: "chip" }, "Scan menu"));
  what.append(chips);

  const details = el("div", { class: "stack gap-10" });
  details.append(
    el("button", {
      type: "button",
      class: "hit",
      style: "border-top:none",
      onclick: () => setState({ detailsOpen: !state.detailsOpen }),
    }, `Details · ${state.detailsOpen ? "−" : `${state.roaster || "Roaster"} · ${state.method} · Today`}`),
  );
  if (state.detailsOpen) {
    details.append(staticField("Roaster", state.roaster || "La Cabra"));
    const methods = el("div", { class: "row gap-6 wrap" });
    for (const method of METHODS) {
      methods.append(el("button", {
        type: "button",
        class: method === state.method ? "chip on" : "chip",
        onclick: () => setState({ method }),
      }, method));
    }
    details.append(el("span", { class: "mono muted" }, "Method"), methods);
    details.append(staticField("Cup price", "7.50 EUR"), staticField("Date", "Today"));
  }

  const tasting = el("div", { class: "stack gap-10" });
  tasting.append(el("span", { class: "cat" }, "Your tasting"), dots(state.rating, (rating) => setState({ rating })));
  const flavors = el("div", { class: "stack gap-6" });
  flavors.append(
    el("span", { class: "mono muted" }, "On the pack"),
    el("span", { class: "row gap-6 wrap" }, [el("span", { class: "chip" }, "Jasmine"), el("span", { class: "chip" }, "Peach")]),
    el("span", { class: "mono muted" }, "In your cup"),
    el("span", { class: "row gap-6 wrap" }, [el("span", { class: "chip on" }, "Jasmine"), el("span", { class: "chip on" }, "Bergamot")]),
  );
  const tasteRow = el("div", { class: "row gap-14" });
  tasteRow.append(radar(110), flavors);
  tasting.append(tasteRow, staticField("Note to self", "Brighter than the bag at home"));

  body.append(where, what, details, tasting);
  const frame = el("div");
  frame.append(
    pad(navBar("Cancel", "New tasting", canSave ? "Save" : "", () => setState({ step: "list" }), () => setState({ step: "detail" }))),
    body,
  );
  return frame;
}

function placeBlock() {
  if (state.placeState === "confirmed") {
    const row = el("div", { class: "between" });
    row.append(
      el("div", { class: "stack" }, [el("strong", {}, state.placeName), el("span", { class: "mono muted" }, "Paris · France")]),
      el("button", { type: "button", class: "linkish", onclick: () => setState({ placeState: "picking" }) }, "Change"),
    );
    return row;
  }
  if (state.placeState === "suggested") {
    const block = el("div", { class: "stack gap-8" });
    const row = el("div", { class: "row gap-8 wrap" });
    row.append(
      el("button", { type: "button", class: "chip", onclick: () => setState({ placeName: "April Coffee", placeState: "confirmed" }) }, "April Coffee? · 40 m"),
      el("button", { type: "button", class: "linkish", onclick: () => setState({ placeState: "picking" }) }, "Other place"),
    );
    block.append(row, el("span", { class: "mono muted" }, "A suggestion. Saved only once you tap it."));
    return block;
  }
  if (state.placeState === "manual") {
    const block = el("div", { class: "stack gap-10" });
    block.append(
      staticField("Name", "Café Kitsuné"),
      staticField("Address", "Optional"),
      el("button", { type: "button", class: "linkish", onclick: () => setState({ placeName: "Café Kitsuné", placeState: "confirmed" }) }, "Use this place"),
    );
    return block;
  }
  if (state.placeState === "picking") {
    const block = el("div", { class: "stack gap-8" });
    if (state.location === "granted") {
      block.append(el("span", { class: "mono muted" }, "Nearby"));
      for (const place of NEARBY) {
        block.append(el("button", {
          type: "button",
          class: "hit",
          onclick: () => setState({ placeName: place.name, placeState: "confirmed" }),
        }, `${place.name} · ${place.line}`));
      }
    }
    block.append(
      el("div", { class: "search" }, "Search a coffee shop"),
      el("button", { type: "button", class: "linkish", onclick: () => setState({ placeState: "manual" }) }, "+ Add it by hand"),
    );
    return block;
  }
  const block = el("div", { class: "stack gap-8" });
  block.append(
    el("button", { type: "button", class: "hit", onclick: () => setState({ placeState: "picking" }) }, "Choose a place"),
    el("span", { class: "mono muted" }, "No location: search, or add it by hand."),
  );
  return block;
}

function detailScreen() {
  const coffee = state.coffee || "Panama Geisha";
  const roaster = state.roaster || "La Cabra";
  const place = state.placeName || "April Coffee";
  const body = el("div", { class: "phone-body stack gap-14" });
  body.append(
    el("div", { class: "serif", style: "font-size:20px" }, coffee),
    el("span", { class: "cat" }, "Coffee"),
    staticField("Roaster", roaster),
    staticField("Origin", "Panama · Boquete"),
    staticField("Process", "Washed"),
    staticField("On the pack", "Jasmine · Peach"),
    el("span", { class: "cat" }, "Experience"),
  );
  const placeButton = el("button", { type: "button", class: "field", onclick: () => setState({ step: "place" }) });
  placeButton.append(el("span", { class: "cat" }, "Place"), el("span", {}, `${place} ↗`));
  body.append(placeButton, staticField("Date", "Today"), staticField("Method", state.method), staticField("Cup price", "€7.50"));
  body.append(el("span", { class: "cat" }, "Your tasting"), dots(state.rating || 5));
  const taste = el("div", { class: "row gap-14" });
  taste.append(radar(96), el("span", { class: "chip on" }, "Jasmine"));
  body.append(taste, el("p", { class: "note" }, "Brighter than the bag at home."));
  const actions = el("div", { class: "row gap-14" });
  actions.append(el("span", { class: "mono" }, "Edit"), el("span", { class: "mono" }, "Delete"));
  if (state.linked) actions.append(el("span", { class: "mono" }, "Open in Coffee Collection"));
  body.append(actions, el("p", { class: "note" }, "No correction. You don’t set the barista’s recipe."));
  const frame = el("div");
  frame.append(pad(navBar("‹ Tastings", "", "", () => setState({ step: "list" }))), body);
  return frame;
}

function placeScreen() {
  const body = el("div", { class: "phone-body stack gap-14" });
  body.append(
    el("div", { class: "serif", style: "font-size:20px" }, "April Coffee"),
    el("p", { class: "note" }, "48 rue Sedaine · Paris · France ↗"),
  );
  const stats = el("div", { class: "row gap-18" });
  for (const [value, label] of [["3", "visits"], ["4", "coffees"], ["2", "roasters"]]) {
    stats.append(el("div", { class: "stack" }, [el("strong", {}, value), el("span", { class: "mono muted" }, label)]));
  }
  body.append(stats, el("span", { class: "cat" }, "Coffees tasted here"));
  TASTINGS.filter((tasting) => tasting.place === "April Coffee").forEach((tasting) => body.append(tastingRow(tasting, true)));
  body.append(tastingRow({ name: "Burundi Ninga", roaster: "Coffee Collective", date: "2 Sep", method: "Filter", price: "€6.00", rating: 3 }, true));
  body.append(el("span", { class: "mono muted" }, "No venue score. Ratings stay on each cup."));
  const frame = el("div");
  frame.append(pad(navBar("‹ Places", "", "", () => setState({ step: "list" }))), body);
  return frame;
}

function notesBlock(canSave) {
  if (state.step === "list") {
    return textBlock(
      "Tastings, la liste",
      "Troisième onglet du rail existant, sans nouvelle navigation. Il s’affiche même sans aucune fiche café, pour quelqu’un qui ne fait que des dégustations. Coffees liste les dégustations de la plus récente à la plus ancienne. Places regroupe les lieux visités, et un lieu n’est jamais fusionné sur son seul nom. Le bouton rond ouvre la saisie.",
    );
  }
  if (state.step === "compose") {
    const placeLine = state.placeState === "confirmed"
      ? "Lieu confirmé."
      : state.location === "denied"
        ? "Sans localisation : recherche, ou lieu ajouté à la main."
        : "Le lieu proposé n’est qu’une suggestion. Il faut le toucher pour le retenir.";
    const block = textBlock(
      "Un seul écran, le lieu d’abord",
      "Tape un nom de café, choisis ou confirme un lieu : Save apparaît. Tant qu’il manque l’un des deux, il n’y a pas de bouton, ce qui suit la règle du design system pour une action pas encore possible. Essaie « Geisha » ou « La Cabra » pour les suggestions.",
    );
    block.append(
      el("strong", {}, canSave ? "Save visible : nom et lieu présents." : "Save masqué : il manque le nom ou le lieu."),
      el("p", { class: "note" }, placeLine),
    );
    return block;
  }
  if (state.step === "detail") {
    return textBlock(
      "Le détail",
      "La fiche garde le café tel qu’il était ce jour-là. Si tu modifies ou supprimes ta fiche café, la dégustation ne change pas. « Open in… » n’apparaît que si la dégustation est liée à un café de ta collection. Le lieu ouvre sa propre page.",
    );
  }
  return textBlock(
    "Un lieu",
    "Nom, adresse, ville et pays, nombre de visites, cafés goûtés. Un lieu sert plusieurs torréfacteurs : April Coffee sert La Cabra et Coffee Collective. Pas de note de lieu : les notes restent sur chaque tasse.",
  );
}

function renderCorrection() {
  headings.replaceChildren();
  headings.append(el("span", { class: "note" }, "Titre :"));
  for (const [key, label] of Object.entries(HEADINGS)) {
    headings.append(pill(label, state.heading === key, () => setState({ heading: key })));
  }

  const body = el("div", { class: "phone-body stack gap-14" });
  body.append(el("div", { class: "serif", style: "font-size:20px" }, "Huabal"));
  body.append(el("span", { class: "cat" }, "Rating"), dots(3));
  body.append(el("span", { class: "cat" }, HEADINGS[state.heading]));
  for (const axis of AXES) {
    body.append(wishRow(axis, state.wishes[axis], (value) => {
      setState({ wishes: { ...state.wishes, [axis]: value } });
    }));
  }
  body.append(el("span", { class: "mono muted" }, "Tap the lit step again to go back to “as is”."));
  correctionPhone.replaceChildren(pad(navBar("‹", "It's done", "Save")), body);

  correctionSignals.replaceChildren(
    el("strong", {}, "Ce que Kohi sait déjà de ce brew"),
    el("div", { class: "row gap-6 wrap" }, [
      pill("Clarity 3/10 sur le radar", state.muddy, () => setState({ muddy: !state.muddy })),
      pill("Meilleure tasse le 26 Sep (94 °C)", state.better, () => setState({ better: !state.better })),
    ]),
    el("p", { class: "note" }, "Ces signaux viennent du radar et de l’historique de ce café. Ils servent à appuyer, ou non, une envie de complexité."),
  );

  const result = diagnose(state.wishes, state.muddy, state.better);
  const ranked = result.moves.slice().sort((a, b) => a.priority - b.priority);
  const top = ranked[0];
  const column = el("div", { class: "stack gap-14" });
  column.append(el("strong", {}, "Ce que Kohi proposerait"));
  if (top) {
    column.append(el("div", { class: "serif", style: "font-size:22px" }, top.change), el("p", { class: "note" }, top.reason), el("span", { class: "mono muted" }, top.evidence));
  } else {
    column.append(el("p", { class: "note" }, result.quiet));
  }
  for (const line of result.notes) column.append(el("p", { class: "note" }, line));
  const others = ranked.slice(1);
  if (others.length) {
    column.append(el("strong", {}, "Aussi envisagé, moins prioritaire"));
    for (const move of others) column.append(el("p", { class: "note" }, `${move.change} · ${move.reason}`));
  }
  column.append(el("strong", {}, "Ce qui est enregistré"));
  column.append(storedRow("acidity", observed(state.wishes.acidity, "too acidic", "flat")));
  column.append(storedRow("bitterness", observed(state.wishes.bitterness, "too bitter", "not enough")));
  column.append(storedRow("body", observed(state.wishes.body, "heavy", "thin")));
  const complexity = state.wishes.complexity;
  column.append(storedRow(
    "complexity",
    complexity < 0 ? "−1 · wants less" : complexity > 0 ? "+1 · wants more" : "0 · as is (nil if never asked)",
  ));
  column.append(el("p", { class: "note" }, "Les brews existants ne changent pas. Seul l’affichage traduit : un ancien brew noté « acidity + » (trop acide) se lit désormais « less acidity ». Complexity est un champ nouveau et vide sur les anciens brews, jamais lu comme « less » ou « more »."));
  correctionResult.replaceChildren(column);
}

function wishRow(axis, value, onPick) {
  const row = el("div", { class: "wish" });
  row.append(el("span", { class: "name" }, axis[0].toUpperCase() + axis.slice(1)));
  for (const step of [-1, 0, 1]) {
    row.append(el("button", {
      type: "button",
      class: value === step ? "on" : "",
      onclick: () => onPick(value === step ? 0 : step),
    }, step < 0 ? "−" : step > 0 ? "+" : "·"));
  }
  const said = value < 0 ? `less ${axis}` : value > 0 ? `more ${axis}` : "as is";
  row.append(el("span", { class: value === 0 ? "said muted" : "said" }, said));
  return row;
}

function observed(wish, over, under) {
  if (wish < 0) return `+1 · ${over}`;
  if (wish > 0) return `−1 · ${under}`;
  return "0 · balanced";
}

function diagnose(wishes, muddy, better) {
  const acidity = -wishes.acidity;
  const bitterness = -wishes.bitterness;
  const body = -wishes.body;
  const complexity = wishes.complexity;
  const moves = [];
  const notes = [];

  if (acidity > 0 && bitterness > 0) {
    moves.push({
      change: "Leave the grind alone; check the water and the distribution",
      reason: "sour and bitter at once is uneven extraction, not too little of it",
      evidence: "GENERAL COFFEE KNOWLEDGE · partial",
      priority: 10,
    });
    if (complexity !== 0) notes.push("Complexity attend : on règle d’abord l’extraction inégale.");
    return { moves, notes, quiet: "" };
  }

  let reinforced = false;
  if (acidity > 0 && bitterness <= 0) {
    reinforced = complexity > 0;
    moves.push({
      change: "Grind finer",
      reason: reinforced
        ? "probably under-extracted, and an under-extracted cup reads flat, which fits the complexity you want"
        : "probably under-extracted",
      evidence: "GENERAL COFFEE KNOWLEDGE · practice",
      priority: 4,
    });
  }
  if (bitterness > 0 && acidity <= 0) {
    moves.push({
      change: "Grind coarser",
      reason: "probably over-extracted",
      evidence: "GENERAL COFFEE KNOWLEDGE · practice",
      priority: 4,
    });
  }
  if (body < 0 && acidity === 0 && bitterness === 0) {
    moves.push({
      change: "Ratio 1:15 — 450 g of water",
      reason: "thin, but the extraction reads fine — more strength, same extraction",
      evidence: "GENERAL COFFEE KNOWLEDGE · verified",
      priority: 5,
    });
  }
  if (body > 0) {
    moves.push({
      change: "Ratio 1:17 — 510 g of water",
      reason: "heavy or muddy — less strength, or fewer fines",
      evidence: "GENERAL COFFEE KNOWLEDGE · practice",
      priority: 5,
    });
  }
  if (complexity > 0 && !reinforced) {
    if (better) {
      moves.push({
        change: "Go back to 94 °C, as on 26 Sep",
        reason: "your 26 Sep brew of this coffee scored higher on aroma and aftertaste, one setting apart",
        evidence: "DERIVED FROM YOUR BREWS · partial",
        priority: 3,
      });
    } else if (muddy) {
      moves.push({
        change: "Try a paper that runs clearer",
        reason: "clarity 3/10: a muddy cup hides its layers",
        evidence: "GENERAL COFFEE KNOWLEDGE · partial",
        priority: 1,
      });
    } else {
      notes.push("More complexity : pas assez d’éléments pour un réglage fiable. Kohi garde l’envie et la compare à tes prochains brews de ce café.");
    }
  }
  if (complexity < 0) notes.push("Less complexity : aucun réglage proposé sans signal pour l’appuyer.");
  if (wishes.acidity > 0 && moves.length === 0) {
    notes.push("More acidity seul : le moteur n’a pas de règle aujourd’hui. Kohi se tait plutôt que de deviner.");
  }
  const allZero = wishes.acidity === 0 && wishes.bitterness === 0 && wishes.body === 0 && complexity === 0;
  return {
    moves,
    notes,
    quiet: allZero ? "Rien à changer : un brew « as is » partout ne reçoit pas de conseil." : "Aucun réglage proposé.",
  };
}

function textBlock(title, copy) {
  const block = el("div", { class: "stack gap-8" });
  block.append(el("h2", {}, title), el("p", { class: "note" }, copy));
  const order = el("div", { class: "stack gap-8" });
  order.append(el("strong", {}, "Ordre de l’écran de saisie"));
  const rows = [
    ["Where", "Lieu proposé, à confirmer d’un tap. Sinon : à proximité, recherche, ou ajouté à la main."],
    ["What", "Nom du café en texte libre, avec des suggestions tirées de ta collection et de tes dégustations."],
    ["Details", "Torréfacteur, méthode, prix de la tasse, date, origine. Replié par défaut."],
    ["Your tasting", "Note, radar, arômes de la roue, note perso. Aucune correction, aucune complexité."],
  ];
  rows.forEach((row, index) => {
    const line = el("div", { class: "order" });
    line.append(
      el("span", { class: "order-n" }, String(index + 1)),
      el("div", {}, [el("strong", {}, row[0]), el("p", {}, row[1])]),
    );
    order.append(line);
  });
  const wrap = el("div", { class: "stack gap-18" });
  wrap.append(block, order);
  return wrap;
}

function tastingRow(tasting, hidePlace) {
  const button = el("button", { type: "button", class: "hit", onclick: () => setState({ step: "detail" }) });
  const meta = [tasting.date, tasting.method, tasting.price].filter(Boolean).join(" · ");
  button.append(
    el("div", { class: "between" }, [el("strong", {}, tasting.name), dotSpan(tasting.rating)]),
    el("div", { class: "mono muted" }, hidePlace ? tasting.roaster : `${tasting.roaster} · ${tasting.place}`),
    el("div", { class: "mono muted" }, meta),
  );
  return button;
}

function placeRow(name, city, meta) {
  const button = el("button", { type: "button", class: "hit", onclick: () => setState({ step: "place" }) });
  button.append(
    el("div", { class: "between" }, [el("strong", {}, name), el("span", { class: "mono muted" }, city)]),
    el("div", { class: "mono muted" }, meta),
  );
  return button;
}

function dotSpan(value) {
  const row = el("span", { class: "dots tiny" });
  for (let step = 1; step <= 5; step += 1) row.append(el("i", { class: step <= value ? "dot on" : "dot" }));
  return row;
}

function dots(value, onPick) {
  const row = el("div", { class: "dots" });
  for (let step = 1; step <= 5; step += 1) {
    row.append(el("button", {
      type: "button",
      class: step <= value ? "dot on" : "dot",
      "aria-label": `${step} of 5`,
      onclick: onPick ? () => onPick(value === step ? 0 : step) : null,
    }));
  }
  return row;
}

function radar(size) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("width", String(size));
  svg.setAttribute("height", String(size));
  svg.setAttribute("viewBox", `0 0 ${size} ${size}`);
  const c = size / 2;
  const r = size * 0.38;
  const values = [7, 5, 8, 9, 6, 4, 8];
  const point = (i, scale) => {
    const a = -Math.PI / 2 + (i * 2 * Math.PI) / 7;
    return `${c + Math.cos(a) * r * scale},${c + Math.sin(a) * r * scale}`;
  };
  const ring = (scale) => [0, 1, 2, 3, 4, 5, 6].map((i) => point(i, scale)).join(" ");
  for (const scale of [0.4, 0.7, 1]) {
    const shape = document.createElementNS("http://www.w3.org/2000/svg", "polygon");
    shape.setAttribute("points", ring(scale));
    shape.setAttribute("fill", "none");
    shape.setAttribute("stroke", "#e2ddd3");
    svg.appendChild(shape);
  }
  const fill = document.createElementNS("http://www.w3.org/2000/svg", "polygon");
  fill.setAttribute("points", values.map((value, index) => point(index, value / 10)).join(" "));
  fill.setAttribute("fill", "#f6f4ef");
  fill.setAttribute("stroke", "#1a1815");
  svg.appendChild(fill);
  return svg;
}

function tabRail() {
  const rail = el("div", { class: "tabs" });
  for (const tab of ["Coffee Collection", "Recipes", "Tastings"]) {
    rail.append(el("span", { class: tab === "Tastings" ? "on" : "" }, tab));
  }
  return rail;
}

function wordmark() {
  const row = el("div", { class: "wordmark" });
  row.append(el("span", {}, "Kohi"));
  return row;
}

function navBar(left, title, right, onLeft, onRight) {
  const bar = el("div", { class: "nav" });
  bar.append(el("button", { type: "button", onclick: onLeft }, left));
  bar.append(el("strong", {}, title));
  if (right) bar.append(el("button", { type: "button", class: "right", onclick: onRight }, right));
  else bar.append(el("span"));
  return bar;
}

function pad(child) {
  const node = el("div", { class: "phone-pad" });
  node.append(child);
  return node;
}

function staticField(label, value) {
  const row = el("div", { class: "field" });
  row.append(el("span", { class: "cat" }, label), el("span", {}, value));
  return row;
}

function storedRow(key, value) {
  const row = el("div", { class: "store" });
  row.append(el("span", {}, `brew.${key}`), el("span", {}, value));
  return row;
}

function pill(label, on, onclick) {
  return el("button", { type: "button", class: on ? "pill on" : "pill", onclick }, label);
}

function subButton(label, on, onclick) {
  return el("button", { type: "button", class: on ? "on" : "", onclick }, label);
}

function el(tag, props, content) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props || {})) {
    if (value == null) continue;
    if (key === "class") node.className = value;
    else if (key === "onclick" || key === "oninput") node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value);
  }
  const kids = Array.isArray(content) ? content : content == null ? [] : [content];
  for (const kid of kids) {
    if (kid == null) continue;
    node.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
  }
  return node;
}

render();

const { mount } = await import("./review.js");
mount({
  slug: "tastings-before-after",
  title: "Tastings : avant / après",
  root: document.getElementById("review-root"),
  getState,
  setState,
  scenes: [
    { label: "Liste", patch: { step: "list", empty: false }, target: "after" },
    { label: "Saisie", patch: { step: "compose" }, target: "after" },
    { label: "Détail", patch: { step: "detail" }, target: "after" },
    { label: "Lieu", patch: { step: "place" }, target: "after" },
    { label: "Localisation", patch: { location: "granted" }, target: "after" },
    { label: "Sans lieu", patch: { location: "denied" }, target: "after" },
    { label: "Liste vide", patch: { step: "list", empty: true }, target: "after" },
  ],
});
