/* streamer-osd.js - NATIVE per-stream OSD pages (streamer-osd0.html and
 * streamer-osd1.html share this script). Talks directly to the timps
 * streamer over window.timpsApi (GET/POST /control on timps's own port,
 * per-boot token) - no json-prudynt.cgi bridge for these pages (the OSD
 * wiring in a/preview.js is gated off here; preview.js keeps only the live
 * preview <img>, which already loads straight from timps).
 *
 * Phase 1 (this file): the UI is DATA-DRIVEN. Each video stream carries its
 * own independent set of up to MS_MAX_OSD (=8) generic overlay items; every
 * item is a text-or-logo slot with the same field set (enabled/text/x/y/
 * font_size/color/transparency/outline/outline_color). Instead of four
 * hard-coded named boxes (time/usertext/uptime/logo) this page renders one
 * "card" per in-use item index and lets the user add/remove items (0..8),
 * edit every field, and drive both streams' item N at once.
 *
 * Stream:  detected from the page's body id (page-streamer-osd0 -> section
 *          "osd0", page-streamer-osd1 -> "osd1"). Index IS the identity - old
 *          configs (0=time,1=user text,2=uptime,3=logo) load unchanged by
 *          index, distinguished text-vs-logo by each item's "type".
 * Load:    timpsApi.get() returns BOTH streams' item sets in one shot; we
 *          populate this stream's cards and remember the other stream's items
 *          (for the "apply to both" scope + its restart bookkeeping).
 * Save:    per-item changed leaves apply LIVE via
 *          timpsApi.set({osdS:{N:{leaf:val}}}) and persist immediately. A card
 *          scoped to "both streams" POSTs the same leaves to osd0.N AND osd1.N.
 * Restart: the global osd.enabled master switch is persist+restart, and
 *          enabling an item that was OFF when the streamer started cannot be
 *          applied live (its IMP region only exists when enabled at startup).
 *          Both surface the "Restart streamer" hint; each card shows a
 *          per-item Live / Needs-restart / Off status pill.
 * Caps:    caps.osd lists the item leaf keys this build/SoC applies live
 *          (text,x,y,font_size,color,transparency,outline,outline_color).
 *          Each per-leaf control greys out when its key is absent. enabled,
 *          x/y position and the structural controls are NOT caps-gated
 *          (enabled is structural, never advertised in caps.osd).
 * Type:    switching an item text<->logo (and logo upload) is Phase 2 - it
 *          needs a persist-only "type"/"logo_path" leaf the streamer does not
 *          accept over /control yet, so the type selector is disabled with a
 *          tooltip and simply reflects the item's current type.
 * Colors:  <input type=color> (#rrggbb) + its "-alpha" range make up the timps
 *          "0xAARRGGBB" color and back. This is separate from "transparency"
 *          (a 0..255 group alpha over the whole item).
 * Offline: if timps is unreachable the page shows a notice and no cards; it
 *          never throws.
 */
