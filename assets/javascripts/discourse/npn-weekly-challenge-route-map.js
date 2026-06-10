export default function () {
  this.route("weekly-challenges", function () {
    this.route("show", { path: "/:slug" });
  });
}
