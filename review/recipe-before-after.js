const SCREENS = [
  { id: "launcher", label: "Lanceur" },
  { id: "recipe", label: "Écran recette" },
  { id: "empty", label: "Mine vide" },
  { id: "adjust", label: "Repartir d’une recette pro" },
  { id: "brew", label: "Pendant le brew" },
  { id: "after", label: "Après le brew" },
  { id: "archive", label: "Dictée archivée" },
  { id: "home", label: "Accueil · Brews" },
  { id: "detail", label: "Détail d’une recette" },
];

const HEARD = [
  { t: "0:04", what: "Bloom", grams: "40 g", note: "« je swirle »" },
  { t: "0:46", what: "Pour to", grams: "150 g", note: "" },
  { t: "1:31", what: "Pour to", grams: "250 g", note: "« plus lent »" },
  { t: "3:08", what: "Drawdown", grams: "", note: "" },
];

const NOTES = {
  launcher: [
    ["Live remplace Create your recipe", "Le lanceur garde deux choix. Créer une recette se fait désormais depuis Mine, sur l’écran suivant."],
    ["Choose a recipe ne bouge pas", "Il ouvre Mine, comme aujourd’hui."],
  ],
  recipe: [
    ["Titre « Recipe »", "« Which recipe? » posait la question avant même de proposer Live."],
    ["Live en tête, même composant", "C’est l’appel principal par sa place, pas par un encadré : on brew sans recette et on dicte. Il part vers How much?."],
    ["« + New recipe » ouvre Mine", "Même éditeur qu’aujourd’hui : dose, ratio, eau, répartition. Même style qu’Adjust, avec une icône plus : rangé avec les recettes, sans prendre le dessus."],
    ["Adjust remplace Edit recipe", "Visible pour toute recette sélectionnée, pas seulement les miennes."],
  ],
  empty: [
    ["Plus de cul-de-sac", "Aujourd’hui, Mine vide affiche « No recipes yet ». Après, la première ligne propose de créer."],
  ],
  adjust: [
    ["Recette pro : une copie", "Adjust copie la recette dans Mine et ouvre l’éditeur prérempli. L’original des pros reste intact."],
    ["Recette à moi : en place", "L’éditeur modifie la recette et l’enregistre. Aujourd’hui la modification ne vaut que pour ce brew."],
  ],
  brew: [
    ["Avant : une séquence par défaut", "Sans recette, l’app fabrique une séquence minutée et avance toute seule."],
    ["Après : un chrono libre", "Aucune étape à suivre, donc rien à faire avancer. La narration démarre avec le chrono ; Stop termine."],
    ["La dictée ne commande rien", "Elle documente. La transcription se fait après, sur l’appareil."],
  ],
  after: [
    ["Étapes entendues, datées", "L’heure de chaque étape est celle de la phrase. Chaque ligne se corrige ou se supprime."],
    ["Répartition lue sur les grammes", "Bloom compté par défaut, comme dans l’éditeur. L’eau totale vient de la dernière masse dictée si elle manque."],
    ["Rien de lisible", "Une seule étape, la durée du chrono, et la transcription en note."],
    ["Save as recipe", "Ouvre l’éditeur prérempli ; la recette arrive dans Mine et se rejoue en Auto."],
  ],
  archive: [
    ["Avant : l’audio disparaît", "Il est supprimé après la transcription, sauf si Keep voice notes est actif (coupé par défaut)."],
    ["Après : tout est gardé pour apprendre", "Audio, transcription datée, ce que le parser a lu et ce que l’utilisateur a gardé partent dans Supabase. Toutes les dictées de brew, live et après-brew."],
    ["Réglage actif par défaut", "« Share dictations to improve Kohi », coupable. Coupé, rien n’est copié ni envoyé."],
    ["Privé", "Bucket et table en accès par utilisateur. L’analyse passe par la clé service."],
  ],
  home: [
    ["Mêmes onglets que le brew", "« My recipes » et « Recipes from the pros » deviennent « Mine » et « From the pros »."],
    ["« + New recipe » en tête de Mine", "Remplace « Create your recipe », aligné à droite à côté de Filters. Même ligne que dans le brew."],
    ["Pas de doublon", "Sous un onglet, ni titre de section ni étiquette qui répète l’onglet. « Express » reste : il dit d’où vient la recette."],
  ],
  detail: [
    ["Un seul Adjust", "Remplace « Edit » (les miennes) et « Save a copy » (les pros)."],
    ["Même éditeur partout", "Une recette des pros est copiée dans Mine, crédit dans la note. Une des miennes est modifiée sur place, paramètres compris. Le glissement Edit de la liste ouvre le même éditeur."],
  ],
};

