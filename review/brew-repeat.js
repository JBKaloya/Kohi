const state = {
  persona: "returning",
  screen: "launcher",
  tab: "mine",
  source: "last",
  returnTo: "launcher",
  correction: "pending",
};

const frame = document.getElementById("frame");
const notes = document.getElementById("notes");
const personas = document.getElementById("personas");

function getState() {
  return structuredClone(state);
}

function setState(patch) {
  const previousPersona = state.persona;
  Object.assign(state, patch);
  if (patch.persona && patch.persona !== previousPersona && patch.screen == null) {
    state.screen = patch.persona === "returning" ? "launcher" : "recipes";
    state.tab = patch.persona === "returning" ? "mine" : "pros";
  }
  render();
  document.dispatchEvent(new CustomEvent("kohi-review-sync"));
}

function choosePersona(next) {
  setState({
    persona: next,
    screen: next === "returning" ? "launcher" : "recipes",
    tab: next === "returning" ? "mine" : "pros",
  });
}

function openAmounts(source, from) {
  setState({
    source,
    returnTo: from,
    screen: "amounts",
    correction: source === "last" ? "pending" : state.correction,
  });
}

function back() {
  if (state.screen === "amounts") {
    setState({ screen: state.returnTo });
    return;
  }
  if (state.screen === "previous" || (state.screen === "recipes" && state.persona === "returning")) {
    setState({ screen: "launcher" });
    return;
  }
  if (state.screen === "launcher" || state.screen === "recipes") setState({ screen: "card" });
}

function render() {
  const progress = progressFor(state.persona, state.screen);
  const showBack = state.screen !== "card";
  personas.replaceChildren(
    el("button", { type: "button", class: state.persona === "returning" ? "pill on" : "pill", onclick: () => choosePersona("returning") }, "Déjà un brew"),
    el("button", { type: "button", class: state.persona === "first" ? "pill on" : "pill", onclick: () => choosePersona("first") }, "Premier brew"),
  );
  frame.replaceChildren(
    bar(progress, showBack ? back : null),
    el("div", { class: "brew-title" }, questionFor(state.screen)),
    el("div", { class: "brew-body" }, bodyFor()),
  );
  if (state.screen === "amounts") frame.append(el("div", { class: "brew-foot" }, dial()));
  notes.replaceChildren(notesFor());
}

function bodyFor() {
  if (state.screen === "card") return cardBody();
  if (state.screen === "launcher") return launcherBody();
  if (state.screen === "previous") return previousBody();
  if (state.screen === "recipes") return recipesBody();
  return amountsBody();
}

function cardBody() {
  const block = el("div", { class: "stack gap-14" });
  block.append(el("span", { class: "cat" }, "At home"));
  if (state.persona === "returning") {
    block.append(el("strong", {}, "26 Sep · V60 · Ode"), el("p", { class: "note" }, "30 g · 1:16.7 · 99 °C"));
  } else {
    block.append(el("p", { class: "note" }, "No brew on this coffee yet."));
  }
  block.append(
    el("button", {
      type: "button",
      class: "capsule",
      onclick: () => setState({ screen: state.persona === "returning" ? "launcher" : "recipes" }),
    }, state.persona === "returning" ? "Start a brew" : "Choose a recipe"),
  );
  return block;
}

function launcherBody() {
  return el("div", { class: "stack gap-18" }, [
    choice("cup", "Repeat last", "26 Sep · V60 · 30 g · 1:16.7", () => openAmounts("last", "launcher")),
    choice("list", "Choose a previous brew", "This coffee", () => setState({ screen: "previous" })),
    choice("book", "Use a saved recipe", "Mine", () => setState({ tab: "mine", screen: "recipes" })),
    choice("plus", "Start from scratch", "From the pros", () => setState({ tab: "pros", screen: "recipes" })),
  ]);
}

function previousBody() {
  return el("div", { class: "stack gap-14" }, [
    lineButton("26 Sep · V60 · Ode", "30 g · 1:16.7 · 99 °C", () => openAmounts("last", "previous")),
    lineButton("17 Sep · Batch · Moccamaster", "60 g · 1:16 · 94 °C", () => openAmounts("batch", "previous")),
  ]);
}

