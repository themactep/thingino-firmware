(function () {
  "use strict";

  const form = $("#trainForm");
  const DEFAULT_ENDPOINT = "https://train.thingino.com/v1/samples";

  function clamp(value, low, high, fallback) {
    const number = Number(value);
    if (!Number.isFinite(number)) return fallback;
    return Math.min(high, Math.max(low, Math.round(number)));
  }

  async function loadConfig() {
    await send2Load("Training pool", (data) => {
      const train = data.train || {};
      $("#train_enabled").checked =
        train.enabled === true || train.enabled === "true";
      $("#train_daily_limit").value = clamp(train.daily_limit, 1, 48, 12);
      $("#train_min_interval").value = clamp(
        train.min_interval,
        60,
        86400,
        300,
      );
      $("#train_endpoint").value = train.endpoint || DEFAULT_ENDPOINT;
    });
  }

  if (form) {
    form.addEventListener("submit", (event) =>
      send2Save("Training pool", form, event, () => ({
        train: {
          enabled: $("#train_enabled").checked,
          daily_limit: clamp($("#train_daily_limit").value, 1, 48, 12),
          min_interval: clamp($("#train_min_interval").value, 60, 86400, 300),
          endpoint: $("#train_endpoint").value.trim() || DEFAULT_ENDPOINT,
          send_photo: true,
          send_video: false,
        },
      })),
    );
  }

  send2SetupReload($("#train-reload"), "Training pool", loadConfig);
  loadConfig();
})();
