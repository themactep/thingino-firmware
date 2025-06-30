#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Motion Guard"
%>
<%in _header.cgi %>

<% field_switch "motion_enabled" "Enable motion guard" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
  <div class="col">
    <% field_range "motion_sensitivity" "Sensitivity" "1,8,1" %>
    <% field_range "motion_cooldown_time" "Delay between alerts, sec." "5,30,1" %>
  </div>
  <div class="col">
    <% field_checkbox "motion_send2email" "Send to email address" "<a href=\"tool-send2email.cgi\">Configure sending to email</a>" %>
    <% field_checkbox "motion_send2telegram" "Send to Telegram" "<a href=\"tool-send2telegram.cgi\">Configure sending to Telegram</a>" %>
    <% field_checkbox "motion_send2mqtt" "Send to MQTT" "<a href=\"tool-send2mqtt.cgi\">Configure sending to MQTT</a>" %>
    <% field_checkbox "motion_send2webhook" "Send to webhook" "<a href=\"tool-send2webhook.cgi\">Configure sending to a webhook</a>" %>
    <% field_checkbox "motion_send2ftp" "Upload to FTP" "<a href=\"tool-send2ftp.cgi\">Configure uploading to FTP</a>" %>
    <% field_checkbox "motion_send2local" "Save locally" "<a href=\"tool-send2local.cgi\">Configure saving locally</a>" %>
    <% field_checkbox "motion_send2yadisk" "Upload to Yandex Disk" "<a href=\"tool-send2yadisk.cgi\">Configure sending to Yandex Disk</a>" %>
  </div>
  <div class="col">
    <div class="alert alert-info">
      <p>A motion event is detected by the streamer which triggers the <code>/sbin/motion</code> script,
      which sends alerts through the selected and preconfigured notification methods.</p>
      <p>You must configure at least one notification method for the motion monitor to work.</p>
      <% wiki_page "Plugin:-Motion-Guard" %>
    </div>
  </div>
</div>

<script>
const motion_params = ['enabled', 'sensitivity', 'cooldown_time'];
const send2_targets = ['email', 'telegram', 'mqtt', 'webhook', 'ftp', 'savelocal', 'yadisk'];

const wsPort = location.protocol === "https:" ? 8090 : 8089;
const wsProto = location.protocol === "https:" ? "wss:" : "ws:";
let ws = new WebSocket(`${wsProto}//${document.location.hostname}:${wsPort}?token=<%= $ws_token %>`);

ws.onopen = () => {
  const payload = '{"motion":{' + motion_params.map(x => `"${x}":null`).join() + '}}';
  ws.send(payload);
};
ws.onmessage = ev => {
  if (!ev.data) return;
  const msg = JSON.parse(ev.data);
  const data = msg.motion;
  if (data) {
    $('#motion_enabled').checked = data.enabled;
    if (data.sensitivity) {
      $('#motion_sensitivity').value = data.sensitivity;
      $('#motion_sensitivity-show').textContent = data.sensitivity;
    }
    if (data.cooldown_time) {
      $('#motion_cooldown_time').value = data.cooldown_time;
      $('#motion_cooldown_time-show').textContent = data.cooldown_time;
    }
  }
};

function sendToWs(payload) {
  ws.send(payload);
}

function saveValue(domain, name) {
  const el = document.getElementById(`${domain}_${name}`);
  if (!el) return;
  const value = el.type === 'checkbox' ? (el.checked ? 'true' : 'false') : el.value;
  sendToWs(JSON.stringify({ [domain]: { [name]: value }, action: { save_config: null, restart_thread: 2 } }));
}
motion_params.forEach(x => {
  document.getElementById(`motion_${x}`).onchange = () => saveValue('motion', x);
});

async function switchSend2Target(target, state) {
  const res = await fetch(`/x/json-motion.cgi?${new URLSearchParams({ target, state })}`);
  const data = await res.json();
  document.getElementById(`motion_send2${data.message.target}`).checked = data.message.status == 1;
}
send2_targets.forEach(x => {
  document.getElementById(`motion_send2${x}`).onchange = ev => switchSend2Target(x, ev.target.checked);
});
</script>

<div class="alert alert-dark ui-debug d-none">
  <h4 class="mb-3">Debug info</h4>
  <% ex "grep ^motion_ $CONFIG_FILE" %>
</div>

<%in _footer.cgi %>