function recipesBody() {
  const tabs = el("div", { class: "row gap-14" }, [
    tabButton("Mine", state.tab === "mine", () => setState({ tab: "mine" })),
    tabButton("From the pros", state.tab === "pros", () => setState({ tab: "pros" })),
  ]);
  const block = el("div", { class: "stack gap-14" }, [tabs]);
  if (state.tab === "mine") {
    if (state.persona === "first") block.append(el("p", { class: "note" }, "Recipes you save appear here."));
    else {
      block.append(
        lineButton("Huabal · V60", "30 g · 1:16.7 · 99 °C", () => openAmounts("mine", "recipes")),
        lineButton("Batch · Moccamaster", "60 g · 1:16 · 94 °C", () => openAmounts("mine", "recipes")),
      );
    }
  } else {
    block.append(
      lineButton("V60 · Ultimate", "15 g · 1:16.7 · 93 °C", () => openAmounts("pros", "recipes")),
      lineButton("Kalita · Wave", "20 g · 1:15 · 93 °C", () => openAmounts("pros", "recipes")),
    );
  }
  return block;
}

function amountsBody() {
  const batch = state.source === "batch";
  const pros = state.source === "pros";
  const dose = pros ? "15 g" : batch ? "60 g" : "30 g";
  const water = pros ? "250 g" : batch ? "960 g" : "500 g";
  const ratio = pros || !batch ? "1:16.7" : "1:16";
  const cups = pros ? "About 1 cup" : batch ? "About 4 cups" : "About 2 cups";
  const from = batch
    ? "From 17 Sep · Moccamaster"
    : state.source === "mine"
      ? "Huabal · V60"
      : state.source === "pros"
        ? "V60 · Ultimate"
        : "From 26 Sep · V60 · Ode";
  const block = el("div", { class: "stack gap-14" });
  block.append(el("p", { class: "note" }, from));
  if (state.source === "last" && state.correction === "pending") {
    const insight = el("div", { class: "insight stack gap-8" });
    insight.append(
      el("span", { class: "cat" }, "Applied from your last brew"),
      el("strong", {}, "Grind coarser"),
      el("div", { class: "row gap-14" }, [
        el("button", { type: "button", class: "linkish", onclick: () => setState({ correction: "kept" }) }, "Keep"),
        el("button", { type: "button", class: "linkish", onclick: () => setState({ correction: "undone" }) }, "Undo"),
      ]),
    );
    block.append(insight);
  }
  block.append(el("span", { class: "cat" }, "Coffee"));
  block.append(el("div", { class: "between" }, [
    el("span", {}, `Dose ${dose}`),
    el("span", { class: "muted" }, ratio),
    el("span", {}, `Water ${water}`),
  ]));
  block.append(el("span", { class: "cat" }, cups));
  return block;
}

function notesFor() {
  const block = el("div", { class: "stack gap-10" });
  block.append(el("h2", {}, "Parcours"));
  block.append(el("p", { class: "note" }, state.persona === "returning"
    ? "Start a brew, puis au choix le dernier brew, un brew passé, ou les recettes. Le chevron ramène à l’écran d’où l’on vient."
    : "Pas de lanceur. Les recettes s’ouvrent tout de suite, sur From the pros. Le chevron ramène à la carte."));
  block.append(el("p", { class: "note" }, backCaption()));
  const steps = state.persona === "returning"
    ? [["launcher", "Start a brew"], ["previous", "Previous brews"], ["recipes", "Mine · From the pros"], ["amounts", "How much?"]]
    : [["recipes", "Mine · From the pros"], ["amounts", "How much?"]];
  for (const [id, label] of steps) {
    const current = id === state.screen;
    block.append(el("div", { class: current ? "path-step on" : "path-step" }, label));
  }
  return block;
}

function bar(progress, onBack) {
  const ticks = el("div", { class: "ticks" });
  const total = progress.total === 2 ? [0, 1] : [0, 1, 2];
  for (const index of total) ticks.append(el("span", { class: index === progress.step ? "tick on" : "tick" }));
  const left = el("div", { class: "row gap-10" });
  if (onBack) {
    left.append(el("button", { type: "button", class: "linkish", "aria-label": "Back", onclick: onBack }, "‹"));
  }
  left.append(ticks);
  return el("div", { class: "brew-bar" }, [left, el("span", { class: "muted" }, "×")]);
}

