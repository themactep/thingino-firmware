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
      $("#gotify_priority").value = gotify.priority ?? 5;
      $("#gotify_send_photo").checked =
        gotify.send_photo === true || gotify.send_photo === "true";
      $("#gotify_send_video").checked =
        gotify.send_video === true || gotify.send_video === "true";
    });
  }

  if (form) {
    form.addEventListener("submit", (event) =>
      send2Save("Gotify", form, event, () => ({
        gotify: {
          url: $("#gotify_url").value.trim(),
          token: $("#gotify_token").value.trim(),
          title: $("#gotify_title").value.trim(),
          message: $("#gotify_message").value.trim(),
          priority: Number($("#gotify_priority").value) || 5,
          send_photo: $("#gotify_send_photo").checked,
          send_video: $("#gotify_send_video").checked,
          enabled: true,
        },
      })),
    );
  }

  send2SetupReload($("#gotify-reload"), "Gotify", loadConfig);
  loadConfig();
})();
