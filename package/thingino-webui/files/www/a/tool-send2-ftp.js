(function () {
  "use strict";

  const form = $("#ftpForm");

  async function loadConfig() {
    await send2Load("FTP", (data) => {
      const ftp = data.ftp || {};
      $("#ftp_host").value = ftp.host || "";
      $("#ftp_port").value = ftp.port || "21";
      $("#ftp_username").value = ftp.username || "";
      $("#ftp_password").value = ftp.password || "";
      $("#ftp_use_ssl").checked =
        ftp.use_ssl === true || ftp.use_ssl === "true";
      $("#ftp_trust_cert").checked =
        ftp.trust_cert === true || ftp.trust_cert === "true";
      $("#ftp_path").value = ftp.path || "";
      $("#ftp_template").value = ftp.template || "";
      $("#ftp_send_photo").checked =
        ftp.send_photo !== false && ftp.send_photo !== "false";
      $("#ftp_send_video").checked =
        ftp.send_video === true || ftp.send_video === "true";
    });
  }

  if (form) {
    form.addEventListener("submit", (event) =>
      send2Save("FTP", form, event, () => ({
        ftp: {
          host: $("#ftp_host").value.trim(),
          port: Number($("#ftp_port").value) || 21,
          username: $("#ftp_username").value.trim(),
          password: $("#ftp_password").value.trim(),
          use_ssl: $("#ftp_use_ssl").checked,
          trust_cert: $("#ftp_trust_cert").checked,
          path: $("#ftp_path").value.trim(),
          template: $("#ftp_template").value.trim(),
          send_photo: $("#ftp_send_photo").checked,
          send_video: $("#ftp_send_video").checked,
          enabled: true,
        },
      })),
    );
  }

  send2SetupReload($("#ftp-reload"), "FTP", loadConfig);
  loadConfig();
})();
