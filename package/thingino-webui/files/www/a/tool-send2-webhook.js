(function () {
  "use strict";

  const form = $("#webhookForm");

  async function loadConfig() {
    await send2Load("Webhook", (data) => {
      const webhook = data.webhook || {};
      $("#webhook_url").value = webhook.url || "";
      $("#webhook_message").value = webhook.message || "";
      $("#webhook_send_photo").checked =
        webhook.send_photo !== false && webhook.send_photo !== "false";
      $("#webhook_send_video").checked =
        webhook.send_video === true || webhook.send_video === "true";
    });
  }

  if (form) {
    form.addEventListener("submit", (event) =>
      send2Save("Webhook", form, event, () => ({
        webhook: {
          url: $("#webhook_url").value.trim(),
          message: $("#webhook_message").value.trim(),
          send_photo: $("#webhook_send_photo").checked,
          send_video: $("#webhook_send_video").checked,
          enabled: true,
        },
      })),
    );
  }

  send2SetupReload($("#webhook-reload"), "Webhook", loadConfig);
  loadConfig();
})();
