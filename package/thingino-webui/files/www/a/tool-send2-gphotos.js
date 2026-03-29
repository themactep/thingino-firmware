(function () {
  "use strict";

  const form = $("#gphotosForm");

  async function loadConfig() {
    await send2Load("Google Photos", (data) => {
      const gphotos = data.gphotos || {};
      $("#gphotos_client_id").value = gphotos.client_id || "";
      $("#gphotos_client_secret").value = gphotos.client_secret || "";
      $("#gphotos_refresh_token").value = gphotos.refresh_token || "";
      $("#gphotos_album_id").value = gphotos.album_id || "";
      $("#gphotos_description_template").value =
        gphotos.description_template || "";
      $("#gphotos_photo_name_template").value =
        gphotos.photo_name_template || "";
      $("#gphotos_video_name_template").value =
        gphotos.video_name_template || "";
    });
  }

  if (form) {
    form.addEventListener("submit", (event) =>
      send2Save("Google Photos", form, event, () => ({
        gphotos: {
          client_id: $("#gphotos_client_id").value.trim(),
          client_secret: $("#gphotos_client_secret").value.trim(),
          refresh_token: $("#gphotos_refresh_token").value.trim(),
          album_id: $("#gphotos_album_id").value.trim(),
          description_template: $("#gphotos_description_template").value.trim(),
          photo_name_template: $("#gphotos_photo_name_template").value.trim(),
          video_name_template: $("#gphotos_video_name_template").value.trim(),
          enabled: true,
        },
      })),
    );
  }

  send2SetupReload($("#gphotos-reload"), "Google Photos", loadConfig);
  loadConfig();
})();
