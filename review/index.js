import { CANVASES } from "./catalog.js";

const list = document.getElementById("list");
const counts = new Map();

for (const item of CANVASES) {
  const link = document.createElement("a");
  link.className = "iteration";
  link.href = item.href;
  link.dataset.slug = item.slug;
  const text = document.createElement("div");
  const title = document.createElement("h2");
  title.textContent = item.title;
  const line = document.createElement("p");
  line.textContent = item.line;
  text.append(title, line);
  const count = document.createElement("div");
  count.className = "iteration-count";
  count.dataset.count = item.slug;
  link.append(text, count);
  list.append(link);
}

paintCounts();
loadCounts();

async function loadCounts() {
  const config = window.KOHI_REVIEW_CONFIG;
  if (!config?.url || !config?.key) return;
  try {
    const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2.81.1");
    const client = createClient(config.url, config.key, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const slugs = CANVASES.map((item) => item.slug);
    const { data, error } = await client
      .from("canvas_comments")
      .select("canvas_slug, status, parent_id")
      .in("canvas_slug", slugs);
    if (error) return;
    counts.clear();
    for (const row of data || []) {
      if (row.parent_id || row.status !== "open") continue;
      counts.set(row.canvas_slug, (counts.get(row.canvas_slug) || 0) + 1);
    }
    paintCounts();
  } catch {
    // The list stays usable when the remarks cannot be counted.
  }
}

function paintCounts() {
  for (const item of CANVASES) {
    const node = list.querySelector(`[data-count="${item.slug}"]`);
    const open = counts.get(item.slug) || 0;
    node.textContent = open === 0 ? "" : `${open} remarque${open > 1 ? "s" : ""}`;
  }
}
