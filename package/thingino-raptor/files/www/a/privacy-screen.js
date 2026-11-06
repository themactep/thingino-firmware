(function () {
  "use strict";

  const OSD = "/api/v1/settings/streams/0/osd/privacy/";
  const ON_BOOT = "/api/v1/settings/privacy/on-boot";
  const HEX8 = /^#?[0-9a-fA-F]{8}$/;

  // field id -> [agent leaf, response key, raptor default shown when unset]
  const FIELDS = {
    privacy_cover_color: ["cover-color", "cover_color", "#000000ff"],
    privacy_text: ["text", "text", "Privacy Mode"],
    privacy_font_size: ["font-size", "font_size", ""],
    privacy_max_chars: ["max-chars", "max_chars", 20],
    privacy_position: ["position", "position", "center"],
    privacy_fill_color: ["fill-color", "fill_color", "#ffffffff"],
    privacy_stroke_color: ["stroke-color", "stroke_color", "#000000ff"],
  };
  const NUMERIC = ["privacy_font_size", "privacy_max_chars"];
  const COLORS = [
    ["swatch_cover", "picker_cover", "privacy_cover_color", "alpha_cover"],
    ["swatch_fill", "picker_fill", "privacy_fill_color", "alpha_fill"],
    [
      "swatch_outline",
      "picker_outline",
      "privacy_stroke_color",
      "alpha_outline",
    ],
  ];

  const $id = (id) => document.getElementById(id);
  const onBoot = $id("privacy_on_boot");
  const saveBtn = $id("save-privacy");
  const loaded = {};
  let loadedOnBoot = null;

  function notify(type, message) {
    if (window.showAlert) window.showAlert(type, message, 6000);
    else alert(message);
  }

  function normalizeHex(v) {
    v = (v || "").trim();
    if (!HEX8.test(v)) return null;
    return v[0] === "#" ? v : "#" + v;
  }

  function updateSwatch(input, swatch, picker, alpha) {
    const v = normalizeHex(input.value);
    if (!v) {
      swatch.style.backgroundColor = "";
      return;
    }
    const n = (i) => parseInt(v.substring(i, i + 2), 16);
    swatch.style.backgroundColor =
      "rgba(" + n(1) + "," + n(3) + "," + n(5) + "," + n(7) / 255 + ")";
    picker.value = v.substring(0, 7);
    alpha.value = n(7);
  }

  function wireColor([swatchId, pickerId, inputId, alphaId]) {
    const swatch = $id(swatchId);
    const picker = $id(pickerId);
    const input = $id(inputId);
    const alpha = $id(alphaId);
    const refresh = () => updateSwatch(input, swatch, picker, alpha);
    swatch.addEventListener("click", () => picker.click());
    picker.addEventListener("input", () => {
      const cur = normalizeHex(input.value);
      input.value = picker.value + (cur ? cur.substring(7, 9) : "ff");
      refresh();
    });
    input.addEventListener("input", refresh);
    alpha.addEventListener("input", () => {
      const cur = normalizeHex(input.value) || "#ffffffff";
      const a = ("0" + parseInt(alpha.value, 10).toString(16)).slice(-2);
      input.value = cur.substring(0, 7) + a;
      refresh();
    });
    return refresh;
  }

  const refreshers = COLORS.map(wireColor);

  function refreshPositionSelect() {
    const select = document.querySelector("select[data-position-for]");
    const input = $id(select.dataset.positionFor);
    const value = input.value.trim();
    const named = [...select.options].some(
      (o) => o.value === value && o.value !== "custom",
    );
    select.value = named ? value : value ? "custom" : "";
    input.classList.toggle("d-none", select.value !== "custom");
  }

  document
    .querySelector("select[data-position-for]")
    .addEventListener("change", (e) => {
      const input = $id(e.target.dataset.positionFor);
      const custom = e.target.value === "custom";
      input.classList.toggle("d-none", !custom);
      if (custom) {
        if (/^[a-z_]+$/.test(input.value)) input.value = "";
        input.focus();
      } else {
        input.value = e.target.value;
      }
    });

  function fieldValue(id) {
    const v = $id(id).value.trim();
    if (NUMERIC.includes(id)) {
      const n = Number(v);
      return v && Number.isFinite(n) && n > 0 ? n : null;
    }
    return v || null;
  }

  // A rejected write comes back without the "accepted" status.
  async function patch(path, body) {
    const res = await agentJsonRequest(path, {
      method: "PATCH",
      body,
      cache: "no-store",
    });
    if (!res || res.status !== "accepted") {
      throw new Error(Object.keys(body)[0] + " was rejected by the camera");
    }
  }

  async function load() {
    try {
      const boot = await agentJsonRequest(ON_BOOT, { cache: "no-store" });
      loadedOnBoot = !!(boot && boot.on_boot === true);
      onBoot.checked = loadedOnBoot;
    } catch (err) {
      console.warn("Failed to load privacy startup setting", err);
    }
    for (const [id, [leaf, key, fallback]] of Object.entries(FIELDS)) {
      try {
        const res = await agentJsonRequest(OSD + leaf, { cache: "no-store" });
        const v = res ? res[key] : null;
        $id(id).value = v === null || v === undefined ? fallback : v;
      } catch (err) {
        console.warn("Failed to load privacy " + leaf, err);
        $id(id).value = fallback;
      }
      loaded[id] = fieldValue(id);
    }
    refreshers.forEach((r) => r());
    refreshPositionSelect();
  }

  // Only changed fields are written, so an untouched page never creates the
  // [osd.privacy] section. Writes are sequential because the first one may
  // create that section with several config writes.
  async function save() {
    saveBtn.disabled = true;
    try {
      if (onBoot.checked !== loadedOnBoot) {
        await patch(ON_BOOT, { on_boot: onBoot.checked });
        loadedOnBoot = onBoot.checked;
      }
      for (const [id, [leaf, key]] of Object.entries(FIELDS)) {
        const now = fieldValue(id);
        if (now === null || now === loaded[id]) continue;
        await patch(OSD + leaf, { [key]: now });
        loaded[id] = now;
      }
      notify("success", "Privacy settings saved.");
    } catch (err) {
      console.error("Failed to save privacy settings", err);
      notify("danger", "Failed to save privacy settings: " + err.message);
    } finally {
      saveBtn.disabled = false;
    }
  }

  saveBtn.addEventListener("click", save);
  load();
})();