const state = { screen: "recipe" };
const pills = document.getElementById("screens");
const before = document.getElementById("before");
const after = document.getElementById("after");
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
  before.replaceChildren(...screen(state.screen, "before"));
  after.replaceChildren(...screen(state.screen, "after"));
  notes.className = "stack gap-14 ba-notes";
  notes.replaceChildren(...NOTES[state.screen].map(([title, body]) =>
    el("div", { class: "stack gap-4" }, [el("h3", {}, title), el("p", { class: "note" }, body)])));
}

function bar(step) {
  return el("div", { class: "brew-bar" }, [
    el("span", { class: "muted" }, "‹"),
    el("div", { class: "ticks" }, [0, 1, 2, 3].map((tick) => el("span", { class: tick <= step ? "tick on" : "tick" }))),
  ]);
}

function screen(id, side) {
  const now = side === "before";
  switch (id) {
    case "launcher":
      return [bar(0), el("div", { class: "brew-title" }, "Huabal"), el("div", { class: "brew-body stack gap-14" }, now ? [
        choice("≡", "Choose a recipe", "Mine or from the pros"),
        choice("+", "Create your recipe", "Dose, ratio, water and how it splits"),
      ] : [
        choice("∿", "Live", "No recipe. Brew and say what you do."),
        choice("≡", "Choose a recipe", "Mine or from the pros"),
      ])];
    case "recipe":
      return [bar(1), el("div", { class: "brew-title" }, now ? "Which recipe?" : "Recipe"), el("div", { class: "brew-body stack gap-14" }, now ? [
        choice("+", "Create your recipe", "Dose, ratio, water and how it splits"),
        el("span", { class: "cat" }, "Choose a recipe"),
        lanes("mine"),
        line("Huabal · V60", "15 g · 1:15 · 93 °C", true),
        line("Batch · Moccamaster", "60 g · 1:16 · 94 °C"),
        el("span", { class: "link-row" }, "Edit recipe"),
      ] : [
        choice("∿", "Live", "No recipe. Brew and say what you do."),
        el("span", { class: "cat" }, "Choose a recipe"),
        lanes("mine"),
        newRow(),
        line("Huabal · V60", "15 g · 1:15 · 93 °C", true),
        line("Batch · Moccamaster", "60 g · 1:16 · 94 °C"),
        el("span", { class: "link-row" }, "Adjust"),
      ])];
    case "empty":
      return [bar(1), el("div", { class: "brew-title" }, now ? "Which recipe?" : "Recipe"), el("div", { class: "brew-body stack gap-14" }, now ? [
        choice("+", "Create your recipe", "Dose, ratio, water and how it splits"),
        el("span", { class: "cat" }, "Choose a recipe"),
        lanes("mine"),
        el("p", { class: "note" }, "No recipes yet."),
      ] : [
        choice("∿", "Live", "No recipe. Brew and say what you do."),
        el("span", { class: "cat" }, "Choose a recipe"),
        lanes("mine"),
        newRow(),
      ])];
    case "adjust":
      if (now) {
        return [bar(1), el("div", { class: "brew-title" }, "Which recipe?"), el("div", { class: "brew-body stack gap-14" }, [
          el("span", { class: "cat" }, "Choose a recipe"),
          lanes("pros"),
          line("Tetsu Kasuya · 4:6", "20 g · 1:15 · 92 °C", true),
          line("Hoffmann · Better 1 cup", "15 g · 1:16.7 · 100 °C"),
          el("p", { class: "note" }, "Pas d’Edit recipe sur une recette des pros. Pour l’ajuster, il faut la recréer à la main."),
        ])];
      }
      return [el("div", { class: "brew-title" }, "Create your recipe"), el("div", { class: "brew-body stack gap-14" }, [
        el("p", { class: "note" }, "Copied to Mine from Tetsu Kasuya · 4:6"),
        el("span", { class: "cat" }, "Totals"),
        el("div", { class: "between" }, [el("span", {}, "Dose 20 g"), el("span", {}, "Ratio 1:15"), el("span", {}, "Water 300 g")]),
        el("span", { class: "cat" }, "Split"),
        el("div", { class: "between" }, [el("span", {}, "Services 5"), el("span", { class: "muted" }, "Count the bloom ●")]),
        el("div", { class: "split-bar" }, [20, 20, 20, 20, 20].map((part) => el("span", { style: `width:${part}%` }))),
        el("p", { class: "note" }, "20 % · 20 % · 20 % · 20 % · the rest"),
      ]), el("div", { class: "brew-foot" }, el("div", { class: "capsule" }, "Save to Mine"))];
    case "brew":
      if (now) {
        return [bar(3), el("div", { class: "brew-body stack gap-14", style: "padding-top:48px" }, [
          el("span", { class: "cat" }, "Step 2 of 4 · Pour"),
          el("div", { class: "live-clock" }, "1:12"),
          el("p", { class: "note" }, "Pour to 150 g · next at 1:30"),
          el("div", { class: "pill-rec" }, [el("span", { class: "dot" }), el("span", {}, "Recording — tap to stop"), wave()]),
        ]), el("div", { class: "brew-foot" }, el("div", { class: "link-row", style: "text-align:center" }, "Stop"))];
      }
      return [bar(3), el("div", { class: "brew-body stack gap-14", style: "padding-top:48px" }, [
        el("span", { class: "cat" }, "Live"),
        el("div", { class: "live-clock" }, "1:12"),
        el("p", { class: "note" }, "No steps to follow. Say what you do."),
        el("div", { class: "pill-rec" }, [el("span", { class: "dot" }), el("span", {}, "Recording — tap to stop"), wave()]),
      ]), el("div", { class: "brew-foot" }, el("div", { class: "link-row", style: "text-align:center" }, "Stop"))];
    case "after":
      if (now) {
        return [el("div", { class: "brew-title" }, "It's done"), el("div", { class: "brew-body stack gap-14" }, [
          el("span", { class: "cat" }, "Notes"),
          el("p", { class: "note" }, "Bloom 40 grammes, je swirle. Je verse jusqu’à 150. Deuxième versement à 250, plus lent. Ça draine."),
          el("span", { class: "cat" }, "Steps"),
          el("p", { class: "note" }, "Celles du chrono, avec les masses dictées reportées quand elles tombent sur une étape."),
        ]), el("div", { class: "brew-foot" }, el("div", { class: "capsule" }, "Save"))];
      }
      return [el("div", { class: "brew-title" }, "It's done"), el("div", { class: "brew-body stack gap-14" }, [
        el("span", { class: "cat" }, "Steps heard"),
        el("div", {}, HEARD.map(heard)),
        el("span", { class: "cat" }, "Split · bloom counted"),
        el("div", { class: "split-bar" }, [16, 44, 40].map((part) => el("span", { style: `width:${part}%` }))),
        el("p", { class: "note" }, "Bloom 16 % · Pour 44 % · Pour 40 %"),
      ]), el("div", { class: "brew-foot stack gap-8" }, [
        el("div", { class: "capsule" }, "Save as recipe"),
        el("div", { class: "link-row", style: "text-align:center" }, "Save the brew only"),
      ])];
    case "archive":
      return [el("div", { class: "brew-title" }, "Settings"), el("div", { class: "brew-body stack gap-14" }, [
        el("span", { class: "cat" }, "Dictation"),
        toggleRow("Keep voice notes", false),
        now ? null : toggleRow("Share dictations to improve Kohi", true),
        el("span", { class: "cat" }, "What happens to a dictation"),
        now ? el("div", { class: "flow" }, [
          el("div", {}, [el("strong", {}, "m4a"), " sur l’appareil"]),
          el("div", {}, "↓ transcription sur l’appareil"),
          el("div", {}, [el("strong", {}, "texte"), " dans les notes du brew"]),
          el("div", { class: "gone" }, "audio supprimé"),
          el("div", {}, "Supabase : rien"),
        ]) : el("div", { class: "flow" }, [
          el("div", {}, [el("strong", {}, "m4a"), " sur l’appareil"]),
          el("div", {}, "↓ transcription sur l’appareil"),
          el("div", {}, [el("strong", {}, "texte"), " dans les notes du brew"]),
          el("div", {}, "↓ file d’envoi, hors ligne compris"),
          el("div", {}, [el("strong", {}, "bucket dictations"), " : l’audio"]),
          el("div", {}, [el("strong", {}, "table dictations"), " : transcription datée, lecture du parser, étapes gardées, contexte, build"]),
          el("div", {}, "↓ puis audio local supprimé"),
        ]),
      ])];
    case "home":
      return [el("div", { class: "brew-title" }, "Kohi"), el("div", { class: "brew-body stack gap-14" }, [
        el("div", { class: "row gap-14" }, now
          ? [el("span", { class: "lane" }, "All"), el("span", { class: "lane on" }, "My recipes"), el("span", { class: "lane" }, "Recipes from the pros")]
          : [el("span", { class: "lane" }, "All"), el("span", { class: "lane on" }, "Mine"), el("span", { class: "lane" }, "From the pros")]),
        el("div", { class: "between" }, now
          ? [el("span", { class: "cat" }, "Filters"), el("span", { class: "cat" }, "Create your recipe")]
          : [el("span", { class: "cat" }, "Filters"), el("span", {})]),
        now ? null : newRow(),
        line("Kenya Tekangu · French Press", now ? "100 g · 1:2.5 · Mine" : "100 g · 1:2.5"),
        line("Filter · 26 Sep", "30 g · 1:16.7 · Express"),
      ])];
    case "detail":
      return [el("div", { class: "brew-title" }, "V60 « 4:6 »"), el("div", { class: "brew-body stack gap-14" }, [
        el("span", { class: "cat" }, "Parameters"),
        el("p", { class: "note" }, "20 g · 1:15 · 92 °C"),
        el("span", { class: "cat" }, "Steps"),
        el("p", { class: "note" }, "5 pours, 60 g each"),
        el("span", { class: "link-row" }, now ? "Save a copy" : "Adjust"),
        now ? el("p", { class: "note" }, "Sur une des miennes : « Edit », qui ouvre un autre éditeur.") : null,
      ]), el("div", { class: "brew-foot" }, el("div", { class: "capsule" }, "Brew"))];
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

function lanes(on) {
  return el("div", { class: "row gap-14" }, [
    el("span", { class: on === "mine" ? "lane on" : "lane" }, "Mine"),
    el("span", { class: on === "pros" ? "lane on" : "lane" }, "From the pros"),
  ]);
}

function newRow() {
  return el("span", { class: "link-row new-link" }, "+  New recipe");
}

function line(title, detail, selected = false) {
  return el("div", { class: selected ? "brew-line on" : "brew-line" }, [el("strong", {}, title), el("div", { class: "mono muted" }, detail)]);
}

function heard(item) {
  return el("div", { class: "heard" }, [
    el("span", { class: "t" }, item.t),
    el("span", {}, item.what),
    el("span", {}, item.grams),
    item.note ? el("span", { class: "n" }, item.note) : null,
  ]);
}

function toggleRow(label, on) {
  return el("div", { class: "toggle-row" }, [el("span", {}, label), el("span", { class: on ? "toggle on" : "toggle" })]);
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
  slug: "recipe-before-after",
  title: "Recipe et Live, avant / après",
  root: document.getElementById("review-root"),
  getState,
  setState,
  scenes: SCREENS.map((item) => ({
    label: item.label,
    patch: { screen: item.id },
    target: "avant",
  })),
});