function dial() {
  return el("div", { class: "stack gap-10" }, [
    el("div", { class: "capsule" }, "Brew"),
    el("div", { class: "cat", style: "text-align:center" }, "Log without timer"),
  ]);
}

function choice(glyph, title, detail, onclick) {
  return el("button", { type: "button", class: "choice", onclick }, [
    el("span", { class: "choice-mark" }, glyphMark(glyph)),
    el("span", { class: "stack" }, [el("strong", {}, title), el("span", { class: "mono muted" }, detail)]),
  ]);
}

function lineButton(title, line, onclick) {
  return el("button", { type: "button", class: "brew-line", onclick }, [
    el("strong", {}, title),
    el("div", { class: "mono muted" }, line),
  ]);
}

function tabButton(label, on, onclick) {
  return el("button", { type: "button", class: on ? "lane on" : "lane", onclick }, label);
}

function glyphMark(name) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("width", "16");
  svg.setAttribute("height", "16");
  svg.setAttribute("viewBox", "0 0 16 16");
  svg.setAttribute("aria-hidden", "true");
  const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
  const d = {
    list: "M3 4 H13 M3 8 H13 M3 12 H13",
    book: "M3 3 H8 V13 H3 Z M8 3 H13 V13 H8",
    plus: "M8 3 V13 M3 8 H13",
    cup: "M4 6 H12 V12 H4 Z M6 6 V4 H10 V6",
  }[name];
  path.setAttribute("d", d);
  path.setAttribute("fill", "none");
  path.setAttribute("stroke", "#1a1815");
  path.setAttribute("stroke-width", "1.2");
  svg.append(path);
  return svg;
}

function progressFor(persona, screen) {
  if (persona === "first") return screen === "amounts" ? { step: 1, total: 2 } : { step: 0, total: 2 };
  if (screen === "amounts") return { step: 2, total: 3 };
  if (screen === "previous" || screen === "recipes") return { step: 1, total: 3 };
  return { step: 0, total: 3 };
}

function questionFor(screen) {
  if (screen === "card") return "Huabal";
  if (screen === "launcher") return "Start a brew";
  if (screen === "previous") return "Previous brews";
  if (screen === "recipes") return "Which recipe?";
  return "How much?";
}

function backCaption() {
  if (state.screen === "card") return "Premier écran du parcours. Pas de chevron.";
  if (state.screen === "amounts") return `Chevron : retour vers ${labelFor(state.returnTo)}.`;
  if (state.screen === "previous" || (state.screen === "recipes" && state.persona === "returning")) {
    return "Chevron : retour vers Start a brew.";
  }
  return "Chevron : retour vers la carte.";
}

function labelFor(screen) {
  if (screen === "launcher") return "Start a brew";
  if (screen === "previous") return "Previous brews";
  if (screen === "recipes") return "Which recipe?";
  if (screen === "card") return "la carte";
  return "How much?";
}

function el(tag, props, content) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props || {})) {
    if (value == null) continue;
    if (key === "class") node.className = value;
    else if (key === "onclick") node.addEventListener("click", value);
    else node.setAttribute(key, value);
  }
  const kids = Array.isArray(content) ? content : content == null ? [] : [content];
  for (const kid of kids) node.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
  return node;
}

render();

const { mount } = await import("./review.js");
mount({
  slug: "brew-repeat",
  title: "Répéter un brew",
  root: document.getElementById("review-root"),
  getState,
  setState,
  scenes: [
    { label: "Déjà un brew", patch: { persona: "returning", screen: "launcher", tab: "mine" }, target: "frame" },
    { label: "Premier brew", patch: { persona: "first", screen: "recipes", tab: "pros" }, target: "frame" },
    { label: "Carte", patch: { screen: "card" }, target: "frame" },
    { label: "Lanceur", patch: { persona: "returning", screen: "launcher" }, target: "frame" },
    { label: "Brews passés", patch: { screen: "previous" }, target: "frame" },
    { label: "Recettes", patch: { screen: "recipes" }, target: "frame" },
    { label: "Quantités", patch: { screen: "amounts" }, target: "frame" },
  ],
});
