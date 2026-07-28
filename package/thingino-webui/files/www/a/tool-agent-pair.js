(function () {
  "use strict";

  const endpoint = "/x/json-agent-pair.cgi";
  const form = $("#agentPairForm");
  const statusEl = $("#agent-pair-status");
  const reloadBtn = $("#agent-pair-reload");
  const saveBtn = $("#agent-pair-save");

  function setStatus(text, tone) {
    statusEl.className = "alert alert-" + (tone || "secondary") + " mb-4";
    statusEl.textContent = text;
  }

  function loadStatus() {
    setStatus("Loading agent status…", "secondary");
    return fetch(endpoint, { credentials: "same-origin" })
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (data) {
        const agent = (data && data.agent) || {};
        const parts = [
          "enabled=" + String(agent.enabled),
          "tls=" + String(agent.tls),
          "listen=" + String(agent.listen || ""),
          "port=" + String(agent.port || ""),
          "token=" + (agent.has_token ? "configured" : "missing"),
        ];
        if (data && data.bootstrap_pending) {
          parts.push("bootstrap=pending");
        }
        setStatus("Agent status: " + parts.join(", "), "info");
        if (agent.listen) $("#agent_pair_listen").value = agent.listen;
        if (agent.port) $("#agent_pair_port").value = agent.port;
        if (typeof agent.tls === "boolean") {
          $("#agent_pair_tls").checked = agent.tls;
        }
      })
      .catch(function (err) {
        setStatus("Failed to load agent status: " + err.message, "danger");
      });
  }

  form.addEventListener("submit", function (ev) {
    ev.preventDefault();
    if (!form.checkValidity()) {
      form.classList.add("was-validated");
      return;
    }

    const body = {
      token: $("#agent_pair_token").value.trim(),
      tls: $("#agent_pair_tls").checked,
      listen: $("#agent_pair_listen").value.trim() || "0.0.0.0",
      port: Number($("#agent_pair_port").value) || 1998,
      mqtt_host: $("#agent_pair_mqtt_host").value.trim(),
      mqtt_port: Number($("#agent_pair_mqtt_port").value) || 1883,
      mqtt_username: $("#agent_pair_mqtt_username").value.trim(),
      mqtt_password: $("#agent_pair_mqtt_password").value,
    };

    saveBtn.disabled = true;
    setStatus("Writing bootstrap and restarting agent…", "secondary");

    fetch(endpoint, {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    })
      .then(function (res) {
        return res.json().then(function (data) {
          if (!res.ok || (data && data.ok === false)) {
            const msg =
              (data && data.error && data.error.message) ||
              "HTTP " + res.status;
            throw new Error(msg);
          }
          return data;
        });
      })
      .then(function (data) {
        setStatus(
          (data && data.message) || "Bootstrap installed; agent restart queued",
          "success",
        );
        $("#agent_pair_token").value = "";
        setTimeout(loadStatus, 1500);
      })
      .catch(function (err) {
        setStatus("Pairing failed: " + err.message, "danger");
      })
      .finally(function () {
        saveBtn.disabled = false;
      });
  });

  reloadBtn.addEventListener("click", function () {
    loadStatus();
  });

  loadStatus();
})();
