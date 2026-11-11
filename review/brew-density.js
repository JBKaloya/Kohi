const { mount } = await import("./review.js");
mount({
  slug: "brew-density",
  title: "Densité du parcours brew",
  root: document.getElementById("review-root"),
  getState: () => ({}),
  setState: () => {},
  scenes: [],
});
