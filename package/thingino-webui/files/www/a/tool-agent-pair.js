(function () {
  "use strict";

  const endpoint = "/x/json-agent-pair.cgi";
  const form = $("#agentPairForm");
  const statusEl = $("#agent-pair-status");
  const tokenConfiguredEl = $("#agent-pair-token-configured");
  const mqttConfiguredEl = $("#agent-pair-mqtt-configured");
  const updateMqttEl = $("#agent_pair_update_mqtt");
  const reloadBtn = $("#agent-pair-reload");
  const saveBtn = $("#agent-pair-save");
  const mqttFields = [
    $("#agent_pair_mqtt_host"),
    $("#agent_pair_mqtt_port"),
    $("#agent_pair_mqtt_username"),
    $("#agent_pair_mqtt_password"),
  ];

  let hasToken = false;
  let mqttState = {
    configured: false,
    enabled: false,
    host: "",
    port: 1883,
    username: "",
    has_password: false,
  };

  function setStatus(text, tone) {
    statusEl.className = "alert alert-" + (tone || "secondary") + " mb-4";
    statusEl.textContent = text;
  }

  function setMqttEditable(editable) {
    mqttFields.forEach(function (el) {
      el.disabled = !editable;
    });
    if (!editable) {
      $("#agent_pair_mqtt_host").value = mqttState.host || "";
      $("#agent_pair_mqtt_port").value = mqttState.port || 1883;
      $("#agent_pair_mqtt_username").value = mqttState.username || "";
      $("#agent_pair_mqtt_password").value = "";
      $("#agent_pair_mqtt_password").placeholder = mqttState.has_password
        ? "••••••••"
        : "";
    } else {
      $("#agent_pair_mqtt_password").placeholder = mqttState.has_password
        ? "leave blank to keep current password"
        : "";
    }
  }

  function renderConfiguredBanners() {
    tokenConfiguredEl.classList.toggle("d-none", !hasToken);

    if (mqttState.configured) {
      const userBit = mqttState.username
        ? " as " + mqttState.username
        : "";
      mqttConfiguredEl.textContent =
        "Configured: " +
        mqttState.host +
        ":" +
        (mqttState.port || 1883) +
        userBit +
        (mqttState.enabled ? "" : " (mqtt_sub disabled)");
      mqttConfiguredEl.classList.remove("d-none");
    } else {
      mqttConfiguredEl.classList.add("d-none");
    }
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
        const mqtt = (data && data.mqtt_sub) || {};
        hasToken = !!agent.has_token;
        mqttState = {
          configured: !!mqtt.configured,
          enabled: !!mqtt.enabled,
          host: mqtt.host || "",
          port: mqtt.port || 1883,
          username: mqtt.username || "",
          has_password: !!mqtt.has_password,
        };

        const parts = [
          "enabled=" + String(agent.enabled),
          "tls=" + String(agent.tls),
          "listen=" + String(agent.listen || ""),
          "port=" + String(agent.port || ""),
          "token=" + (hasToken ? "configured" : "missing"),
        ];
        if (mqttState.configured) {
          parts.push("mqtt=" + mqttState.host + ":" + mqttState.port);
        }
        if (data && data.bootstrap_pending) {
          parts.push("bootstrap=pending");
        }
        setStatus("Agent status: " + parts.join(", "), "info");

        if (agent.listen) $("#agent_pair_listen").value = agent.listen;
        if (agent.port) $("#agent_pair_port").value = agent.port;
        if (typeof agent.tls === "boolean") {
          $("#agent_pair_tls").checked = agent.tls;
        }

        $("#agent_pair_token").required = !hasToken;
        updateMqttEl.checked = false;
        renderConfiguredBanners();
        setMqttEditable(false);
      })
      .catch(function (err) {
        setStatus("Failed to load agent status: " + err.message, "danger");
      });
  }

  updateMqttEl.addEventListener("change", function () {
    setMqttEditable(updateMqttEl.checked);
  });

  form.addEventListener("submit", function (ev) {
    ev.preventDefault();
    const token = $("#agent_pair_token").value.trim();
    if (!token && !hasToken) {
      form.classList.add("was-validated");
      $("#agent_pair_token").required = true;
      return;
    }
    if (updateMqttEl.checked && !$("#agent_pair_mqtt_host").value.trim()) {
      form.classList.add("was-validated");
      $("#agent_pair_mqtt_host").setCustomValidity("Broker address required");
      $("#agent_pair_mqtt_host").reportValidity();
      return;
    }
    $("#agent_pair_mqtt_host").setCustomValidity("");
    if (!form.checkValidity()) {
      form.classList.add("was-validated");
      return;
    }

    const body = {
      token: token,
      tls: $("#agent_pair_tls").checked,
      listen: $("#agent_pair_listen").value.trim() || "0.0.0.0",
      port: Number($("#agent_pair_port").value) || 1998,
      update_mqtt: updateMqttEl.checked,
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
