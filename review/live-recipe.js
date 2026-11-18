const SCREENS = [
  { id: "scope", label: "Recipe" },
  { id: "dial", label: "How much?" },
  { id: "live", label: "Live" },
  { id: "after", label: "Steps heard" },
  { id: "save", label: "Save as recipe" },
];

const HEARD = [
  { t: "0:04", what: "Bloom", grams: "40 g", note: "« je swirle »" },
  { t: "0:46", what: "Pour to", grams: "150 g", note: "" },
  { t: "1:31", what: "Pour to", grams: "250 g", note: "« plus lent »" },
  { t: "3:08", what: "Drawdown", grams: "", note: "" },
];

const NOTES = {
  scope: [
    "Codé. L’écran s’appelle Recipe. Live est la première entrée, avec la même ligne que les autres choix, sans cadre.",
    "New recipe est la première ligne de Mine, même quand Mine est vide : icône plus, même style de texte qu’Adjust.",
    "Adjust, sous la liste : une recette des pros est copiée dans Mine puis ouverte dans l’éditeur ; une des miennes est modifiée sur place.",
  ],
  dial: [
    "Codé. La ligne de source dit « Live · V60 ». Dose et eau facultatives.",
    "Le kit et la ligne Before you pour restent.",
  ],
  live: [
    "Codé. Un chrono libre : aucune étape imposée, donc rien à faire avancer.",
    "La dictée démarre avec le chrono ; on peut la couper et la relancer. Micro refusé : le chrono tourne quand même.",
    "Ce qui est dit n’apparaît pas ici en direct : la transcription se fait après, sur l’appareil.",
  ],
  after: [
    "Codé. Les étapes lues dans la dictée, avec l’heure de la phrase. Chaque ligne se supprime ; Edit ouvre l’éditeur.",
    "La répartition se lit sur les grammes dictés, bloom compté selon le réglage de l’éditeur.",
    "Rien d’entendu : une seule étape, la durée totale, et la transcription reste dans les notes.",
    "Les étapes gardées sont aussi renvoyées à l’archive des dictées, à côté de ce qui a été entendu.",
  ],
  save: [
    "Codé. Save as recipe ouvre l’éditeur d’étapes prérempli, avec ratio et répartition.",
    "La recette arrive dans Mine et le brew y est rattaché. Elle se rejoue ensuite en Auto.",
  ],
};

const state = { screen: "live" };
const pills = document.getElementById("screens");
const frame = document.getElementById("frame");
const notes = document.getElementById("notes");

function getState() {
  return structuredClone(state);
}

function setState(patch) {
  Object.assign(state, patch);
  render();
  document.dispatchEvent(new CustomEvent("kohi-review-sync"));
}

function render() {
  pills.replaceChildren(...SCREENS.map((item) => el("button", {
    type: "button",
    class: state.screen === item.id ? "pill on" : "pill",
    onclick: () => setState({ screen: item.id }),
  }, item.label)));
  frame.replaceChildren(...screen(state.screen));
  notes.replaceChildren(...NOTES[state.screen].map((line) => el("p", {}, line)));
}

