/**
 * Shared review layer for hosted Kohi canvases.
 *
 * A page renders its own prototype, then calls mount() with the slug and the
 * prototype state. Pins, the remote, and Supabase stay here, so the next
 * canvas only has to supply its screens.
 *
 *   import { mount } from "./review.js";
 *   mount({
 *     slug: "tastings-before-after",
 *     title: "Tastings : avant / après",
 *     root,
 *     getState,
 *     setState,
 *     scenes: [{ label: "Liste", patch: { step: "list" } }],
 *   });
 *
 * Config comes from window.KOHI_REVIEW_CONFIG in ./config.js
 * (url + publishable key). Comments are rows in public.canvas_comments.
 */

const COLUMNS =
  "id, canvas_slug, parent_id, author_name, body, anchor, pin_x, pin_y, view_state, status, created_at";

const AUTHORS = ["Jean-Baptiste", "Timour"];

export function mount(options) {
  const slug = options.slug;
  const root = options.root;
  if (!slug || !root) throw new Error("Kohi review needs a slug and a root");

  const authorKey = remember("kohi-review-key", crypto.randomUUID());
  const storedAuthor = remember("kohi-review-author", AUTHORS[0]);
  let author = AUTHORS.includes(storedAuthor) ? storedAuthor : AUTHORS[0];
  let customName = AUTHORS.includes(storedAuthor) ? "" : storedAuthor;
  let comments = [];
  let armed = false;
  let activeId = null;
  let draft = null;
  let draftBody = "";
  let replyBody = "";
  let client = null;
  let statusLine = "Connexion…";
  let statusError = false;
  let saving = false;

  document.body.classList.add("review-has-remote");
  const chrome = document.createElement("aside");
  chrome.className = "review-remote";
  chrome.dataset.reviewChrome = "true";
  chrome.setAttribute("aria-label", "Télécommande de revue");
  document.body.appendChild(chrome);

  root.addEventListener("click", onRootClick, true);
  document.addEventListener("kohi-review-sync", drawPins);
  document.addEventListener("keydown", onKey);

  renderRemote();
  connect();

  function onRootClick(event) {
    if (!armed) return;
    if (event.target.closest("[data-review-chrome]")) return;
    event.preventDefault();
    event.stopPropagation();
    const anchorEl = event.target.closest("[data-anchor]") || root;
    const rect = anchorEl.getBoundingClientRect();
    const width = rect.width || 1;
    const height = rect.height || 1;
    draft = {
      anchor: anchorEl.dataset.anchor || "page",
      x: clamp(((event.clientX - rect.left) / width) * 100),
      y: clamp(((event.clientY - rect.top) / height) * 100),
      state: structuredClone(options.getState()),
    };
    draftBody = "";
    armed = false;
    activeId = null;
    drawPins();
    renderRemote();
    queueMicrotask(() => chrome.querySelector("[data-focus='draft']")?.focus());
  }

  function onKey(event) {
    const typing = event.target.closest("input, textarea");
    if (event.key === "Escape") {
      armed = false;
      draft = null;
      drawPins();
      renderRemote();
    } else if ((event.key === "c" || event.key === "C") && !typing && !event.metaKey && !event.ctrlKey) {
      armed = !armed;
      drawPins();
      renderRemote();
    }
  }

  async function connect() {
    const config = window.KOHI_REVIEW_CONFIG;
    if (!config?.url || !config?.key) {
      fail("Ajoute review/config.js avec la clé publiable pour enregistrer les remarques.");
      return;
    }
    try {
      const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2.81.1");
      client = createClient(config.url, config.key, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const inserted = await client.from("canvas_reviews").insert({ slug, title: options.title || slug });
      const duplicate = inserted.error && (inserted.error.code === "23505" || /duplicate key/i.test(inserted.error.message || ""));
      if (inserted.error && !duplicate) throw inserted.error;
      if (duplicate) {
        const updated = await client.from("canvas_reviews").update({ title: options.title || slug }).eq("slug", slug);
        if (updated.error) throw updated.error;
      }
      await load();
      client
        .channel("review:" + slug)
        .on(
          "postgres_changes",
          { event: "*", schema: "public", table: "canvas_comments", filter: `canvas_slug=eq.${slug}` },
          () => load(),
        )
        .subscribe();
      setInterval(() => {
        if (document.visibilityState === "visible") load();
      }, 15000);
    } catch (error) {
      fail(error.message || "La revue n’a pas pu joindre Supabase.");
    }
  }

  async function load() {
    if (!client) return;
    const { data, error } = await client
      .from("canvas_comments")
      .select(COLUMNS)
      .eq("canvas_slug", slug)
      .order("created_at", { ascending: true });
    if (error) {
      fail(error.message);
      return;
    }
    comments = data || [];
    const open = comments.filter((comment) => !comment.parent_id && comment.status === "open").length;
    statusError = false;
    statusLine = open === 0 ? "Aucune remarque ouverte." : `${open} remarque${open > 1 ? "s" : ""} ouverte${open > 1 ? "s" : ""}.`;
    drawPins();
    renderRemote();
  }

  async function saveDraft() {
    const body = draftBody.trim();
    if (!draft || !body || saving || !client) return;
    saving = true;
    renderRemote();
    const { error } = await client
      .from("canvas_comments")
      .insert({
        canvas_slug: slug,
        author_name: activeAuthor(),
        author_key: authorKey,
        body: body.slice(0, 2000),
        anchor: draft.anchor,
        pin_x: draft.x,
        pin_y: draft.y,
        view_state: draft.state || {},
      })
      .select(COLUMNS);
    saving = false;
    if (error) {
      fail(error.message);
      return;
    }
    draft = null;
    draftBody = "";
    await load();
  }

  async function saveReply(parentId) {
    const body = replyBody.trim();
    if (!body || saving || !client) return;
    saving = true;
    renderRemote();
    const { error } = await client
      .from("canvas_comments")
      .insert({
        canvas_slug: slug,
        parent_id: parentId,
        author_name: activeAuthor(),
        author_key: authorKey,
        body: body.slice(0, 2000),
      })
      .select(COLUMNS);
    saving = false;
    if (error) {
      fail(error.message);
      return;
    }
    replyBody = "";
    await load();
  }

  async function setStatus(id, status) {
    const { error } = await client.from("canvas_comments").update({ status }).eq("id", id);
    if (error) {
      fail(error.message);
      return;
    }
    await load();
  }

  function focusComment(comment) {
    activeId = comment.id;
    draft = null;
    armed = false;
    const view = comment.view_state;
    if (view && typeof view === "object" && Object.keys(view).length > 0) {
      options.setState(view);
    }
    drawPins();
    renderRemote();
    requestAnimationFrame(() => {
      root.querySelector(`[data-pin="${CSS.escape(comment.id)}"]`)?.scrollIntoView({
        behavior: "smooth",
        block: "center",
      });
    });
  }

  function drawPins() {
    root.classList.toggle("is-armed", armed);
    root.querySelectorAll(".review-pin").forEach((node) => node.remove());
    let number = 0;
    for (const comment of comments) {
      if (comment.parent_id || comment.pin_x == null || comment.pin_y == null) continue;
      number += 1;
      const host = anchorElement(comment.anchor);
      const pin = document.createElement("button");
      pin.type = "button";
      pin.className = "review-pin";
      pin.dataset.reviewChrome = "true";
      pin.dataset.pin = comment.id;
      pin.style.left = `${comment.pin_x}%`;
      pin.style.top = `${comment.pin_y}%`;
      pin.textContent = String(number);
      pin.setAttribute("aria-label", `Remarque ${number} de ${comment.author_name}`);
      if (comment.status === "resolved") pin.classList.add("is-resolved");
      if (comment.id === activeId) pin.classList.add("is-active");
      pin.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        focusComment(comment);
      });
      host.appendChild(pin);
    }
    if (draft && draft.x != null) {
      const host = anchorElement(draft.anchor);
      const pin = document.createElement("button");
      pin.type = "button";
      pin.className = "review-pin is-draft";
      pin.dataset.reviewChrome = "true";
      pin.style.left = `${draft.x}%`;
      pin.style.top = `${draft.y}%`;
      pin.textContent = "+";
      pin.tabIndex = -1;
      host.appendChild(pin);
    }
  }

  function renderRemote() {
    const focusKey = document.activeElement?.dataset?.focus;
    const caret = document.activeElement?.selectionStart;
    chrome.replaceChildren();

    chrome.append(
      el("div", { class: "review-kicker" }, "Télécommande"),
      el("h2", { class: "review-title" }, options.title || slug),
      el("p", { class: statusError ? "review-status is-error" : "review-status" }, statusLine),
    );

    const who = el("div", { class: "review-block" });
    who.append(el("p", { class: "review-label" }, "Qui commente"));
    const names = el("div", { class: "review-names" });
    const shown = activeAuthor();
    for (const name of AUTHORS) {
      names.append(
        el(
          "button",
          {
            type: "button",
            class: name === shown && !customName.trim() ? "review-choice is-on" : "review-choice",
            onclick: () => {
              author = name;
              customName = "";
              localStorage.setItem("kohi-review-author", name);
              renderRemote();
            },
          },
          name,
        ),
      );
    }
    who.append(names);
    const nameField = el("input", {
      class: "review-name-field",
      "data-focus": "author",
      placeholder: "Autre nom",
      maxlength: "40",
      "aria-label": "Autre nom",
      oninput: (event) => {
        customName = event.target.value;
        localStorage.setItem("kohi-review-author", event.target.value.trim() || author);
      },
    });
    nameField.value = customName;
    who.append(nameField);
    chrome.append(who);

    if (options.scenes?.length) {
      const scenes = el("div", { class: "review-block" });
      scenes.append(el("p", { class: "review-label" }, "Écran"));
      const row = el("div", { class: "review-scenes" });
      const current = options.getState();
      for (const scene of options.scenes) {
        const on = Object.entries(scene.patch).every(([key, value]) => current[key] === value);
        row.append(
          el(
            "button",
            {
              type: "button",
              class: on ? "review-choice is-on" : "review-choice",
              onclick: () => {
                options.setState(scene.patch);
                if (scene.target) {
                  document.getElementById(scene.target)?.scrollIntoView({ behavior: "smooth", block: "start" });
                }
              },
            },
            scene.label,
          ),
        );
      }
      scenes.append(row);
      chrome.append(scenes);
    }

    const tools = el("div", { class: "review-block" });
    tools.append(el("p", { class: "review-label" }, "Remarques"));
    tools.append(
      el(
        "button",
        {
          type: "button",
          class: armed ? "review-choice review-arm is-on" : "review-choice review-arm",
          onclick: () => {
            armed = !armed;
            drawPins();
            renderRemote();
          },
        },
        armed ? "Clique sur la maquette" : "Commenter",
      ),
      el("p", { class: "review-hint" }, "Le commentaire retient l’écran en cours. Touche C pour armer, Échap pour annuler."),
      el(
        "button",
        {
          type: "button",
          class: "review-text-button",
          style: "margin-top:8px",
          onclick: () => {
            draft = { anchor: "page", x: null, y: null, state: structuredClone(options.getState()) };
            draftBody = "";
            armed = false;
            activeId = null;
            drawPins();
            renderRemote();
            queueMicrotask(() => chrome.querySelector("[data-focus='draft']")?.focus());
          },
        },
        "Remarque sur l’ensemble",
      ),
    );
    chrome.append(tools);

    if (draft) {
      const box = el("div", { class: "review-block review-compose" });
      box.append(
        el("p", { class: "review-label" }, anchorLabel(draft.anchor)),
        el("textarea", {
          "data-focus": "draft",
          maxlength: "2000",
          placeholder: "Ce qui coince, ou ce qui est juste.",
          oninput: (event) => {
            draftBody = event.target.value;
          },
        }),
      );
      const area = box.querySelector("textarea");
      area.value = draftBody;
      const actions = el("div", { class: "review-compose-actions" });
      actions.append(
        el(
          "button",
          {
            type: "button",
            class: "review-send",
            disabled: saving || !client ? "true" : null,
            onclick: saveDraft,
          },
          saving ? "Envoi…" : "Enregistrer",
        ),
        el(
          "button",
          {
            type: "button",
            class: "review-text-button",
            onclick: () => {
              draft = null;
              draftBody = "";
              drawPins();
              renderRemote();
            },
          },
          "Annuler",
        ),
      );
      box.append(actions);
      chrome.append(box);
    }

    const list = el("div", { class: "review-block" });
    const roots = comments.filter((comment) => !comment.parent_id);
    if (roots.length === 0) {
      list.append(el("p", { class: "review-hint" }, "Les épingles de Timour et les tiennes apparaîtront ici."));
    }
    let number = 0;
    for (const comment of roots) {
      const numbered = comment.pin_x != null;
      if (numbered) number += 1;
      const open = comment.id === activeId;
      const button = el("button", {
        type: "button",
        class: open ? "review-thread is-open" : "review-thread",
        onclick: () => focusComment(comment),
      });
      const top = el("div", { class: "review-thread-top" });
      top.append(
        el("span", { class: "review-thread-no" }, numbered ? String(number) : "·"),
        el("span", { class: "review-thread-meta" }, `${comment.author_name} · ${anchorLabel(comment.anchor)}`),
      );
      button.append(top, el("p", { class: "review-thread-body" }, comment.body));
      if (comment.status === "resolved") {
        button.append(el("p", { class: "review-thread-meta" }, "Résolue"));
      }
      list.append(button);
      if (!open) continue;
      const detail = el("div", { class: "review-detail" });
      for (const reply of comments.filter((item) => item.parent_id === comment.id)) {
        const block = el("div", { class: "review-reply" });
        block.append(
          el("div", { class: "review-reply-meta" }, reply.author_name),
          el("p", { class: "review-reply-body" }, reply.body),
        );
        detail.append(block);
      }
      const replyBox = el("textarea", {
        "data-focus": "reply",
        maxlength: "2000",
        placeholder: "Répondre",
        oninput: (event) => {
          replyBody = event.target.value;
        },
      });
      replyBox.value = replyBody;
      const actions = el("div", { class: "review-detail-actions" });
      actions.append(
        el(
          "button",
          { type: "button", class: "review-send", disabled: saving || !client ? "true" : null, onclick: () => saveReply(comment.id) },
          "Répondre",
        ),
        el(
          "button",
          {
            type: "button",
            class: "review-text-button",
            onclick: () => setStatus(comment.id, comment.status === "resolved" ? "open" : "resolved"),
          },
          comment.status === "resolved" ? "Rouvrir" : "Résoudre",
        ),
      );
      detail.append(replyBox, actions);
      list.append(detail);
    }
    chrome.append(list);

    if (focusKey) {
      const next = chrome.querySelector(`[data-focus="${focusKey}"]`);
      if (next) {
        next.focus();
        if (caret != null && next.setSelectionRange) next.setSelectionRange(caret, caret);
      }
    }
  }

  function activeAuthor() {
    return (customName.trim() || author).slice(0, 40);
  }

  function anchorElement(id) {
    if (id && id !== "page") {
      const found = root.querySelector(`[data-anchor="${CSS.escape(id)}"]`);
      if (found) return found;
    }
    return root;
  }

  function anchorLabel(id) {
    if (!id || id === "page") return "Ensemble";
    return anchorElement(id).dataset.anchorLabel || id;
  }

  function fail(message) {
    statusError = true;
    statusLine = message;
    renderRemote();
  }
}

function remember(key, value) {
  const existing = localStorage.getItem(key);
  if (existing) return existing;
  localStorage.setItem(key, value);
  return value;
}

function clamp(value) {
  return Math.min(100, Math.max(0, value));
}

function el(tag, props, text) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props || {})) {
    if (value == null) continue;
    if (key === "class") node.className = value;
    else if (key === "onclick" || key === "oninput") node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value);
  }
  if (text != null) node.textContent = text;
  return node;
}
