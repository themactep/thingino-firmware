(function () {
  "use strict";

  const form = $("#mqttForm");
  const mqttSsl = $("#mqtt_use_ssl");
  const mqttTlsSkipVerify = $("#mqtt_tls_skip_verify");
  const mqttTlsSkipVerifyRow = $("#mqtt_tls_skip_verify_row");

  function updateTlsSkipVerifyState() {
    var enabled = mqttSsl.checked;
    mqttTlsSkipVerifyRow.classList.toggle("d-none", !enabled);
    mqttTlsSkipVerify.disabled = !enabled;
  }

  async function loadConfig() {
    await send2Load("MQTT", (data) => {
      const mqtt = data.mqtt || {};
      $("#mqtt_client_id").value = mqtt.client_id || "";
      $("#mqtt_host").value = mqtt.host || "";
      $("#mqtt_port").value = mqtt.port || "1883";
      $("#mqtt_username").value = mqtt.username || "";
      $("#mqtt_password").value = mqtt.password || "";
      $("#mqtt_use_ssl").checked =
        mqtt.use_ssl === true || mqtt.use_ssl === "true";
      $("#mqtt_tls_skip_verify").checked =
        mqtt.tls_skip_verify === true || mqtt.tls_skip_verify === "true";
      $("#mqtt_topic").value = mqtt.topic || "";
      $("#mqtt_message").value = mqtt.message || "";
      updateTlsSkipVerifyState();
    });
  }

  if (form) {
    form.addEventListener("submit", (event) =>
      send2Save("MQTT", form, event, () => ({
        mqtt: {
          client_id: $("#mqtt_client_id").value.trim(),
          host: $("#mqtt_host").value.trim(),
          port: Number($("#mqtt_port").value) || 1883,
          username: $("#mqtt_username").value.trim(),
          password: $("#mqtt_password").value.trim(),
          use_ssl: $("#mqtt_use_ssl").checked,
          tls_skip_verify: $("#mqtt_tls_skip_verify").checked,
          topic: $("#mqtt_topic").value.trim(),
          message: $("#mqtt_message").value.trim(),
          enabled: true,
        },
      })),
    );
  }

  mqttSsl.addEventListener("change", updateTlsSkipVerifyState);
  send2SetupReload($("#mqtt-reload"), "MQTT", loadConfig);
  loadConfig();
})();