function screen(id) {
  const index = SCREENS.findIndex((item) => item.id === id);
  const bar = el("div", { class: "brew-bar" }, [
    el("span", { class: "muted" }, "‹"),
    el("div", { class: "ticks" }, [0, 1, 2, 3].map((tick) => el("span", { class: tick <= Math.min(index, 3) ? "tick on" : "tick" }))),
  ]);
  switch (id) {
    case "scope":
      return [bar, el("div", { class: "brew-title" }, "Recipe"), el("div", { class: "brew-body stack gap-14" }, [
        choice("〰", "Live", "No recipe. Brew and say what you do."),
        el("span", { class: "cat" }, "Choose a recipe"),
        el("div", { class: "row gap-14" }, [el("span", { class: "lane on" }, "Mine"), el("span", { class: "lane" }, "From the pros")]),
        el("span", { class: "cat" }, "+ New recipe"),
        line("Huabal · V60", "15 g · 1:15 · 93 °C"),
        line("Batch · Moccamaster", "60 g · 1:16 · 94 °C"),
        el("span", { class: "cat" }, "Adjust"),
      ])];
    case "dial":
      return [bar, el("div", { class: "brew-title" }, "How much?"), el("div", { class: "brew-body stack gap-14" }, [
        el("p", { class: "note" }, "Live · V60"),
        el("div", { class: "between" }, [el("span", {}, "Dose 15 g"), el("span", { class: "muted" }, "1:—"), el("span", { class: "muted" }, "Water —")]),
        el("span", { class: "cat" }, "Before you pour"),
        el("p", { class: "note" }, "Rinse the paper · Preheat the server · Tare the scale"),
      ]), el("div", { class: "brew-foot" }, el("div", { class: "capsule" }, "Swipe up to brew"))];
    case "live":
      return [bar, el("div", { class: "brew-body stack gap-14", style: "padding-top:48px" }, [
        el("span", { class: "cat" }, "Live"),
        el("div", { class: "live-clock" }, "1:12"),
        el("p", { class: "note" }, "No steps to follow. Say what you do."),
        el("div", { class: "pill-rec" }, [el("span", { class: "dot" }), el("span", {}, "Recording — tap to stop"), wave()]),
      ]), el("div", { class: "brew-foot" }, el("div", { class: "link-row", style: "text-align:center" }, "Stop"))];
    case "after":
      return [bar, el("div", { class: "brew-title" }, "It's done"), el("div", { class: "brew-body stack gap-14" }, [
        choice("+", "Save as recipe", "Keep these steps for next time"),
        el("div", { class: "between" }, [el("span", { class: "cat" }, "Steps heard"), el("span", { class: "cat" }, "Edit")]),
        el("div", {}, HEARD.map(heard)),
        el("span", { class: "cat" }, "Split · bloom counted"),
        el("div", { class: "split-bar" }, [16, 44, 40].map((part) => el("span", { style: `width:${part}%` }))),
        el("p", { class: "note" }, "Bloom 16 % · Pour 44 % · Pour 40 %"),
      ]), el("div", { class: "brew-foot" }, el("div", { class: "capsule" }, "Save"))];
    case "save":
      return [el("div", { class: "brew-title" }, "Create your recipe"), el("div", { class: "brew-body stack gap-14" }, [
        el("span", { class: "cat" }, "Totals"),
        el("div", { class: "between" }, [el("span", {}, "Dose 15 g"), el("span", {}, "Water 250 g"), el("span", { class: "muted" }, "1:16.7")]),
        el("span", { class: "cat" }, "Split"),
        el("div", { class: "between" }, [el("span", {}, "Services 3"), el("span", { class: "muted" }, "Count the bloom ●")]),
        el("div", { class: "between" }, [el("span", {}, "1 · Bloom"), el("span", {}, "16 % · 40 g")]),
        el("div", { class: "between" }, [el("span", {}, "2 · Pour"), el("span", {}, "44 % · 110 g")]),
        el("div", { class: "between" }, [el("span", {}, "3 · Pour"), el("span", { class: "muted" }, "40 % · 100 g · the rest")]),
        el("span", { class: "cat" }, "Steps"),
        el("div", {}, HEARD.map(heard)),
      ])];
    default:
      return [];
  }
}

function choice(mark, title, detail) {
  return el("div", { class: "choice" }, [
    el("span", { class: "choice-mark" }, mark),
    el("div", { class: "stack gap-2" }, [el("strong", {}, title), el("span", { class: "muted" }, detail)]),
  ]);
}

function line(title, detail) {
  return el("div", { class: "brew-line" }, [el("strong", {}, title), el("div", { class: "mono muted" }, detail)]);
}

function heard(item) {
  return el("div", { class: "heard" }, [
    el("span", { class: "t" }, item.t),
    el("span", {}, item.what),
    el("span", {}, item.grams),
    item.note ? el("span", { class: "n" }, item.note) : null,
  ]);
}

function wave() {
  return el("span", { class: "wave" }, [6, 12, 9, 15, 7, 11, 5, 13].map((h) => el("span", { style: `height:${h}px` })));
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
  for (const kid of kids) {
    if (kid == null) continue;
    node.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
  }
  return node;
}

render();

const { mount } = await import("./review.js");
mount({
  slug: "live-recipe",
  title: "Recipe, Live et archive des dictées",
  root: document.getElementById("review-root"),
  getState,
  setState,
  scenes: SCREENS.map((item) => ({
    label: item.label,
    patch: { screen: item.id },
    target: "parcours",
  })),
});
