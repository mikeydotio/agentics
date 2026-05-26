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

  // Pull-to-refresh: when scrollY is 0 and the user drags down past
  // PTR_THRESHOLD pixels, POST /_internal/refresh and reload on release.
  var PTR_THRESHOLD = 64;
  var PTR_MAX = 96;
  var ptr = document.getElementById("ptr");
  if (!ptr) return;

  var startY = null;
  var pulling = false;
  var armed = false;
  var refreshing = false;

  function setLabel(text) { ptr.textContent = text; }
  function setHeight(px) { ptr.style.height = px + "px"; }

  function reset() {
    pulling = false;
    armed = false;
    startY = null;
    ptr.classList.remove("armed");
    ptr.style.transition = "height 180ms ease";
    setHeight(0);
  }

  document.addEventListener("touchstart", function (e) {
    if (refreshing) return;
    if (window.scrollY > 0) return;
    if (e.touches.length !== 1) return;
    startY = e.touches[0].clientY;
    pulling = true;
    ptr.style.transition = "none";
  }, { passive: true });

  document.addEventListener("touchmove", function (e) {
    if (!pulling || refreshing || startY == null) return;
    var delta = e.touches[0].clientY - startY;
    if (delta <= 0) { setHeight(0); return; }
    var shown = Math.min(delta * 0.5, PTR_MAX);
    setHeight(shown);
    if (shown >= PTR_THRESHOLD) {
      if (!armed) { armed = true; ptr.classList.add("armed"); setLabel("Release to refresh"); }
    } else {
      if (armed) { armed = false; ptr.classList.remove("armed"); }
      setLabel("Pull to refresh");
    }
  }, { passive: true });

  function finish() {
    if (!pulling || refreshing) { reset(); return; }
    if (!armed) { reset(); return; }
    refreshing = true;
    ptr.style.transition = "height 180ms ease";
    setHeight(PTR_THRESHOLD);
    setLabel("Refreshing…");
    fetch("/deployit/_internal/refresh", { method: "POST" })
      .catch(function () { /* ignore — reload anyway to surface latest server state */ })
      .then(function () { window.location.reload(); });
  }

  document.addEventListener("touchend", finish, { passive: true });
  document.addEventListener("touchcancel", function () { reset(); }, { passive: true });
})();
