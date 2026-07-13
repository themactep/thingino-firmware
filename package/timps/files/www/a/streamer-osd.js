/* streamer-osd.js - NATIVE per-stream OSD pages (streamer-osd0.html and
 * streamer-osd1.html share this script). Talks directly to the timps
 * streamer over window.timpsApi (GET/POST /control on timps's own port,
 * per-boot token) - no json-prudynt.cgi bridge for these pages (the OSD
 * wiring in a/preview.js is gated off here; preview.js keeps only the live
 * preview <img>, which already loads straight from timps).
 *
 * Stream:  detected from the page's body id (page-streamer-osd0 -> timps
 *          section "osd0", page-streamer-osd1 -> "osd1"). Each video stream
 *          carries its own independent overlay item set. Item layout (the
 *          timps default, same one the bridge used):
 *            0 = time, 1 = user text, 2 = uptime, 3 = logo
 * Load:    timpsApi.get() -> populate every control from this page's osdS
 *          object + the global "osd" master switch; enable only the controls
 *          whose timps item leaf key is listed in caps.osd.
 * Save:    per-item leaves (enabled/text/x/y/font_size/color/transparency/
 *          outline/outline_color) apply LIVE via timpsApi.set({osdS:{N:{..}}})
 *          and persist immediately. The global osd.enabled master switch is
 *          persist+restart, and enabling an overlay that was off when the
 *          streamer started cannot be applied live either (its region only
 *          exists when it was enabled at startup) - both show the existing
 *          "Restart streamer" hint (the menu entry calls
 *          /x/restart-prudynt.cgi).
 * Colors:  the page's <input type=color> (#rrggbb) plus its "-alpha" range
 *          slider make up the timps color "0xAARRGGBB" and back.
 * Offline: if timps is unreachable the controls stay disabled and a small
 *          notice appears; nothing throws.
 */
