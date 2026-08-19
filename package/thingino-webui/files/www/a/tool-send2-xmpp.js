(function () {
  "use strict";

  const form = $("#xmppForm");

  async function loadConfig() {
    await send2Load("XMPP", (data) => {
      const xmpp = data.xmpp || {};
      $("#xmpp_jid").value = xmpp.jid || "";
      $("#xmpp_password").value = xmpp.password || "";
      $("#xmpp_resource").value = xmpp.resource || "thingino";
      $("#xmpp_bosh_url").value = xmpp.bosh_url || "";
      $("#xmpp_recipient").value = xmpp.recipient || "";
      $("#xmpp_send_photo").checked =
        xmpp.send_photo === true || xmpp.send_photo === "true";
    });
  }

  if (form) {
    form.addEventListener("submit", (event) =>
      send2Save("XMPP", form, event, () => ({
        xmpp: {
          jid: $("#xmpp_jid").value.trim(),
          password: $("#xmpp_password").value.trim(),
          resource: $("#xmpp_resource").value.trim() || "thingino",
          bosh_url: $("#xmpp_bosh_url").value.trim(),
          recipient: $("#xmpp_recipient").value.trim(),
          send_photo: $("#xmpp_send_photo").checked,
          enabled: true,
        },
      })),
    );
  }

  const reloadBtn = $("#xmpp-reload");
  if (reloadBtn) {
    reloadBtn.addEventListener("click", loadConfig);
  }

  loadConfig();
})();
