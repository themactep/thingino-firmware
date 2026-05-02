(function () {
  "use strict";

  const form = $("#gotifyForm");

  async function loadConfig() {
    await send2Load("Gotify", (data) => {
      const gotify = data.gotify || {};
      $("#gotify_url").value = gotify.url || "";
      $("#gotify_token").value = gotify.token || "";
      $("#gotify_title").value = gotify.title || "Thingino Camera";
      $("#gotify_message").value =
        gotify.message || "Motion detected at %Y-%m-%d %H:%M:%S";
      $("#gotify_extras").value = gotify.extras || "";
      $("#gotify_priority").value = gotify.priority ?? 5;
      $("#gotify_send_photo").checked = false;
      $("#gotify_send_video").checked = false;
    });
  }

  if (form) {
    form.addEventListener("submit", (event) => {
      const extrasValue = $("#gotify_extras").value.trim();
      if (extrasValue) {
        try {
          const parsed = JSON.parse(extrasValue);
          if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
            throw new Error("Extras must be a JSON object.");
          }
        } catch (error) {
          event.preventDefault();
          showAlert("danger", error.message || "Extras must be valid JSON.");
          return;
        }
      }

      send2Save("Gotify", form, event, () => ({
        gotify: {
          url: $("#gotify_url").value.trim(),
          token: $("#gotify_token").value.trim(),
          title: $("#gotify_title").value.trim(),
          message: $("#gotify_message").value.trim(),
          extras: extrasValue,
          priority: Number($("#gotify_priority").value) || 5,
          send_photo: false,
          send_video: false,
          enabled: true,
        },
      }));
    });
  }

  send2SetupReload($("#gotify-reload"), "Gotify", loadConfig);
  loadConfig();
})();
