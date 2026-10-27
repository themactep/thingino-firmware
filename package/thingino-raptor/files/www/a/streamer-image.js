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
 * Noise-reduction fields additionally get their own save path via the agent
 * settings endpoints (image/noise-reduction, image/temporal-nr), which map to
 * the sinter/temper tuning controls (SetModule_Ratio on Gen3 SoCs).
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
    noise_reduction: "sinter",
    temporal_noise_reduction: "temper",
  };

  // field id -> agent settings endpoint (own save path; preview.js does not
  // wire these two fields)
  var ENDPOINT_MAP = {
    noise_reduction: "image/noise-reduction",
    temporal_noise_reduction: "image/temporal-nr",
  };

  // field id -> JSON payload member name the agent expects
  var PAYLOAD_MAP = {
    noise_reduction: "noise_reduction",
    temporal_noise_reduction: "temporal_noise_reduction",
  };

  function el(id) {
    return document.getElementById(id);
  }

  function enable(id) {
    var node = el(id);
    if (!node) return;
    node.disabled = false;
    // Walk every ancestor the preview.js disable paths may have tagged, up
    // to the column; the nearest wrapper alone is not enough because
    // preview.js and the hideUnsupportedControls path pick different ones.
    var wrap = node.closest("p, .select, .boolean, .mb-3, .col");
    while (wrap) {
      wrap.classList.remove("disabled");
      wrap.classList.remove("d-none");
      wrap = wrap.parentElement
        ? wrap.parentElement.closest("p, .mb-3, .col")
        : null;
    }
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

  function saveField(id) {
    var helper = window.thinginoStreamer;
    var endpoint = ENDPOINT_MAP[id];
    var node = el(id);
    if (!helper || !endpoint || !node) return;
    var body = {};
    body[PAYLOAD_MAP[id]] = node.value;
    helper
      .agentRequest("/api/v1/settings/" + endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      })
      .then(function () {
        enable(id);
      })
      .catch(function (err) {
        console.warn("Failed to save " + id, err);
      });
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
    // Noise-reduction fields save through the agent directly (preview.js
    // does not wire them).
    Object.keys(ENDPOINT_MAP).forEach(function (id) {
      var node = el(id);
      if (!node) return;
      node.addEventListener("change", function () {
        saveField(id);
      });
    });
    load();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init, { once: true });
  } else {
    init();
  }
})();
