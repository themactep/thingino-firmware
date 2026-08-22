/**
 * Preview-page OSD settings modal (prudynt).
 *
 * Restores the in-page OSD dialog on the live view that was removed from
 * the shared preview.html: a floating OSD button over the preview image
 * opens a modal with burn-in OSD settings (format, scale, colors), the SEI
 * elements editor, and SEI overlay visual settings (stored locally).
 *
 * Config reads/writes go through the prudynt config API on :8080 with the
 * X-API-Key header (same idiom as sei-osd.js / streamer-osd.html).  Saves
 * include `action.save_config` + `restart_thread` so the OSD thread picks
 * up changes immediately.
 *
 * Plugin-owned file: registered via prudynt.webui.json `preview.scripts`,
 * injected into the preview page at build time.  No core webui changes.
 */
(function () {
  "use strict";

  var STORAGE_KEY = "sei-osd-settings";
  var TYPES = ["text", "gain", "hostname", "ipaddress", "timestamp", "uptime"];
  var DEFAULTS = {
    text: { format: "", position: "10,10" },
    gain: { format: "%s", position: "10,-10" },
    hostname: { format: "%s", position: "0,10" },
    ipaddress: { format: "%s", position: "0,30" },
    timestamp: { format: "%F %T", position: "10,10" },
    uptime: { format: "%02lu:%02lu:%02lu", position: "-10,10" },
  };

  var CFG = "http://" + location.hostname + ":8080/api/v1/config";
  var API_KEY_PROMISE = fetch("/x/api-key.cgi", { cache: "no-store" })
    .then(function (r) {
      return r.json();
    })
    .then(function (d) {
      return d.exists && d.api_key ? d.api_key : "";
    })
    .catch(function () {
      return "";
    });

  async function osdApiFetch(url, options) {
    var key = await API_KEY_PROMISE;
    options = options || {};
    options.headers = options.headers || {};
    if (key) options.headers["X-API-Key"] = key;
    return fetch(url, options);
  }

  // -- visual settings (localStorage) --------------------------------
  function loadSettings() {
    try {
      return JSON.parse(localStorage.getItem(STORAGE_KEY)) || {};
    } catch (_) {
      return {};
    }
  }
  function saveSettings(s) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(s));
    } catch (_) {}
  }

  // -- swatch/color helpers -------------------------------------------
  function updateSwatch(input, swatch) {
    var v = (input.value || "").trim();
    if (v && /^#?[0-9a-fA-F]{6,8}$/.test(v)) {
      if (v[0] !== "#") v = "#" + v;
      if (v.length === 7) v += "ff";
      var r = parseInt(v.substring(1, 3), 16);
      var g = parseInt(v.substring(3, 5), 16);
      var b = parseInt(v.substring(5, 7), 16);
      var a = parseInt(v.substring(7, 9), 16) / 255;
      swatch.style.backgroundColor =
        "rgba(" + r + "," + g + "," + b + "," + a + ")";
      swatch.style.opacity = "";
    } else {
      swatch.style.backgroundColor = "";
      swatch.style.opacity = "";
    }
  }

  function wireColor(swatch, picker, input, alphaSlider) {
    swatch.addEventListener("click", function () {
      picker.click();
    });
    picker.addEventListener("input", function () {
      var cur = input.value.trim(),
        alpha = "ff";
      if (cur && /^#?[0-9a-fA-F]{8}$/.test(cur)) {
        if (cur[0] !== "#") cur = "#" + cur;
        alpha = cur.substring(7, 9);
      }
      input.value = picker.value + alpha;
      updateSwatch(input, swatch);
    });
    input.addEventListener("input", function () {
      updateSwatch(input, swatch);
      var v = input.value.trim();
      if (v && /^#?[0-9a-fA-F]{8}$/.test(v)) {
        if (v[0] !== "#") v = "#" + v;
        if (alphaSlider) alphaSlider.value = parseInt(v.substring(7, 9), 16);
      }
    });
    if (alphaSlider) {
      alphaSlider.addEventListener("input", function () {
        var v = input.value.trim();
        if (!v || !/^#?[0-9a-fA-F]{8}$/.test(v)) {
          if (v && /^#?[0-9a-fA-F]{3,6}$/.test(v)) v = v + "ff";
          else v = "#ffffff";
          if (v[0] !== "#") v = "#" + v;
        } else {
          if (v[0] !== "#") v = "#" + v;
        }
        var alpha = ("0" + parseInt(alphaSlider.value, 10).toString(16)).slice(
          -2,
        );
        input.value = v.substring(0, 7) + alpha;
        updateSwatch(input, swatch);
      });
    }
  }

  // -- SEI elements editor --------------------------------------------
  function createRow(name, type, format, position) {
    var row = document.createElement("div");
    row.className = "osd-el-row d-flex gap-1 align-items-end mb-1";
    row.innerHTML =
      '<input class="form-control elem-name" placeholder="id" style="flex:0 0 100px" value="' +
      (name || "") +
      '">' +
      '<select class="form-select elem-type" style="flex:0 0 150px">' +
      TYPES.map(function (t) {
        return (
          '<option value="' +
          t +
          '"' +
          (t === type ? " selected" : "") +
          ">" +
          t +
          "</option>"
        );
      }).join("") +
      "</select>" +
      '<input class="form-control elem-format" placeholder="format" style="flex:1 1 auto" value="' +
      (format || "") +
      '">' +
      '<input class="form-control elem-position" placeholder="x,y" style="flex:0 0 70px" value="' +
      (position || "") +
      '">' +
      '<button class="btn btn-outline-danger btn-sm elem-remove flex-shrink-0" title="Remove">&times;</button>';
    row.querySelector(".elem-type").addEventListener("change", function () {
      var d = DEFAULTS[this.value];
      row.querySelector(".elem-format").value = d.format;
      row.querySelector(".elem-position").value = d.position;
    });
    row.querySelector(".elem-remove").addEventListener("click", function () {
      row.remove();
    });
    return row;
  }

  function collectElements() {
    var elems = {};
    document
      .querySelectorAll("#osd-elements-list .osd-el-row")
      .forEach(function (row) {
        var name = row.querySelector(".elem-name").value.trim();
        if (!name) return;
        elems[name] = {
          type: row.querySelector(".elem-type").value,
          format: row.querySelector(".elem-format").value,
          position: row.querySelector(".elem-position").value,
        };
      });
    return elems;
  }

  function loadElements(elems) {
    var list = document.getElementById("osd-elements-list");
    if (!list) return;
    list.innerHTML = "";
    if (!elems) return;
    Object.keys(elems).forEach(function (name) {
      var el = elems[name];
      list.appendChild(createRow(name, el.type, el.format, el.position));
    });
  }

  // -- modal markup ----------------------------------------------------
  var MODAL_HTML =
    '<div class="modal fade" id="osdModal" tabindex="-1" aria-labelledby="osdModalLabel" aria-hidden="true">' +
    '  <div class="modal-dialog modal-lg">' +
    '    <div class="modal-content">' +
    '      <div class="modal-header">' +
    '        <h5 class="modal-title" id="osdModalLabel">OSD Overlay Settings</h5>' +
    '        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>' +
    "      </div>" +
    '      <div class="modal-body">' +
    '        <ul class="nav nav-tabs" role="tablist">' +
    '          <li class="nav-item" role="presentation">' +
    '            <button class="nav-link active" id="burnin-tab" data-bs-toggle="tab" data-bs-target="#burnin-pane" type="button" role="tab" aria-controls="burnin-pane" aria-selected="true">Burn-in OSD</button>' +
    "          </li>" +
    '          <li class="nav-item" role="presentation">' +
    '            <button class="nav-link" id="sei-tab" data-bs-toggle="tab" data-bs-target="#sei-pane" type="button" role="tab" aria-controls="sei-pane" aria-selected="false">SEI OSD</button>' +
    "          </li>" +
    "        </ul>" +
    '        <div class="tab-content pt-3">' +
    '          <div class="tab-pane fade show active" id="burnin-pane" role="tabpanel" aria-labelledby="burnin-tab">' +
    '        <p class="form-switch">' +
    '          <input class="form-check-input" type="checkbox" id="burnin-enabled" role="switch">' +
    '          <label class="form-check-label" for="burnin-enabled">Enabled</label>' +
    "        </p>" +
    '        <p class="row">' +
    '          <label class="form-label col-3" for="burnin-format">Format</label>' +
    '          <input class="form-control col" type="text" id="burnin-format" placeholder="%F %T">' +
    "        </p>" +
    '        <p class="row">' +
    '          <label class="form-label col-3" for="burnin-scale">Scale</label>' +
    '          <select class="form-select col" id="burnin-scale">' +
    '            <option value="0">auto</option><option>1</option><option>2</option><option>3</option>' +
    "            <option>4</option><option>5</option><option>6</option><option>7</option>" +
    "            <option>8</option><option>9</option><option>10</option>" +
    "          </select>" +
    "        </p>" +
    '        <p class="row">' +
    '          <label class="form-label col-3" for="burnin-fill-color">Fill</label>' +
    '          <span class="input-group color-picker-group col">' +
    '            <span class="input-group-text color-swatch" id="modal-swatch-fill" title="Pick color">&nbsp;</span>' +
    '            <input class="d-none" type="color" id="modal-picker-fill">' +
    '            <input class="form-control font-monospace" type="text" id="burnin-fill-color" placeholder="#ffffffff" pattern="#?[0-9a-fA-F]{8}" maxlength="9">' +
    "          </span>" +
    '          <span class="col"><input class="alpha-slider" type="range" id="alpha-fill" min="0" max="255" value="255" title="Alpha"></span>' +
    "        </p>" +
    '        <p class="row">' +
    '          <label class="form-label col-3" for="burnin-outline-color">Outline</label>' +
    '          <span class="input-group color-picker-group col">' +
    '            <span class="input-group-text color-swatch" id="modal-swatch-outline" title="Pick color">&nbsp;</span>' +
    '            <input class="d-none" type="color" id="modal-picker-outline">' +
    '            <input class="form-control font-monospace" type="text" id="burnin-outline-color" placeholder="#000000ff" pattern="#?[0-9a-fA-F]{8}" maxlength="9">' +
    "          </span>" +
    '          <span class="col"><input class="alpha-slider" type="range" id="alpha-outline" min="0" max="255" value="255" title="Alpha"></span>' +
    "        </p>" +
    '        <p class="row">' +
    '          <label class="form-label col-3" for="burnin-background-color">Background</label>' +
    '          <span class="input-group color-picker-group col">' +
    '            <span class="input-group-text color-swatch" id="modal-swatch-bg" title="Pick color">&nbsp;</span>' +
    '            <input class="d-none" type="color" id="modal-picker-bg">' +
    '            <input class="form-control font-monospace" type="text" id="burnin-background-color" placeholder="#00000080" pattern="#?[0-9a-fA-F]{8}" maxlength="9">' +
    "          </span>" +
    '          <span class="col"><input class="alpha-slider" type="range" id="alpha-bg" min="0" max="255" value="128" title="Alpha"></span>' +
    "        </p>" +
    "          </div>" +
    '          <div class="tab-pane fade" id="sei-pane" role="tabpanel" aria-labelledby="sei-tab">' +
    '        <p class="form-switch">' +
    '          <input class="form-check-input" type="checkbox" id="osd-enabled" role="switch">' +
    '          <label class="form-check-label" for="osd-enabled">Enabled</label>' +
    "        </p>" +
    '        <p class="row">' +
    '          <label class="form-check-label col-3" for="osd-fontsize">Font</label>' +
    '          <select class="form-select col" id="osd-fontsize">' +
    "            <option>8</option><option>10</option><option>12</option><option>14</option>" +
    "            <option selected>16</option><option>18</option><option>20</option><option>24</option>" +
    "            <option>28</option><option>32</option><option>40</option><option>48</option>" +
    "            <option>56</option><option>64</option><option>72</option>" +
    "          </select>" +
    '          <span class="input-group col" style="width:10rem">' +
    '            <span class="input-group-text color-swatch" id="sei-swatch-fill" title="Pick color">&nbsp;</span>' +
    '            <input class="d-none" type="color" id="sei-picker-fill">' +
    '            <input class="form-control font-monospace" type="text" id="osd-color" value="#ffffff" pattern="#?[0-9a-fA-F]{6,8}" maxlength="9">' +
    "          </span>" +
    "        </p>" +
    '        <p class="row">' +
    '          <label class="form-check-label col-3" for="osd-stroke">Outline</label>' +
    '          <select class="form-select col" id="osd-stroke">' +
    "            <option>0</option><option selected>1</option><option>2</option>" +
    "            <option>3</option><option>4</option><option>5</option>" +
    "          </select>" +
    '          <span class="input-group col" style="width:10rem">' +
    '            <span class="input-group-text color-swatch" id="sei-swatch-stroke" title="Pick color">&nbsp;</span>' +
    '            <input class="d-none" type="color" id="sei-picker-stroke">' +
    '            <input class="form-control font-monospace" type="text" id="osd-stroke-color" value="#000000" pattern="#?[0-9a-fA-F]{6,8}" maxlength="9">' +
    "          </span>" +
    "        </p>" +
    '          <div id="osd-elements-list" class="mb-2"></div>' +
    '          <button type="button" class="btn btn-outline-primary btn-sm w-100 mb-3" id="osd-add-element">' +
    '            <i class="bi bi-plus-lg me-1"></i> Add element' +
    "          </button>" +
    "          </div>" +
    "        </div>" +
    "      </div>" +
    '      <div class="modal-footer">' +
    '        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>' +
    '        <button type="button" class="btn btn-primary" id="osd-save">Save to config</button>' +
    "      </div>" +
    "    </div>" +
    "  </div>" +
    "</div>";

  // -- config load/save ------------------------------------------------
  function loadOsdConfig() {
    osdApiFetch(CFG + "/osd")
      .then(function (r) {
        return r.json();
      })
      .then(function (d) {
        if (d.sei && d.sei.enabled !== undefined) {
          document.getElementById("osd-enabled").checked =
            d.sei.enabled !== false;
        }
        loadElements(d.sei ? d.sei.entries : null);
        if (d.burnin) {
          var enabled = document.getElementById("burnin-enabled");
          if (d.burnin.enabled !== undefined)
            enabled.checked = d.burnin.enabled !== false;
          if (d.burnin.format !== undefined && d.burnin.format !== null)
            document.getElementById("burnin-format").value = d.burnin.format;
          if (d.burnin.scale !== undefined && d.burnin.scale !== null)
            document.getElementById("burnin-scale").value = d.burnin.scale;
          var fc = document.getElementById("burnin-fill-color");
          var oc = document.getElementById("burnin-outline-color");
          var bc = document.getElementById("burnin-background-color");
          fc.value =
            d.burnin.fill_color !== undefined && d.burnin.fill_color !== null
              ? d.burnin.fill_color
              : "#ffffffff";
          oc.value =
            d.burnin.outline_color !== undefined &&
            d.burnin.outline_color !== null
              ? d.burnin.outline_color
              : "#000000ff";
          bc.value =
            d.burnin.background_color !== undefined &&
            d.burnin.background_color !== null
              ? d.burnin.background_color
              : "#00000080";
          updateSwatch(fc, document.getElementById("modal-swatch-fill"));
          updateSwatch(oc, document.getElementById("modal-swatch-outline"));
          updateSwatch(bc, document.getElementById("modal-swatch-bg"));
          var v = fc.value.trim();
          if (v && /^#?[0-9a-fA-F]{8}$/.test(v)) {
            if (v[0] !== "#") v = "#" + v;
            document.getElementById("alpha-fill").value = parseInt(
              v.substring(7, 9),
              16,
            );
          }
          v = oc.value.trim();
          if (v && /^#?[0-9a-fA-F]{8}$/.test(v)) {
            if (v[0] !== "#") v = "#" + v;
            document.getElementById("alpha-outline").value = parseInt(
              v.substring(7, 9),
              16,
            );
          }
          v = bc.value.trim();
          if (v && /^#?[0-9a-fA-F]{8}$/.test(v)) {
            if (v[0] !== "#") v = "#" + v;
            document.getElementById("alpha-bg").value = parseInt(
              v.substring(7, 9),
              16,
            );
          }
        }
      })
      .catch(function () {});
  }

  function applyVisualsLive() {
    saveSettings({
      fs: document.getElementById("osd-fontsize").value,
      stw: document.getElementById("osd-stroke").value,
      fc: document.getElementById("osd-color").value,
      sc: document.getElementById("osd-stroke-color").value,
    });
    if (window.SeiOSD && window.SeiOSD.repaint) window.SeiOSD.repaint();
  }

  async function saveOsdConfig() {
    var confirmed = await confirm("Save OSD elements to /etc/prudynt.json?");
    if (!confirmed) return;
    var btn = document.getElementById("osd-save");
    btn.disabled = true;
    try {
      var payload = {
        osd: {
          sei: {
            enabled: document.getElementById("osd-enabled").checked,
            entries: collectElements(),
          },
          burnin: {
            enabled: document.getElementById("burnin-enabled").checked,
            format: document.getElementById("burnin-format").value,
            background_color:
              document.getElementById("burnin-background-color").value.trim() ||
              undefined,
            scale: parseInt(document.getElementById("burnin-scale").value, 10),
            fill_color:
              document.getElementById("burnin-fill-color").value.trim() ||
              undefined,
            outline_color:
              document.getElementById("burnin-outline-color").value.trim() ||
              undefined,
          },
        },
        action: { save_config: null, restart_thread: 32 },
      };
      var r = await osdApiFetch(CFG, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      var msg = await r.json();
      if (msg.action && msg.action.save_config === "ok") {
        if (typeof showAlert === "function")
          showAlert("success", "OSD configuration saved and applied.", 4000);
        var modal = bootstrap.Modal.getInstance(
          document.getElementById("osdModal"),
        );
        if (modal) modal.hide();
      } else {
        throw new Error(msg.error || "Save failed");
      }
    } catch (e) {
      if (typeof showAlert === "function")
        showAlert("danger", "Failed: " + e.message, 6000);
    } finally {
      btn.disabled = false;
    }
  }

  // -- bootstrap --------------------------------------------------------
  function init() {
    var style = document.createElement("style");
    style.textContent =
      ".color-swatch{width:32px;padding:2px;cursor:pointer;border:1px solid var(--bs-border-color)}" +
      ".color-picker-group{width:150px}" +
      ".alpha-slider{width:48px;height:24px;cursor:pointer}";
    document.head.appendChild(style);

    document.body.insertAdjacentHTML("beforeend", MODAL_HTML);

    // OSD button in the Live View card header, next to Reload.
    var frame = document.getElementById("frame");
    var img = document.getElementById("preview");
    var host =
      document.querySelector(".preview-header-actions") ||
      frame ||
      (img && img.parentNode) ||
      document.body;
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "btn btn-outline-secondary";
    btn.id = "preview-osd";
    btn.title = "OSD overlay settings";
    btn.innerHTML = '<i class="bi bi-fonts"></i> OSD';
    host.appendChild(btn);

    // Burn-in color swatches
    wireColor(
      document.getElementById("modal-swatch-fill"),
      document.getElementById("modal-picker-fill"),
      document.getElementById("burnin-fill-color"),
      document.getElementById("alpha-fill"),
    );
    wireColor(
      document.getElementById("modal-swatch-outline"),
      document.getElementById("modal-picker-outline"),
      document.getElementById("burnin-outline-color"),
      document.getElementById("alpha-outline"),
    );
    wireColor(
      document.getElementById("modal-swatch-bg"),
      document.getElementById("modal-picker-bg"),
      document.getElementById("burnin-background-color"),
      document.getElementById("alpha-bg"),
    );
    // SEI color swatches (no alpha sliders — keep compact)
    wireColor(
      document.getElementById("sei-swatch-fill"),
      document.getElementById("sei-picker-fill"),
      document.getElementById("osd-color"),
    );
    wireColor(
      document.getElementById("sei-swatch-stroke"),
      document.getElementById("sei-picker-stroke"),
      document.getElementById("osd-stroke-color"),
    );

    btn.addEventListener("click", function () {
      loadOsdConfig();
      var s = loadSettings();
      document.getElementById("osd-fontsize").value = s.fs || 16;
      document.getElementById("osd-stroke").value = s.stw || 1;
      document.getElementById("osd-color").value = s.fc || "#ffffff";
      document.getElementById("osd-stroke-color").value = s.sc || "#000000";
      updateSwatch(
        document.getElementById("osd-color"),
        document.getElementById("sei-swatch-fill"),
      );
      updateSwatch(
        document.getElementById("osd-stroke-color"),
        document.getElementById("sei-swatch-stroke"),
      );
      new bootstrap.Modal(document.getElementById("osdModal")).show();
    });

    document
      .getElementById("osd-add-element")
      .addEventListener("click", function () {
        document
          .getElementById("osd-elements-list")
          .appendChild(createRow("", "text", "", ""));
      });

    ["osd-fontsize", "osd-stroke", "osd-color", "osd-stroke-color"].forEach(
      function (id) {
        document.getElementById(id).addEventListener("input", applyVisualsLive);
        document
          .getElementById(id)
          .addEventListener("change", applyVisualsLive);
      },
    );

    document
      .getElementById("osd-save")
      .addEventListener("click", saveOsdConfig);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
