(function () {
  "use strict";

  // Swipe-to-swap state. A row (li[data-delete]) swaps its Install pill for the
  // Delete pill by translating its .action-track left by one .actions-slot width
  // when its .swipe-content is dragged left (right-to-left swipe); swiping back
  // right restores Install. Only local builds carry data-delete, so only they are
  // swipeable. The slot width is measured from the DOM each drag, so the pill
  // width lives in app.css alone — no constant to keep in sync.
  var SLOP = 8;     // movement under this is a tap, not a swipe
  var openRow = null;       // the currently-open <li>, or null
  var suppressClick = false; // set after a swipe so the trailing click is ignored
  var drag = null;

  function trackOf(li) { return li.querySelector(".action-track"); }
  function slotWidth(li) {
    var slot = li.querySelector(".actions-slot");
    return slot ? slot.getBoundingClientRect().width : 0;
  }
  function closeRow(li) {
    var t = trackOf(li);
    if (t) t.style.transform = "";
  }
  function openRowEl(li) {
    var t = trackOf(li);
    if (t) t.style.transform = "translateX(-" + slotWidth(li) + "px)";
  }

  document.addEventListener("pointerdown", function (e) {
    suppressClick = false; // clear any stale flag from a swipe that fired no click
    if (!e.isPrimary) return;
    var surface = e.target.closest(".swipe-content");
    var li = surface && surface.closest("li[data-delete]");
    if (!li) return;
    var track = trackOf(li);
    if (!track) return;
    if (openRow && openRow !== li) { closeRow(openRow); openRow = null; }
    var width = slotWidth(li);
    drag = {
      li: li, surface: surface, track: track, width: width, pointerId: e.pointerId,
      startX: e.clientX, startY: e.clientY,
      base: (openRow === li) ? -width : 0,
      active: false, moved: false
    };
  });

  document.addEventListener("pointermove", function (e) {
    if (!drag || e.pointerId !== drag.pointerId) return;
    var dx = e.clientX - drag.startX;
    var dy = e.clientY - drag.startY;
    if (!drag.active) {
      // Only claim the gesture once it's clearly horizontal (lets vertical
      // scrolling through; touch-action: pan-y handles the rest).
      if (Math.abs(dx) <= SLOP || Math.abs(dx) <= Math.abs(dy)) return;
      drag.active = true;
      drag.track.style.transition = "none";
      if (drag.surface.setPointerCapture) {
        try { drag.surface.setPointerCapture(e.pointerId); } catch (_) {}
      }
    }
    e.preventDefault();
    drag.moved = true;
    var x = Math.max(-drag.width, Math.min(0, drag.base + dx));
    drag.track.style.transform = "translateX(" + x + "px)";
  });

  function endDrag(e) {
    if (!drag || (e && e.pointerId !== drag.pointerId)) return;
    var d = drag; drag = null;
    d.track.style.transition = "";
    if (!d.active) return; // a tap — let the click handler run
    var dx = (e ? e.clientX : d.startX) - d.startX;
    var x = Math.max(-d.width, Math.min(0, d.base + dx));
    if (x <= -d.width / 2) { openRowEl(d.li); openRow = d.li; } // past half-open, snap open
    else { closeRow(d.li); if (openRow === d.li) openRow = null; }
    if (d.moved) suppressClick = true;
  }
  document.addEventListener("pointerup", endDrag);
  document.addEventListener("pointercancel", endDrag);

  // Delete: confirm, then DELETE the row's target. The server (via the CLI)
  // removes the build/product from the shared index and deletes its files.
  function handleDelete(btn) {
    var li = btn.closest("li");
    var url = li && li.getAttribute("data-delete");
    if (!url) return;
    var label = (btn.getAttribute("aria-label") || "this build").replace(/^Delete\s+/, "");
    if (!window.confirm("Delete “" + label + "”? This removes it and its build files for all your devices.")) {
      return;
    }
    btn.disabled = true;
    fetch(url, { method: "DELETE", headers: { "Accept": "application/json" } })
      .then(function (res) {
        return res.json().then(
          function (body) { return { ok: res.ok && body && body.ok, body: body }; },
          function () { return { ok: res.ok, body: null }; }
        );
      })
      .then(function (r) {
        if (r.ok) {
          // A product page with no rows left would 404 on reload — go home.
          var remaining = document.querySelectorAll("ul li").length - 1;
          if (location.pathname.indexOf("/deployit/p/") === 0 && remaining <= 0) {
            window.location.assign("/deployit/");
          } else {
            window.location.reload();
          }
          return;
        }
        btn.disabled = false;
        window.alert((r.body && (r.body.display || r.body.error)) || "Delete failed.");
      })
      .catch(function () {
        btn.disabled = false;
        window.alert("Delete failed — network error.");
      });
  }

  // Single delegated click listener for delete, swipe-suppression, install
  // links, closing an open row, and row tap-to-navigate.
  document.addEventListener("click", function (e) {
    var delBtn = e.target.closest(".swipe-delete");
    if (delBtn) { handleDelete(delBtn); return; }
    if (suppressClick) { suppressClick = false; e.preventDefault(); e.stopPropagation(); return; }
    if (e.target.closest("a.install")) return; // let install/download links work
    if (openRow) { closeRow(openRow); openRow = null; return; } // tap closes an open row
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
