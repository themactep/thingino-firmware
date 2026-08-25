(function () {
  "use strict";

  const form = $("#pushoverForm");

  async function loadConfig() {
    await send2Load("Pushover", (data) => {
      const pushover = data.pushover || {};
      $("#pushover_token").value = pushover.token || "";
      $("#pushover_user").value = pushover.user || "";
      $("#pushover_title").value = pushover.title || "";
      $("#pushover_message").value = pushover.message || "";
      $("#pushover_priority").value = String(pushover.priority ?? 0);
      $("#pushover_send_photo").checked =
        pushover.send_photo === true || pushover.send_photo === "true";
      $("#pushover_send_video").checked =
        pushover.send_video === true || pushover.send_video === "true";
    });
  }

  if (form) {
    form.addEventListener("submit", (event) =>
      send2Save("Pushover", form, event, () => ({
        pushover: {
          token: $("#pushover_token").value.trim(),
          user: $("#pushover_user").value.trim(),
          title: $("#pushover_title").value.trim(),
          message: $("#pushover_message").value,
          priority: Number($("#pushover_priority").value) || 0,
          send_photo: $("#pushover_send_photo").checked,
          // Photos and videos are mutually exclusive attachments in the
          // Pushover API; the UI only exposes photo, so persist false rather
          // than whatever the checkbox held.
          send_video: false,
          enabled: true,
        },
      })),
    );
  }

  send2SetupReload($("#pushover-reload"), "Pushover", loadConfig);
  loadConfig();
})();
