(function () {
  "use strict";

  const form = $("#telegramForm");

  async function loadConfig() {
    await send2Load("Telegram", (data) => {
      const telegram = data.telegram || {};
      $("#telegram_token").value = telegram.token || "";
      $("#telegram_channel").value = telegram.channel || "";
      $("#telegram_caption").value = telegram.caption || "";
      $("#telegram_send_photo").checked =
        telegram.send_photo !== false && telegram.send_photo !== "false";
      $("#telegram_send_video").checked =
        telegram.send_video === true || telegram.send_video === "true";
    });
  }

  if (form) {
    form.addEventListener("submit", (event) =>
      send2Save("Telegram", form, event, () => ({
        telegram: {
          token: $("#telegram_token").value.trim(),
          channel: $("#telegram_channel").value.trim(),
          caption: $("#telegram_caption").value.trim(),
          send_photo: $("#telegram_send_photo").checked,
          send_video: $("#telegram_send_video").checked,
          enabled: true,
        },
      })),
    );
  }

  send2SetupReload($("#telegram-reload"), "Telegram", loadConfig);
  loadConfig();
})();
