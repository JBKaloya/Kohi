const MOMENTS = [
  { id: "rinse", label: "Rinse" },
  { id: "depart", label: "Après le rinçage" },
  { id: "bloom", label: "Bloom, en cours" },
  { id: "due", label: "Temps de l’étape atteint" },
];

const MODES = [
  { id: "auto", label: "Auto", detail: "By time" },
  { id: "manual", label: "Manual", detail: "Tap" },
  { id: "cues", label: "Cues", detail: "Visual" },
];

const FRAMES = {
  rinse: {
    auto: rinseFrame(),
    manual: rinseFrame(),
    cues: rinseFrame(),
  },
  depart: {
    auto: countdownFrame(),
    manual: countdownFrame(),
    cues: {
      clock: "0:00",
      lines: [
        { text: "Bloom", role: "label" },
        { text: "to 45 g", role: "hero" },
        { text: "now 0 g", role: "muted" },
        { text: "bed drops to 2 mm", role: "mark" },
      ],
      ifYouWait: "Le chrono est déjà parti. Pas de 3-2-1.",
      diverges: true,
    },
  },
  bloom: {
    auto: bloomFrame("next: wait"),
    manual: bloomFrame("next: wait"),
    cues: {
      clock: "0:28",
      lines: [
        { text: "Bloom", role: "label" },
        { text: "to 45 g", role: "hero" },
        { text: "now 32 g", role: "muted" },
        { text: "bed drops to 2 mm", role: "mark" },
      ],
      ifYouWait: "L’étape continue. Le repère remplace la ligne « next ».",
      diverges: true,
    },
  },
  due: {
    auto: {
      clock: "0:45",
      lines: [
        { text: "Bloom", role: "label" },
        { text: "to 45 g", role: "hero" },
        { text: "now 45 g", role: "muted" },
        { text: "next: wait", role: "body" },
        { text: "Passe seul dans 3 s", role: "mark" },
      ],
      ifYouWait: "Trois secondes plus tard, l’étape suivante s’affiche.",
      diverges: true,
    },
    manual: {
      clock: "0:45",
      lines: [
        { text: "Bloom", role: "label" },
        { text: "to 45 g", role: "hero" },
        { text: "now 45 g", role: "muted" },
        { text: "next: wait", role: "body" },
      ],
      ifYouWait: "L’écran reste. Seul un tap passe à Wait.",
      diverges: true,
    },
    cues: {
      clock: "0:45",
      lines: [
        { text: "Bloom", role: "label" },
        { text: "to 45 g", role: "hero" },
        { text: "now 45 g", role: "muted" },
        { text: "bed drops to 2 mm", role: "mark" },
      ],
      ifYouWait: "L’écran reste. Le repère dit quand taper, l’horloge ne décide pas.",
      diverges: true,
    },
  },
};

const state = { moment: "due" };
const pills = document.getElementById("moment-pills");
const modes = document.getElementById("modes");

function getState() {
  return structuredClone(state);
}

function setState(patch) {
  Object.assign(state, patch);
  render();
  document.dispatchEvent(new CustomEvent("kohi-review-sync"));
}

function render() {
  pills.replaceChildren(
    ...MOMENTS.map((item) => el("button", {
      type: "button",
      class: state.moment === item.id ? "pill on" : "pill",
      onclick: () => setState({ moment: item.id }),
    }, item.label)),
  );
  modes.replaceChildren();
  for (const mode of MODES) {
    const frame = FRAMES[state.moment][mode.id];
    const column = el("div", {
      class: "stack gap-10",
      "data-anchor": `mode-${mode.id}`,
      "data-anchor-label": mode.label,
    });
    const screen = el("div", { class: "brew-screen" });
    screen.append(el("div", { class: "clock" }, frame.clock));
    for (const line of frame.lines) screen.append(el("div", { class: `role-${line.role}` }, line.text));
    column.append(
      el("strong", {}, `${mode.label} · ${mode.detail}`),
      screen,
      el("p", { class: frame.diverges ? "" : "note" }, frame.ifYouWait),
    );
    modes.append(column);
  }
}

function rinseFrame() {
  return {
    clock: "0:00",
    lines: [
      { text: "Rinse", role: "label" },
      { text: "Rinse · 30 g", role: "hero" },
      { text: "Skip", role: "muted" },
    ],
    ifYouWait: "Rien. Tap sur le bloc, ou Skip. Le rinçage reste hors du chrono.",
    diverges: false,
  };
}

function countdownFrame() {
  return {
    clock: "0:00",
    lines: [{ text: "3", role: "hero" }],
    ifYouWait: "2, puis 1, puis le bloom. Un tap saute le compte.",
    diverges: false,
  };
}

function bloomFrame(footer) {
  return {
    clock: "0:28",
    lines: [
      { text: "Bloom", role: "label" },
      { text: "to 45 g", role: "hero" },
      { text: "now 32 g", role: "muted" },
      { text: footer, role: "body" },
    ],
    ifYouWait: "L’étape continue. Un tap l’enregistre et passe à la suivante.",
    diverges: false,
  };
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
  slug: "advance-modes",
  title: "Timing des recettes",
  root: document.getElementById("review-root"),
  getState,
  setState,
  scenes: MOMENTS.map((item) => ({
    label: item.label,
    patch: { moment: item.id },
    target: "moments",
  })),
});
