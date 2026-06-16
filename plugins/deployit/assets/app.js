(function () {
  "use strict";

  // Row tap-to-navigate: clicking anywhere on a row except the install button
  // navigates to the row's data-href.
  document.addEventListener("click", function (e) {
    if (e.target.closest("a.install")) return;
    var li = e.target.closest("li[data-href]");
    if (!li) return;
    var href = li.getAttribute("data-href");
    if (href) window.location.assign(href);
  });

  // Nav-bar Refresh button: POST /_internal/refresh (which git-pulls the shared
  // index server-side), then reload to re-render. One path serves both pages:
  // the product-page GET does not pull on its own, and the listing GET pulls
  // anyway (so the POST is a harmless belt-and-suspenders there). The reload
  // happens whether the POST succeeds or fails, surfacing the latest state.
  var refreshing = false;
  var refreshBtn = document.getElementById("refresh");
  if (refreshBtn) {
    refreshBtn.addEventListener("click", function () {
      if (refreshing) return;
      refreshing = true;
      refreshBtn.disabled = true;
      refreshBtn.classList.add("loading");
      refreshBtn.setAttribute("aria-busy", "true");
      fetch("/deployit/_internal/refresh", { method: "POST" })
        .catch(function () { /* ignore — reload anyway to surface latest state */ })
        .finally(function () { window.location.reload(); });
    });
  }
})();
