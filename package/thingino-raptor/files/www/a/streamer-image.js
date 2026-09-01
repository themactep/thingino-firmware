/**
 * Raptor Image Quality page.
 *
 * The generic /a/preview.js wires the WB/AE/flip controls through the agent
 * (saveImageValue -> sendToEndpoint -> thinginoStreamer.applyPayload), but it
 * disables them on load expecting the prudynt json-imaging.cgi bridge to
 * re-enable them later. Raptor has no such CGI, so this module loads the live
 * image settings from the agent and re-enables/populates those fields.
 *
 * brightness/contrast/sharpness/saturation are already handled end-to-end by
 * preview.js; this module owns only the fields preview.js leaves disabled.
 */
(function () {
  "use strict";

  // page field id -> agent config key
  var FIELD_MAP = {
    image_core_wb_mode: "core_wb_mode",
    image_wb_bgain: "wb_bgain",
    image_wb_rgain: "wb_rgain",
    image_ae_compensation: "ae_compensation",
    image_hflip: "hflip",
    image_vflip: "vflip",
  };

  function el(id) {
    return document.getElementById(id);
  }

  function enable(id) {
    var node = el(id);
    if (!node) return;
    node.disabled = false;
    var wrap =
      node.closest("p, .select, .boolean, .col") || node.parentElement;
    if (wrap) wrap.classList.remove("disabled");
  }

  function populate(id, value) {
    var node = el(id);
    if (!node) return;
    if (node.type === "checkbox") {
      node.checked = value === true || value === 1 || value === "1";
    } else if (value === null || value === undefined) {
      node.value = "";
    } else {
      node.value = value;
    }
  }

  async function load() {
    var helper = window.thinginoStreamer;
    if (!helper || typeof helper.agentRequest !== "function") return;
    try {
      var cfg = await helper.agentRequest("/api/v1/config", {
        cache: "no-store",
      });
      var image = (cfg && cfg.image) || {};
      Object.keys(FIELD_MAP).forEach(function (id) {
        populate(id, image[FIELD_MAP[id]]);
        enable(id);
      });
    } catch (err) {
      console.warn("Failed to load raptor image settings", err);
    }
  }

  function init() {
    // Re-enable immediately; values arrive when the config fetch resolves.
    Object.keys(FIELD_MAP).forEach(enable);
    load();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init, { once: true });
  } else {
    init();
  }
})();
