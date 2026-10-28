(function () {
  const API = "/x/json-lamp-socket.cgi";

  function $(sel) {
    return document.querySelector(sel);
  }

  async function apiFetch(body) {
    const opts = { headers: { Accept: "application/json" } };
    if (body) {
      opts.method = "POST";
      opts.headers["Content-Type"] = "application/json";
      opts.body = JSON.stringify(body);
    }
    const res = await fetch(API, opts);
    const data = await res.json();
    if (data.error) throw new Error(data.error.message);
    return data;
  }

  function showMsg(text, type, timeout) {
    if (typeof showAlert === "function") {
      showAlert(type, text, timeout);
    }
  }

  function renderState(state) {
    $("#lamp-state").textContent = state || "unknown";
    if (window.thinginoLampSocket) window.thinginoLampSocket.sync();
  }

  async function load() {
    try {
      const data = await apiFetch();
      const enabled = data.enabled === true;
      $("#lamp-disabled").hidden = enabled;
      $("#lamp-missing").hidden = !enabled || data.present !== false;
      $("#lamp-device").textContent = data.device || "not detected";
      $("#lamp-on").disabled = !enabled || data.present === false;
      $("#lamp-off").disabled = !enabled || data.present === false;
      $("#lamp-enabled").checked = enabled;
      $("#lamp-boot-state").value = data.boot_state || "none";
      $("#lamp-device-override").value = data.device_override || "";
      renderState(data.state);
    } catch (err) {
      showMsg("Failed to load Lamp Socket status: " + err.message, "danger");
    }
  }

  async function setLamp(action) {
    try {
      const data = await apiFetch({ action: action });
      renderState(data.state);
    } catch (err) {
      showMsg("Failed to switch the lamp: " + err.message, "danger");
    }
  }

  async function save(ev) {
    ev.preventDefault();
    try {
      await apiFetch({
        action: "save",
        enabled: $("#lamp-enabled").checked,
        boot_state: $("#lamp-boot-state").value,
        device: $("#lamp-device-override").value.trim(),
      });
      showMsg("Lamp Socket settings saved.", "success", 3000);
      load();
    } catch (err) {
      showMsg("Failed to save settings: " + err.message, "danger");
    }
  }

  async function diag(body) {
    const out = $("#lamp-reply");
    out.textContent = "...";
    try {
      const data = await apiFetch(body);
      out.textContent = data.reply || "(no reply)";
    } catch (err) {
      out.textContent = "Error: " + err.message;
    }
  }

  $("#lamp-on").addEventListener("click", () => setLamp("on"));
  $("#lamp-off").addEventListener("click", () => setLamp("off"));
  $("#lamp-form").addEventListener("submit", save);
  $("#reload-btn").addEventListener("click", load);
  $("#lamp-query").addEventListener("click", () => diag({ action: "query" }));
  $("#lamp-send").addEventListener("click", () =>
    diag({ action: "send", bytes: $("#lamp-raw").value.trim() }),
  );

  load();
})();
