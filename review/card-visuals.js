const { mount } = await import("./review.js");
mount({
  slug: "card-visuals",
  title: "Visuels des fiches",
  root: document.getElementById("review-root"),
  getState: () => ({}),
  setState: () => {},
  scenes: [],
});