(function () {
  "use strict";

  var m = document.body && /^page-streamer-osd([01])$/.exec(document.body.id);
  if (!m) return;
  var S = parseInt(m[1], 10); // 0 or 1: this page's stream
  var OTHER = 1 - S;
  var SEC = "osd" + S; // timps /control section for this stream
  var MAX_OSD = 8; // MS_MAX_OSD

  var STREAM_NAME = { 0: "Main stream", 1: "Substream" };
  var LIVE_LEAVES = [
    "enabled", "text", "x", "y", "font_size",
    "color", "transparency", "outline", "outline_color",
  ];

  function $id(id) { return document.getElementById(id); }

  function toast(type, message, ms) {
    if (typeof window.showAlert === "function")
      window.showAlert(type, message, ms);
    else console.log("[streamer-osd]", type + ":", message);
  }

  function restartHint() {
    toast(
      "warning",
      "Setting saved. Restart the streamer (Restart streamer in the menu) for it to take effect.",
      8000,
    );
  }

  // ---- conversions -----------------------------------------------------

  // timps "0xAARRGGBB" -> {color:"#rrggbb", alpha:0..255}
  function fromTimpsColor(v) {
    var n = parseInt(String(v), 16);
    if (isNaN(n)) return null;
    var rgb = (n & 0xffffff).toString(16).padStart(6, "0");
    return { color: "#" + rgb, alpha: (n >>> 24) & 0xff };
  }

  // "#rrggbb" + alpha 0..255 -> timps "0xAARRGGBB"
  function toTimpsColor(hex, alpha) {
    var rgb = /^#?([0-9a-f]{6})/i.exec(hex || "");
    if (!rgb) return null;
    var a = Math.min(255, Math.max(0, isNaN(alpha) ? 255 : alpha));
    return "0x" + a.toString(16).padStart(2, "0").toUpperCase() +
      rgb[1].toUpperCase();
  }

  // signed coordinate (negative = from the right/bottom edge) <-> the
  // magnitude+anchor pair the position widget shows. 0 and positive => start
  // edge (left/top); negative => end edge (right/bottom), magnitude = -v.
  function posToAnchor(v) {
    var n = parseInt(v, 10);
    if (isNaN(n)) n = 0;
    return n < 0 ? { anchor: "end", mag: -n } : { anchor: "start", mag: n };
  }
  function anchorToPos(anchor, mag) {
    var n = parseInt(mag, 10);
    if (isNaN(n) || n < 0) n = 0;
    return anchor === "end" ? -n : n;
  }

  // ---- shared state ----------------------------------------------------

  var capsOsd = []; // leaf keys this build applies live
  // item enabled state at streamer boot, per stream: enabling an item that
  // was off at boot has no IMP region, so the live enable is a no-op until a
  // restart. Captured for BOTH streams (the single GET returns both) so the
  // "both streams" scope can flag a restart on either side.
  var bootEnabled = { 0: {}, 1: {} };
  // last loaded item snapshot per stream (for the other stream in "both"
  // scope auto-detect and to remember a card's current type)
  var itemData = { 0: {}, 1: {} };

  // ---- POST helpers ----------------------------------------------------

  function sendBody(body, busyEl) {
    if (busyEl) busyEl.classList.add("opacity-75");
    return window.timpsApi
      .set(body)
      .catch(function (err) {
        console.error("timps set failed:", err);
        toast("danger", "Failed to apply setting: " + (err.message || err));
      })
      .then(function () {
        if (busyEl) busyEl.classList.remove("opacity-75");
      });
  }

  // POST one item's changed leaves. scope "both" writes osd0.N AND osd1.N.
  function sendItem(item, leaves, scope, busyEl) {
    var body = {};
    var secs = scope === "both" ? ["osd" + S, "osd" + OTHER] : [SEC];
    secs.forEach(function (sec) {
      body[sec] = {};
      body[sec][String(item)] = leaves;
    });
    return sendBody(body, busyEl);
  }

  // ---- caps gating (per leaf; structural fields never gated) ------------

  function leafSupported(leaf) {
    // enabled + x/y position are structural, always available; enabled is
    // never even advertised in caps.osd. Everything else is caps-gated.
    if (leaf === "enabled" || leaf === "x" || leaf === "y") return true;
    return capsOsd.indexOf(leaf) >= 0;
  }

  function applyCaps(card) {
    var fields = card.querySelectorAll("[data-leaf]");
    Array.prototype.forEach.call(fields, function (f) {
      var leaf = f.getAttribute("data-leaf");
      // the type selector is Phase 2 (disabled regardless of caps)
      if (leaf === "type") return;
      var ok = leafSupported(leaf);
      f.classList.toggle("disabled", !ok);
      var inputs = f.querySelectorAll("input, select, button");
      Array.prototype.forEach.call(inputs, function (el) { el.disabled = !ok; });
    });
  }

  // ---- status pill -----------------------------------------------------

  // three states derived purely from data we already have:
  //  off            - item not enabled
  //  live           - enabled AND it was enabled at streamer boot (has region)
  //  needs-restart  - enabled now but off at boot (no region until restart)
  function updatePill(card) {
    var item = parseInt(card.getAttribute("data-item"), 10);
    var pill = card.querySelector(".osd-status");
    var enabled = card.querySelector(".osd-enabled").checked;
    if (!enabled) {
      pill.className = "osd-status badge text-bg-secondary";
      pill.textContent = "Off";
      return;
    }
    if (bootEnabled[S][item]) {
      pill.className = "osd-status badge text-bg-success";
      pill.textContent = "Live";
    } else {
      pill.className = "osd-status badge text-bg-warning";
      pill.textContent = "Needs restart";
    }
  }

  // whether enabling this item (for the active scope) requires a restart on
  // any targeted stream
  function enableNeedsRestart(item, scope) {
    if (!bootEnabled[S][item]) return true;
    if (scope === "both" && !bootEnabled[OTHER][item]) return true;
    return false;
  }

  // ---- card construction ----------------------------------------------

  function cardScope(card) {
    var sel = card.querySelector(".osd-scope");
    return sel ? sel.value : "this";
  }

  // read the combined position from a card's x/y widgets -> {x, y}
  function readPosition(card) {
    var xa = card.querySelector(".osd-x-anchor").value;
    var xm = card.querySelector(".osd-x-mag").value;
    var ya = card.querySelector(".osd-y-anchor").value;
    var ym = card.querySelector(".osd-y-mag").value;
    return { x: anchorToPos(xa, xm), y: anchorToPos(ya, ym) };
  }

  var CARD_HTML =
    '<div class="card-header d-flex flex-wrap align-items-center gap-2">' +
      '<span class="badge text-bg-secondary osd-index"></span>' +
      '<div class="form-check form-switch m-0" data-leaf="enabled">' +
        '<input class="form-check-input osd-enabled" type="checkbox" role="switch">' +
      '</div>' +
      '<select class="form-select form-select-sm osd-type" style="width:auto" ' +
        'data-leaf="type" disabled ' +
        'title="Switching an overlay between text and logo needs a streamer update (coming soon)">' +
        '<option value="text">Text</option>' +
        '<option value="logo">Logo</option>' +
      '</select>' +
      '<span class="osd-status badge text-bg-secondary">Off</span>' +
      '<div class="ms-auto d-flex align-items-center gap-2">' +
        '<label class="small text-body-secondary mb-0">Apply to</label>' +
        '<select class="form-select form-select-sm osd-scope" style="width:auto">' +
          '<option value="this"></option>' +
          '<option value="both">Both streams</option>' +
        '</select>' +
        '<button type="button" class="btn btn-sm btn-outline-danger osd-remove" ' +
          'title="Remove overlay"><i class="bi bi-trash"></i></button>' +
      '</div>' +
    '</div>' +
    '<div class="card-body">' +
      '<div class="osd-text-body">' +
        '<p class="mb-2" data-leaf="text">' +
          '<label class="form-label mb-1">Text / template</label>' +
          '<input type="text" class="form-control osd-text" ' +
            'placeholder="e.g. %F %T  or  {hostname}">' +
          '<span class="form-text">strftime %codes plus {hostname}/{ip}/{uptime}/{fps}/{bitrate} placeholders</span>' +
        '</p>' +
        '<div class="row g-2">' +
          '<div class="col-6 col-md-3" data-leaf="font_size">' +
            '<label class="form-label mb-1">Font size</label>' +
            '<input type="number" min="8" max="256" class="form-control osd-fontsize">' +
          '</div>' +
          '<div class="col-6 col-md-3" data-leaf="outline">' +
            '<label class="form-label mb-1">Outline</label>' +
            '<input type="number" min="0" max="64" class="form-control osd-outline">' +
          '</div>' +
          '<div class="col-6 col-md-3" data-leaf="color">' +
            '<label class="form-label mb-1">Color</label>' +
            '<div class="d-flex align-items-center gap-1">' +
              '<input type="color" class="form-control form-control-color osd-fill">' +
              '<input type="range" min="0" max="255" step="1" class="form-range osd-fill-alpha" title="Color alpha">' +
            '</div>' +
          '</div>' +
          '<div class="col-6 col-md-3" data-leaf="outline_color">' +
            '<label class="form-label mb-1">Outline color</label>' +
            '<div class="d-flex align-items-center gap-1">' +
              '<input type="color" class="form-control form-control-color osd-stroke">' +
              '<input type="range" min="0" max="255" step="1" class="form-range osd-stroke-alpha" title="Outline alpha">' +
            '</div>' +
          '</div>' +
        '</div>' +
      '</div>' +
      '<div class="osd-logo-body">' +
        '<p class="mb-2 text-body-secondary"><i class="bi bi-image me-1"></i>' +
          'Logo overlay. The image file is set in the streamer configuration; ' +
          'position and transparency are editable here.</p>' +
      '</div>' +
      '<div class="row g-2 mt-1 align-items-end">' +
        '<div class="col-12 col-md-6" data-leaf="x">' +
          '<label class="form-label mb-1">Position</label>' +
          '<div class="input-group input-group-sm">' +
            '<select class="form-select osd-x-anchor" style="max-width:6rem">' +
              '<option value="start">Left +</option>' +
              '<option value="end">Right -</option>' +
            '</select>' +
            '<input type="number" min="0" class="form-control osd-x-mag" placeholder="x">' +
            '<select class="form-select osd-y-anchor" style="max-width:6rem">' +
              '<option value="start">Top +</option>' +
              '<option value="end">Bottom -</option>' +
            '</select>' +
            '<input type="number" min="0" class="form-control osd-y-mag" placeholder="y">' +
          '</div>' +
          '<span class="form-text">distance in px from the chosen edges</span>' +
        '</div>' +
        '<div class="col-12 col-md-6" data-leaf="transparency">' +
          '<label class="form-label mb-1">Transparency ' +
            '<span class="osd-trans-val text-body-secondary"></span></label>' +
          '<input type="range" min="0" max="255" step="1" class="form-range osd-trans">' +
        '</div>' +
      '</div>' +
      '<div class="osd-both-note alert alert-info py-1 px-2 mt-2 mb-0 small d-none">' +
        '<i class="bi bi-link-45deg me-1"></i>Also applied to ' + STREAM_NAME[OTHER] +
      '</div>' +
    '</div>';

  function buildCard(item, data) {
    data = data || {};
    var card = document.createElement("div");
    card.className = "card mb-2 osd-card";
    card.setAttribute("data-item", String(item));
    card.innerHTML = CARD_HTML;

    card.querySelector(".osd-index").textContent = "#" + item;
    card.querySelector(".osd-scope option[value='this']").textContent =
      "This stream (" + STREAM_NAME[S] + ")";

    // ---- populate from the loaded item ----
    var type = data.type === "logo" ? "logo" : "text";
    card.querySelector(".osd-type").value = type;
    card.setAttribute("data-type", type);
    card.querySelector(".osd-text-body").classList.toggle("d-none", type === "logo");
    card.querySelector(".osd-logo-body").classList.toggle("d-none", type !== "logo");

    card.querySelector(".osd-enabled").checked = !!Number(data.enabled);
    if (type !== "logo") {
      if (data.text !== undefined) card.querySelector(".osd-text").value = data.text;
      if (data.font_size !== undefined)
        card.querySelector(".osd-fontsize").value = data.font_size;
      if (data.outline !== undefined)
        card.querySelector(".osd-outline").value = data.outline;
      var fc = fromTimpsColor(data.color);
      if (fc) {
        card.querySelector(".osd-fill").value = fc.color;
        card.querySelector(".osd-fill-alpha").value = fc.alpha;
      }
      var sc = fromTimpsColor(data.outline_color);
      if (sc) {
        card.querySelector(".osd-stroke").value = sc.color;
        card.querySelector(".osd-stroke-alpha").value = sc.alpha;
      }
    }
    var px = posToAnchor(data.x);
    card.querySelector(".osd-x-anchor").value = px.anchor;
    card.querySelector(".osd-x-mag").value = px.mag;
    var py = posToAnchor(data.y);
    card.querySelector(".osd-y-anchor").value = py.anchor;
    card.querySelector(".osd-y-mag").value = py.mag;
    var tr = (data.transparency === undefined) ? 255 : Number(data.transparency);
    card.querySelector(".osd-trans").value = tr;
    card.querySelector(".osd-trans-val").textContent = "(" + tr + ")";

    // ---- scope: default "this"; auto-detect "both" only when this item is
    // enabled and byte-identical on both streams (a nice-to-have, never for
    // empty/default slots) ----
    if (Number(data.enabled) && itemsIdentical(item)) {
      card.querySelector(".osd-scope").value = "both";
    }
    syncBothNote(card);

    wireCard(card);
    applyCaps(card);
    updatePill(card);
    return card;
  }

  function itemsIdentical(item) {
    var a = itemData[0][item], b = itemData[1][item];
    if (!a || !b) return false;
    return LIVE_LEAVES.every(function (k) {
      return String(a[k]) === String(b[k]);
    });
  }

  function syncBothNote(card) {
    var both = cardScope(card) === "both";
    card.querySelector(".osd-both-note").classList.toggle("d-none", !both);
  }

  // ---- per-card wiring -------------------------------------------------

  function wireCard(card) {
    var item = parseInt(card.getAttribute("data-item"), 10);

    function push(leaves, busyEl) {
      return sendItem(item, leaves, cardScope(card), busyEl);
    }

    // enable toggle: applies live for a boot-enabled item; for an item that
    // was off at boot (incl. every freshly added item) it persists but only
    // renders after a restart
    var en = card.querySelector(".osd-enabled");
    en.addEventListener("change", function () {
      var restart = en.checked && enableNeedsRestart(item, cardScope(card));
      var p = push({ enabled: en.checked ? 1 : 0 }, en);
      updatePill(card);
      if (restart) p.then(restartHint);
    });

    // scope change: no POST by itself; just re-flags the "both" note. Existing
    // values are re-pushed to the other stream on the next edit (nudge any
    // field to copy immediately).
    card.querySelector(".osd-scope").addEventListener("change", function () {
      syncBothNote(card);
    });

    var text = card.querySelector(".osd-text");
    if (text)
      text.addEventListener("change", function () {
        push({ text: text.value }, text);
      });

    var fontsize = card.querySelector(".osd-fontsize");
    if (fontsize)
      fontsize.addEventListener("change", function () {
        var v = parseInt(fontsize.value, 10);
        if (!isNaN(v)) push({ font_size: v }, fontsize);
      });

    var outline = card.querySelector(".osd-outline");
    if (outline)
      outline.addEventListener("change", function () {
        var v = parseInt(outline.value, 10);
        if (!isNaN(v)) push({ outline: v }, outline);
      });

    function fillColor() {
      var picker = card.querySelector(".osd-fill");
      var alpha = parseInt(card.querySelector(".osd-fill-alpha").value, 10);
      return toTimpsColor(picker.value, alpha);
    }
    function strokeColor() {
      var picker = card.querySelector(".osd-stroke");
      var alpha = parseInt(card.querySelector(".osd-stroke-alpha").value, 10);
      return toTimpsColor(picker.value, alpha);
    }
    ["osd-fill", "osd-fill-alpha"].forEach(function (cls) {
      var el = card.querySelector("." + cls);
      if (el) el.addEventListener("change", function () {
        var c = fillColor();
        if (c) push({ color: c }, el);
      });
    });
    ["osd-stroke", "osd-stroke-alpha"].forEach(function (cls) {
      var el = card.querySelector("." + cls);
      if (el) el.addEventListener("change", function () {
        var c = strokeColor();
        if (c) push({ outline_color: c }, el);
      });
    });

    // position: any of the four widgets pushes the combined {x,y}
    ["osd-x-anchor", "osd-x-mag", "osd-y-anchor", "osd-y-mag"].forEach(function (cls) {
      var el = card.querySelector("." + cls);
      if (el) el.addEventListener("change", function () {
        push(readPosition(card), el);
      });
    });

    var trans = card.querySelector(".osd-trans");
    trans.addEventListener("input", function () {
      card.querySelector(".osd-trans-val").textContent = "(" + trans.value + ")";
    });
    trans.addEventListener("change", function () {
      var v = parseInt(trans.value, 10);
      if (!isNaN(v)) push({ transparency: v }, trans);
    });

    // remove: disable (live-hide + persist) and drop the card. A fixed slot
    // is never destroyed server-side; disabling it frees it for reuse.
    card.querySelector(".osd-remove").addEventListener("click", function () {
      push({ enabled: 0 }, card);
      card.parentNode.removeChild(card);
      refreshSlotUI();
    });
  }

  // ---- list management -------------------------------------------------

  function shownItems() {
    var out = {};
    var cards = document.querySelectorAll("#osd-items .osd-card");
    Array.prototype.forEach.call(cards, function (c) {
      out[parseInt(c.getAttribute("data-item"), 10)] = true;
    });
    return out;
  }

  function refreshSlotUI() {
    var count = document.querySelectorAll("#osd-items .osd-card").length;
    var empty = $id("osd-items-empty");
    if (empty) empty.classList.toggle("d-none", count > 0);
    var addBtn = $id("osd-add-item");
    if (addBtn) addBtn.disabled = count >= MAX_OSD;
    var counter = $id("osd-slot-count");
    if (counter) counter.textContent = count + " of " + MAX_OSD + " overlays used";
  }

  function addItem() {
    var shown = shownItems();
    var idx = -1;
    for (var i = 0; i < MAX_OSD; i++) {
      if (!shown[i]) { idx = i; break; }
    }
    if (idx < 0) return;
    // seed a fresh card from whatever the streamer currently holds at that
    // index (defaults: disabled text at a small offset), enabled off
    var seed = itemData[S][idx] || { type: "text", enabled: 0, x: 10, y: 10 };
    var card = buildCard(idx, seed);
    $id("osd-items").appendChild(card);
    refreshSlotUI();
    card.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }

  // ---- load ------------------------------------------------------------

  function offlineNotice() {
    if ($id("timps-offline-notice")) return;
    var div = document.createElement("div");
    div.id = "timps-offline-notice";
    div.className = "alert alert-warning mt-2";
    div.innerHTML =
      '<i class="bi bi-exclamation-triangle me-1"></i>' +
      "The streamer is not reachable, OSD controls are disabled. " +
      "Check that the timps service is running, then reload this page.";
    var h3 = document.querySelector("main h3");
    if (h3 && h3.parentNode) h3.parentNode.insertBefore(div, h3.nextSibling);
    else {
      var c = document.querySelector("main .container");
      if (c) c.appendChild(div);
    }
  }

  function inUse(it) {
    return it && (Number(it.enabled) ||
      (it.text && String(it.text).length) || it.type === "logo");
  }

  function load() {
    if (!window.timpsApi) {
      console.error("timps-api.js not loaded");
      offlineNotice();
      return;
    }
    window.timpsApi
      .get()
      .then(function (json) {
        capsOsd = (json.caps && json.caps.osd) || [];
        [0, 1].forEach(function (s) {
          var set = json["osd" + s] || {};
          itemData[s] = {};
          bootEnabled[s] = {};
          for (var i = 0; i < MAX_OSD; i++) {
            var it = set[String(i)] || {};
            itemData[s][i] = it;
            bootEnabled[s][i] = !!Number(it.enabled);
          }
        });

        // master switch
        var master = $id("osd-master");
        if (master && json.osd && json.osd.enabled !== undefined)
          master.checked = !!Number(json.osd.enabled);

        // render one card per in-use item on THIS stream
        var host = $id("osd-items");
        host.innerHTML = "";
        for (var i = 0; i < MAX_OSD; i++) {
          if (inUse(itemData[S][i]))
            host.appendChild(buildCard(i, itemData[S][i]));
        }
        refreshSlotUI();
      })
      .catch(function (err) {
        console.warn("timps unreachable, OSD controls stay disabled:", err);
        offlineNotice();
      });
  }

  // ---- static wiring (master switch, add button, save button) ----------

  function wireStatic() {
    var master = $id("osd-master");
    if (master) {
      master.addEventListener("change", function () {
        sendBody({ osd: { enabled: master.checked ? 1 : 0 } }, master).then(
          restartHint,
        );
      });
    }
    var addBtn = $id("osd-add-item");
    if (addBtn) addBtn.addEventListener("click", addItem);

    var saveBtn = $id("save-prudynt-config");
    if (saveBtn) {
      saveBtn.addEventListener("click", function () {
        toast(
          "success",
          "Nothing to do: OSD settings are applied live and already saved to the streamer configuration.",
          4000,
        );
      });
    }
  }

  // remote change for this stream (osdS.N.* or the shared osd.enabled master)
  // just re-runs the full load - cheap and always internally consistent. Don't
  // fight the user mid-edit on this page.
  function onConfigEvent(type, data) {
    if (!data) return;
    if (!data.resync) {
      var key = data.key || "";
      if (key !== "osd.enabled" && key.indexOf(SEC + ".") !== 0) return;
    }
    var ae = document.activeElement;
    if (ae && (ae.tagName === "INPUT" || ae.tagName === "SELECT" ||
      ae.tagName === "TEXTAREA"))
      return;
    load();
  }

  function init() {
    wireStatic();
    load();
    if (window.timpsApi) window.timpsApi.events("config", onConfigEvent);
  }

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", init, { once: true });
  else init();
})();