(function () {
  "use strict";

  var m = document.body && /^page-streamer-osd([01])$/.exec(document.body.id);
  if (!m) return;
  var S = m[1]; // "0" or "1": this page's stream
  var SEC = "osd" + S; // timps /control section (and the page id prefix)

  // page element groups -> timps item indexes (the timps default layout)
  var ITEMS = { time: 0, usertext: 1, uptime: 2, logo: 3 };
  var TEXT_ITEMS = [0, 1, 2]; // items driven by the page-level size/shadow

  function $id(id) { return document.getElementById(id); }
  function el(name) { return $id(SEC + "_" + name); }

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

  // ---- conversions ----

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
    return (
      "0x" + a.toString(16).padStart(2, "0").toUpperCase() +
      rgb[1].toUpperCase()
    );
  }

  // one color picker + its "-alpha" slider -> timps color string
  function colorValue(name) {
    var picker = el(name);
    var alphaEl = el(name + "-alpha");
    var a = 255;
    if (alphaEl && alphaEl.value !== "") {
      var parsed = parseInt(alphaEl.value, 10);
      if (!isNaN(parsed)) a = parsed;
    }
    return toTimpsColor(picker ? picker.value : "#ffffff", a);
  }

  // "x,y" (negative = from the right/bottom edge, same convention on both
  // sides) -> {x,y}, or null when the field does not parse
  function parsePosition(v) {
    var p = /^\s*(-?\d+)\s*,\s*(-?\d+)\s*$/.exec(String(v || ""));
    return p ? { x: parseInt(p[1], 10), y: parseInt(p[2], 10) } : null;
  }

  // ---- state / wiring ----

  // item enabled state as loaded from timps: enabling an item that this
  // snapshot says is off gets the restart hint (its region only exists when
  // the item was enabled when the streamer started; timps refuses the live
  // enable and applies it on the next restart)
  var loadedEnabled = {};

  function setEnabled(id, on) {
    var e = $id(id);
    if (!e) return;
    e.disabled = !on;
    var wrap =
      e.closest("p, .number-range, .select, .boolean, .file, .form-switch") ||
      e.parentElement;
    if (wrap) wrap.classList.toggle("disabled", !on);
  }

  // POST one item's changed leaves: {"osdS":{"N":{key:val,...}}}
  function sendItem(item, leaves, busyEl) {
    var body = {};
    body[SEC] = {};
    body[SEC][String(item)] = leaves;
    return sendBody(body, busyEl);
  }

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

  // per-element control wiring: name = page control suffix, item = timps
  // item index, build(el) = item leaves for the POST (null = ignore input)
  function wire(name, item, build) {
    var e = el(name);
    if (!e) return;
    e.addEventListener("change", function () {
      var leaves = build(e);
      if (!leaves) return;
      var p = sendItem(item, leaves, e);
      // enabling an overlay that was off when the state was loaded:
      // persisted, but the live enable is refused without a region
      if (
        leaves.enabled === 1 &&
        !loadedEnabled[item]
      )
        p.then(restartHint);
    });
  }

  function wireControls() {
    // everything starts greyed out until timps confirms support
    ALL_CONTROLS.forEach(function (name) {
      setEnabled(SEC + "_" + name, false);
    });

    // global master switch: config-only in timps (imp_osd_setup runs once at
    // startup), so it always gets the restart hint
    var master = el("enabled");
    if (master) {
      master.addEventListener("change", function () {
        sendBody({ osd: { enabled: master.checked ? 1 : 0 } }, master).then(
          restartHint,
        );
      });
    }

    // page-level font size / shadow width drive every text item (timps
    // keeps font_size/outline per item) - applied live
    var fontsize = el("fontsize");
    if (fontsize) {
      fontsize.addEventListener("change", function () {
        var v = parseInt(fontsize.value, 10);
        if (isNaN(v)) return;
        var body = {};
        body[SEC] = {};
        TEXT_ITEMS.forEach(function (i) {
          body[SEC][String(i)] = { font_size: v };
        });
        sendBody(body, fontsize);
      });
    }
    var strokesize = el("strokesize");
    if (strokesize) {
      strokesize.addEventListener("change", function () {
        var v = parseInt(strokesize.value, 10);
        if (isNaN(v)) return;
        var body = {};
        body[SEC] = {};
        TEXT_ITEMS.forEach(function (i) {
          body[SEC][String(i)] = { outline: v };
        });
        sendBody(body, strokesize);
      });
    }

    Object.keys(ITEMS).forEach(function (group) {
      var item = ITEMS[group];
      wire(group + "_enabled", item, function (e) {
        return { enabled: e.checked ? 1 : 0 };
      });
      wire(group + "_position", item, function (e) {
        return parsePosition(e.value);
      });
      if (group === "logo") return; // colors/format are text-item-only
      wire(group + "_fillcolor", item, function () {
        var c = colorValue(group + "_fillcolor");
        return c ? { color: c } : null;
      });
      wire(group + "_fillcolor-alpha", item, function () {
        var c = colorValue(group + "_fillcolor");
        return c ? { color: c } : null;
      });
      wire(group + "_strokecolor", item, function () {
        var c = colorValue(group + "_strokecolor");
        return c ? { outline_color: c } : null;
      });
      wire(group + "_strokecolor-alpha", item, function () {
        var c = colorValue(group + "_strokecolor");
        return c ? { outline_color: c } : null;
      });
      if (group === "uptime") return; // no format field on the page
      wire(group + "_format", item, function (e) {
        // timps text template: strftime %.. plus {hostname}/{ip}/{uptime}/
        // {fps}/... placeholders - passed through unchanged
        return { text: e.value };
      });
    });

    // timps applies + persists every change immediately; the button is
    // kept only to reassure users trained on the old save-to-file step.
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

  // every page control suffix (for the initial grey-out + caps mapping)
  var ALL_CONTROLS = [
    "enabled", "fontsize", "strokesize",
    "logo_enabled", "logo_position",
    "time_enabled", "time_position", "time_fillcolor", "time_fillcolor-alpha",
    "time_strokecolor", "time_strokecolor-alpha", "time_format",
    "uptime_enabled", "uptime_position", "uptime_fillcolor",
    "uptime_fillcolor-alpha", "uptime_strokecolor", "uptime_strokecolor-alpha",
    "usertext_enabled", "usertext_position", "usertext_fillcolor",
    "usertext_fillcolor-alpha", "usertext_strokecolor",
    "usertext_strokecolor-alpha", "usertext_format",
  ];

  // control suffix pattern -> the timps item leaf key that must be in
  // caps.osd for the control to enable
  function capsKeyFor(name) {
    if (name === "enabled") return "enabled"; // master switch
    if (name === "fontsize") return "font_size";
    if (name === "strokesize") return "outline";
    if (/_enabled$/.test(name)) return "enabled";
    if (/_position$/.test(name)) return "x";
    if (/_fillcolor(-alpha)?$/.test(name)) return "color";
    if (/_strokecolor(-alpha)?$/.test(name)) return "outline_color";
    if (/_format$/.test(name)) return "text";
    return null;
  }

  function populateColor(name, timpsColor) {
    var c = fromTimpsColor(timpsColor);
    if (!c) return;
    var picker = el(name);
    if (picker) picker.value = c.color;
    var alphaEl = el(name + "-alpha");
    if (alphaEl) alphaEl.value = c.alpha;
  }

  function populateItem(group, item) {
    if (!item) return;
    var checkbox = el(group + "_enabled");
    if (checkbox) checkbox.checked = !!Number(item.enabled);
    var pos = el(group + "_position");
    if (pos && item.x !== undefined && item.y !== undefined)
      pos.value = item.x + "," + item.y;
    if (group === "logo") return;
    populateColor(group + "_fillcolor", item.color);
    populateColor(group + "_strokecolor", item.outline_color);
    var format = el(group + "_format");
    if (format && item.text !== undefined) format.value = item.text;
  }

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
    else document.querySelector("main .container")?.appendChild(div);
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
        var set = json[SEC] || {}; // THIS stream's independent item set
        var capsOsd = (json.caps && json.caps.osd) || [];

        Object.keys(ITEMS).forEach(function (group) {
          var item = set[String(ITEMS[group])];
          populateItem(group, item);
          loadedEnabled[ITEMS[group]] = !!(item && Number(item.enabled));
        });

        // master switch + the page-level size/shadow (mirrors of the first
        // text item; timps keeps them per item)
        var master = el("enabled");
        if (master && json.osd && json.osd.enabled !== undefined)
          master.checked = !!Number(json.osd.enabled);
        var first = set["0"] || {};
        var fontsize = el("fontsize");
        if (fontsize && first.font_size !== undefined)
          fontsize.value = first.font_size;
        var strokesize = el("strokesize");
        if (strokesize && first.outline !== undefined)
          strokesize.value = first.outline;

        ALL_CONTROLS.forEach(function (name) {
          var key = capsKeyFor(name);
          setEnabled(SEC + "_" + name, !!key && capsOsd.indexOf(key) >= 0);
        });
      })
      .catch(function (err) {
        console.warn("timps unreachable, OSD controls stay disabled:", err);
        offlineNotice();
      });
  }

  function init() {
    wireControls();
    load();
  }

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", init, { once: true });
  else init();
})();
