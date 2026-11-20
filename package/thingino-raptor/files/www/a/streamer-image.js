/**
 * Raptor Image Quality page.
 *
 * The raptor /a/preview.js wires brightness/contrast/sharpness/saturation
 * and the WB/AE/flip saves through the agent, but disables the WB/AE/flip
 * fields on load expecting the prudynt json-imaging.cgi bridge to re-enable
 * them later. Raptor has no such CGI, so this module loads the live image
 * settings from the agent and re-enables/populates those fields.
 *
 * The two noise-reduction fields belong to this module alone: it shows them,
 * fills them and saves them through the agent settings endpoints
 * (image/noise-reduction, image/temporal-nr), which map to the sinter/temper
 * tuning controls. Those controls exist only on T20-T31; elsewhere the agent
 * reports null and the fields stay hidden.
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

  // noise-reduction field id -> [agent config key, settings endpoint]
  var NR_FIELDS = {
    noise_reduction: ["noise_reduction", "image/noise-reduction"],
    temporal_noise_reduction: ["temporal_noise_reduction", "image/temporal-nr"],
  };

  function el(id) {
    return document.getElementById(id);
  }

  function wrapperOf(node) {
    return node.closest("p, .select, .boolean, .mb-3") || node.parentElement;
  }

  function enable(id) {
    var node = el(id);
    if (!node) return;
    node.disabled = false;
    var wrap = wrapperOf(node);
    if (wrap) wrap.classList.remove("disabled", "d-none");
  }

  function hide(id) {
    var node = el(id);
    if (!node) return;
    node.disabled = true;
    var wrap = wrapperOf(node);
    if (wrap) wrap.classList.add("d-none");
  }

  function populate(id, value) {
    var node = el(id);
    if (!node) return;
    if (value === null || value === undefined || value === "") return;
    node.value = value;
  }

  function saveNr(id) {
    var helper = window.thinginoStreamer;
    var node = el(id);
    if (!helper || !node) return;
    var body = {};
    body[NR_FIELDS[id][0]] = Number(node.value);
    helper
      .agentRequest("/api/v1/settings/" + NR_FIELDS[id][1], {
        method: "PATCH",
        body: body,
      })
      .catch(function (err) {
        console.warn("Failed to save " + id, err);
      });
  }

  function resetNr(id) {
    var node = el(id);
    if (!node || node.disabled) return;
    var min = Number(node.dataset.min || 0);
    var max = Number(node.dataset.max || 255);
    node.value = Math.round((min + max) / 2);
    saveNr(id);
  }

  async function load() {
    var helper = window.thinginoStreamer;
    if (!helper || typeof helper.agentRequest !== "function") return;
    var config = await helper.agentRequest("/api/v1/config");
    var image = (config && config.image) || {};
    Object.keys(FIELD_MAP).forEach(function (id) {
      populate(id, image[FIELD_MAP[id]]);
    });
    Object.keys(NR_FIELDS).forEach(function (id) {
      var value = image[NR_FIELDS[id][0]];
      if (value === null || value === undefined) {
        hide(id);
        return;
      }
      populate(id, value);
      enable(id);
    });
  }

  function init() {
    // Re-enable immediately; values arrive when the config fetch resolves.
    Object.keys(FIELD_MAP).forEach(enable);
    // The noise-reduction fields stay disabled until the agent reports a
    // value for them.
    Object.keys(NR_FIELDS).forEach(function (id) {
      var node = el(id);
      if (!node) return;
      node.disabled = true;
      node.addEventListener("change", function () {
        saveNr(id);
      });
      node.addEventListener("dblclick", function () {
        resetNr(id);
      });
    });
    load();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
