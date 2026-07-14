export default function () {
  this.route("weekly-challenges", function () {
    // Before the :slug route so "upcoming" resolves as a static segment.
    this.route("upcoming");
    this.route("show", { path: "/:slug" });
  });
}
