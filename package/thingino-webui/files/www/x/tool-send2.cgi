#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to Services"

config_file="/etc/send2.json"

camera_id=${network_macaddr//:/}
MOUNTS=$(awk '/cif|fat|nfs|smb/{print $2}' /etc/mtab)

mqtt_available="true"
[ -f /usr/bin/mosquitto_pub ] || mqtt_available="false"

# Helpers for per-domain JSON updates
get_value_for() {
  local domain="$1" key="$2"
  jct "$config_file" get "$domain.$key" 2>/dev/null
}

checked_if_true() {
  case "$1" in
    true|1|yes|on) echo -n "checked" ;;
    *) : ;;
  esac
}

tmp_file_for() {
  echo "/tmp/send2-$1.json"
}

set_value_for() {
  local domain="$1" key="$2" value="$3" tmp
  tmp=$(tmp_file_for "$domain")
  [ -f "$tmp" ] || echo '{}' > "$tmp"
  jct "$tmp" set "$domain.$key" "$value" >/dev/null 2>&1
}

import_domain_config() {
  local domain="$1" tmp
  tmp=$(tmp_file_for "$domain")
  [ -f "$tmp" ] || return
  jct "$config_file" import "$tmp"
  rm -f "$tmp"
}

# Track active tab
active_tab=$(echo "$QUERY_STRING" | sed -n 's/.*[?&]tab=\([^&]*\).*/\1/p')
[ -z "$active_tab" ] && active_tab=$(echo "$REQUEST_URI" | sed -n 's/.*[?&]tab=\([^&]*\).*/\1/p')
[ -z "$active_tab" ] && active_tab="$POST_tab"
case "$active_tab" in
summary|email|ftp|mqtt|ntfy|storage|telegram|webhook) : ;;
*) active_tab="summary" ;;
esac

motion_get_value() {
  jct /etc/prudynt.json get "motion.$1" 2>/dev/null
}

read_motion_config() {
  [ -f /etc/prudynt.json ] || return
  motion_send2email=$(motion_get_value send2email)
  motion_send2ftp=$(motion_get_value send2ftp)
  motion_send2mqtt=$(motion_get_value send2mqtt)
  motion_send2ntfy=$(motion_get_value send2ntfy)
  motion_send2storage=$(motion_get_value send2storage)
  motion_send2telegram=$(motion_get_value send2telegram)
  motion_send2webhook=$(motion_get_value send2webhook)
}

read_motion_runtime() {
  motion_enabled=$(motion_get_value enabled)
  motion_cooldown_time=$(motion_get_value cooldown_time)
  motion_sensitivity=$(motion_get_value sensitivity)
  default_for motion_enabled "false"
  default_for motion_cooldown_time "5"
  default_for motion_sensitivity "3"
}

########################################
# Email
########################################
email_defaults() {
  default_for email_from_name "Camera $network_hostname"
  default_for email_trust_cert "false"
  default_for email_port "25"
  default_for email_to_name "Camera admin"
  default_for email_subject "Snapshot from $network_hostname"
  default_for email_send_photo "false"
  default_for email_send_video "false"
  default_for email_use_ssl "false"
}

email_read_config() {
  [ -f "$config_file" ] || return

  email_from_address=$(get_value_for email from_address)
  email_from_name=$(get_value_for email from_name)
  email_to_address=$(get_value_for email to_address)
  email_to_name=$(get_value_for email to_name)
  email_subject=$(get_value_for email subject)
  email_body=$(get_value_for email body)
  email_host=$(get_value_for email host)
  email_port=$(get_value_for email port)
  email_username=$(get_value_for email username)
  email_password=$(get_value_for email password)
  email_use_ssl=$(get_value_for email use_ssl)
  email_trust_cert=$(get_value_for email trust_cert)
  email_send_photo=$(get_value_for email send_photo)
  email_send_video=$(get_value_for email send_video)
}

email_handle_submit() {
  error=""
  email_host="$POST_email_host"
  email_port="$POST_email_port"
  email_username="$POST_email_username"
  email_password="$POST_email_password"
  email_use_ssl="$POST_email_use_ssl"
  email_trust_cert="$POST_email_trust_cert"
  email_from_name="$POST_email_from_name"
  email_from_address="$POST_email_from_address"
  email_to_name="$POST_email_to_name"
  email_to_address="$POST_email_to_address"
  email_subject="$POST_email_subject"
  email_body="$POST_email_body"
  email_send_photo="$POST_email_send_photo"
  email_send_video="$POST_email_send_video"

  email_body="$(echo "$email_body" | tr "\r\n" " ")"

  error_if_empty "$email_host" "SMTP host cannot be empty."
  error_if_empty "$email_from_address" "Sender email address cannot be empty."
  error_if_empty "$email_from_name" "Sender name cannot be empty."
  error_if_empty "$email_to_address" "Recipient email address cannot be empty."
  error_if_empty "$email_to_name" "Recipient name cannot be empty."

  email_defaults

  if [ -z "$error" ]; then
    set_value_for email host "$email_host"
    set_value_for email port "$email_port"
    set_value_for email username "$email_username"
    set_value_for email password "$email_password"
    set_value_for email use_ssl "$email_use_ssl"
    set_value_for email trust_cert "$email_trust_cert"
    set_value_for email from_name "$email_from_name"
    set_value_for email from_address "$email_from_address"
    set_value_for email to_name "$email_to_name"
    set_value_for email to_address "$email_to_address"
    set_value_for email subject "$email_subject"
    set_value_for email body "$email_body"
    set_value_for email send_photo "$email_send_photo"
    set_value_for email send_video "$email_send_video"

    import_domain_config email
    redirect_to "$SCRIPT_NAME?tab=$active_tab" "success" "Email settings updated."
  else
    redirect_to "$SCRIPT_NAME?tab=$active_tab" "danger" "Please fix the highlighted errors."
  fi
}

########################################
# FTP
########################################
ftp_defaults() {
  default_for ftp_port "21"
  default_for ftp_template "${network_hostname}-%Y%m%d-%H%M%S"
  default_for ftp_send_video "false"
  default_for ftp_send_photo "false"

  [ -z "$ftp_username" ] && ftp_username="anonymous" && ftp_password="anonymous"
}

ftp_read_config() {
  [ -f "$config_file" ] || return

  ftp_host=$(get_value_for ftp host)
  ftp_port=$(get_value_for ftp port)
  ftp_username=$(get_value_for ftp username)
  ftp_password=$(get_value_for ftp password)
  ftp_path=$(get_value_for ftp path)
  ftp_template=$(get_value_for ftp template)
  ftp_send_photo=$(get_value_for ftp send_photo)
  ftp_send_video=$(get_value_for ftp send_video)
}

ftp_handle_submit() {
  error=""
  ftp_host="$POST_ftp_host"
  ftp_port="$POST_ftp_port"
  ftp_username="$POST_ftp_username"
  ftp_password="$POST_ftp_password"
  ftp_path="$POST_ftp_path"
  ftp_template="$POST_ftp_template"
  ftp_send_photo="$POST_ftp_send_photo"
  ftp_send_video="$POST_ftp_send_video"

  ftp_defaults

  if [ -z "$error" ]; then
    set_value_for ftp host "$ftp_host"
    set_value_for ftp port "$ftp_port"
    set_value_for ftp username "$ftp_username"
    set_value_for ftp password "$ftp_password"
    set_value_for ftp path "$ftp_path"
    set_value_for ftp template "$ftp_template"
    set_value_for ftp send_photo "$ftp_send_photo"
    set_value_for ftp send_video "$ftp_send_video"

    import_domain_config ftp
    redirect_to "$SCRIPT_NAME?tab=$active_tab" "success" "FTP settings updated."
  else
    redirect_to "$SCRIPT_NAME?tab=$active_tab" "danger" "Please fix the highlighted errors."
  fi
}

########################################
# MQTT
########################################
mqtt_defaults() {
  default_for mqtt_client_id "$camera_id"
  default_for mqtt_port "1883"
  default_for mqtt_topic "thingino/$mqtt_client_id"
  default_for mqtt_message "{\"camera_id\": \"$camera_id\", \"timestamp\": \"%s\"}"
  default_for mqtt_send_photo "false"
  default_for mqtt_send_video "false"
  default_for mqtt_use_ssl "false"
}

mqtt_read_config() {
  [ -f "$config_file" ] || return

  mqtt_host=$(get_value_for mqtt host)
  mqtt_message=$(get_value_for mqtt message)
  mqtt_password=$(get_value_for mqtt password)
  mqtt_port=$(get_value_for mqtt port)
  mqtt_send_photo=$(get_value_for mqtt send_photo)
  mqtt_send_video=$(get_value_for mqtt send_video)
  mqtt_topic=$(get_value_for mqtt topic)
  mqtt_topic_photo=$(get_value_for mqtt topic_photo)
  mqtt_topic_video=$(get_value_for mqtt topic_video)
  mqtt_use_ssl=$(get_value_for mqtt use_ssl)
  mqtt_username=$(get_value_for mqtt username)
  mqtt_client_id=$(get_value_for mqtt client_id)
}

mqtt_handle_submit() {
  error=""
  mqtt_client_id="$POST_mqtt_client_id"
  mqtt_host="$POST_mqtt_host"
  mqtt_message="$POST_mqtt_message"
  mqtt_password="$POST_mqtt_password"
  mqtt_port="$POST_mqtt_port"
  mqtt_send_photo="$POST_mqtt_send_photo"
  mqtt_send_video="$POST_mqtt_send_video"
  mqtt_topic="$POST_mqtt_topic"
  mqtt_topic_photo="$POST_mqtt_topic_photo"
  mqtt_topic_video="$POST_mqtt_topic_video"
  mqtt_use_ssl="$POST_mqtt_use_ssl"
  mqtt_username="$POST_mqtt_username"

  if [ "false" = "$mqtt_available" ]; then
    set_error_flag "MQTT client is not a part of your firmware."
  fi

  error_if_empty "$mqtt_host" "MQTT broker host cannot be empty."
  error_if_empty "$mqtt_port" "MQTT port cannot be empty."
  error_if_empty "$mqtt_topic" "MQTT topic cannot be empty."
  error_if_empty "$mqtt_message" "MQTT message cannot be empty."

  if [ "${mqtt_topic:0:1}" = "/" ] || [ "${mqtt_topic_photo:0:1}" = "/" ]; then
    set_error_flag "MQTT topic should not start with a slash."
  fi

  if [ "$mqtt_topic" != "${mqtt_topic// /}" ] || [ "$mqtt_topic_photo" != "${mqtt_topic_photo// /}" ]; then
    set_error_flag "MQTT topic should not contain spaces."
  fi

  if [ -n "$(echo $mqtt_topic | sed -r -n /[^a-zA-Z0-9/_-]/p)" ] || \
     [ -n "$(echo $mqtt_topic_photo | sed -r -n /[^a-zA-Z0-9/_-]/p)" ]; then
    set_error_flag "MQTT topic should not include non-ASCII or special characters like /, #, +."
  fi

  if [ "true" = "$mqtt_send_photo" ] && [ -z "$mqtt_topic_photo" ]; then
    set_error_flag "MQTT topic for snapshot should not be empty."
  fi

  mqtt_defaults

  if [ -z "$error" ]; then
    set_value_for mqtt host "$mqtt_host"
    set_value_for mqtt port "$mqtt_port"
    set_value_for mqtt username "$mqtt_username"
    set_value_for mqtt password "$mqtt_password"
    set_value_for mqtt client_id "$mqtt_client_id"
    set_value_for mqtt topic "$mqtt_topic"
    set_value_for mqtt message "$mqtt_message"
    set_value_for mqtt use_ssl "$mqtt_use_ssl"
    set_value_for mqtt send_photo "$mqtt_send_photo"
    set_value_for mqtt send_video "$mqtt_send_video"
    set_value_for mqtt topic_photo "$mqtt_topic_photo"
    set_value_for mqtt topic_video "$mqtt_topic_video"

    import_domain_config mqtt
    redirect_to "$SCRIPT_NAME?tab=$active_tab" "success" "MQTT settings updated."
  else
    redirect_to "$SCRIPT_NAME?tab=$active_tab" "danger" "Please fix the highlighted errors."
  fi
}

########################################
# Ntfy
########################################
ntfy_defaults() {
  default_for ntfy_host "ntfy.sh"
  default_for ntfy_port "80"
  default_for ntfy_topic "$camera_id"
  default_for ntfy_message "{\"camera_id\": \"$camera_id\", \"timestamp\": \"%s\"}"
  default_for ntfy_tags "[]"
  default_for ntfy_send_photo "false"
  default_for ntfy_send_video "false"
  default_for ntfy_use_ssl "false"
}

ntfy_read_config() {
  [ -f "$config_file" ] || return

  ntfy_actions=$(get_value_for ntfy actions)
  ntfy_attach=$(get_value_for ntfy attach)
  ntfy_call=$(get_value_for ntfy call)
  ntfy_click=$(get_value_for ntfy click)
  ntfy_delay=$(get_value_for ntfy delay)
  ntfy_email=$(get_value_for ntfy email)
  ntfy_filename=$(get_value_for ntfy filename)
  ntfy_host=$(get_value_for ntfy host)
  ntfy_icon=$(get_value_for ntfy icon)
  ntfy_message=$(get_value_for ntfy message)
  ntfy_password=$(get_value_for ntfy password)
  ntfy_port=$(get_value_for ntfy port)
  ntfy_priority=$(get_value_for ntfy priority)
  ntfy_send_photo=$(get_value_for ntfy send_photo)
  ntfy_send_video=$(get_value_for ntfy send_video)
  ntfy_tags=$(get_value_for ntfy tags)
  ntfy_title=$(get_value_for ntfy title)
  ntfy_token=$(get_value_for ntfy token)
  ntfy_topic=$(get_value_for ntfy topic)
  ntfy_twilio_token=$(get_value_for ntfy twilio_token)
  ntfy_username=$(get_value_for ntfy username)
  ntfy_use_ssl=$(get_value_for ntfy use_ssl)
}

ntfy_handle_submit() {
  error=""
  ntfy_host="$POST_ntfy_host"
  ntfy_message="$POST_ntfy_message"
  ntfy_port="$POST_ntfy_port"
  ntfy_password="$POST_ntfy_password"
  ntfy_send_photo="$POST_ntfy_send_photo"
  ntfy_send_video="$POST_ntfy_send_video"
  ntfy_title="$POST_ntfy_title"
  ntfy_token="$POST_ntfy_token"
  ntfy_topic="$POST_ntfy_topic"
  ntfy_username="$POST_ntfy_username"
  ntfy_use_ssl="$POST_ntfy_use_ssl"

  error_if_empty "$ntfy_topic" "Ntfy topic cannot be empty."
  error_if_empty "$ntfy_message" "Ntfy message cannot be empty."

  if [ -n "$(echo $ntfy_topic | sed -r -n /[^-_a-zA-Z0-9]/p)" ]; then
    set_error_flag "Ntfy topic should not include non-ASCII or special characters like /, #, +, or space."
  fi

  if [ ${#ntfy_topic} -gt 64 ]; then
    set_error_flag "Ntfy topic should not exceed 64 characters."
  fi

  ntfy_defaults

  if [ -z "$error" ]; then
    set_value_for ntfy host "$ntfy_host"
    set_value_for ntfy message "$ntfy_message"
    set_value_for ntfy password "$ntfy_password"
    set_value_for ntfy port "$ntfy_port"
    set_value_for ntfy send_photo "$ntfy_send_photo"
    set_value_for ntfy send_video "$ntfy_send_video"
    set_value_for ntfy title "$ntfy_title"
    set_value_for ntfy token "$ntfy_token"
    set_value_for ntfy topic "$ntfy_topic"
    set_value_for ntfy username "$ntfy_username"
    set_value_for ntfy use_ssl "$ntfy_use_ssl"

    import_domain_config ntfy
    redirect_to "$SCRIPT_NAME?tab=$active_tab" "success" "Ntfy settings updated."
  else
    redirect_to "$SCRIPT_NAME?tab=$active_tab" "danger" "Please fix the highlighted errors."
  fi
}

########################################
# Storage
########################################
storage_defaults() {
  default_for storage_template "${network_hostname}-%Y%m%d-%H%M%S"
  default_for storage_send_photo "false"
  default_for storage_send_video "false"
}

storage_read_config() {
  [ -f "$config_file" ] || return

  storage_mount=$(get_value_for storage mount)
  storage_device_path=$(get_value_for storage device_path)
  storage_template=$(get_value_for storage template)
  storage_send_photo=$(get_value_for storage send_photo)
  storage_send_video=$(get_value_for storage send_video)
}

storage_handle_submit() {
  error=""
  storage_mount="$POST_storage_mount"
  storage_device_path="$POST_storage_device_path"
  storage_template="$POST_storage_template"
  storage_send_photo="$POST_storage_send_photo"
  storage_send_video="$POST_storage_send_video"

  error_if_empty "$storage_mount" "Mount point cannot be empty."
  error_if_empty "$storage_template" "Filename template cannot be empty."

  storage_defaults

  if [ -z "$error" ]; then
    set_value_for storage mount "$storage_mount"
    set_value_for storage device_path "$storage_device_path"
    set_value_for storage template "$storage_template"
    set_value_for storage send_photo "$storage_send_photo"
    set_value_for storage send_video "$storage_send_video"

    import_domain_config storage
    redirect_to "$SCRIPT_NAME?tab=$active_tab" "success" "Storage settings updated."
  else
    redirect_to "$SCRIPT_NAME?tab=$active_tab" "danger" "Please fix the highlighted errors."
  fi
}

########################################
# Telegram
########################################
telegram_defaults() {
  default_for telegram_caption "%hostname, %datetime"
  default_for telegram_send_photo "false"
  default_for telegram_send_video "false"
}

telegram_read_config() {
  [ -f "$config_file" ] || return

  telegram_token=$(get_value_for telegram token)
  telegram_channel=$(get_value_for telegram channel)
  telegram_caption=$(get_value_for telegram caption)
  telegram_send_photo=$(get_value_for telegram send_photo)
  telegram_send_video=$(get_value_for telegram send_video)
}

telegram_handle_submit() {
  error=""
  telegram_token="$POST_telegram_token"
  telegram_channel="$POST_telegram_channel"
  telegram_caption="$POST_telegram_caption"
  telegram_send_photo="$POST_telegram_send_photo"
  telegram_send_video="$POST_telegram_send_video"

  error_if_empty "$telegram_token" "Telegram token cannot be empty."
  error_if_empty "$telegram_channel" "Telegram channel cannot be empty."

  telegram_defaults

  if [ -z "$error" ]; then
    set_value_for telegram token "$telegram_token"
    set_value_for telegram channel "$telegram_channel"
    set_value_for telegram caption "$telegram_caption"
    set_value_for telegram send_photo "$telegram_send_photo"
    set_value_for telegram send_video "$telegram_send_video"

    import_domain_config telegram
    redirect_to "$SCRIPT_NAME?tab=$active_tab" "success" "Telegram settings updated."
  else
    redirect_to "$SCRIPT_NAME?tab=$active_tab" "danger" "Please fix the highlighted errors."
  fi
}

########################################
# Webhook
########################################
webhook_defaults() {
  default_for webhook_send_photo "true"
  default_for webhook_send_video "false"
}

webhook_read_config() {
  [ -f "$config_file" ] || return

  webhook_url=$(get_value_for webhook url)
  webhook_message=$(get_value_for webhook message)
  webhook_send_photo=$(get_value_for webhook send_photo)
  webhook_send_video=$(get_value_for webhook send_video)
}

webhook_handle_submit() {
  error=""
  webhook_url="$POST_webhook_url"
  webhook_message="$POST_webhook_message"
  webhook_send_photo="$POST_webhook_send_photo"
  webhook_send_video="$POST_webhook_send_video"

  error_if_empty "$webhook_url" "Webhook URL cannot be empty."

  webhook_defaults

  if [ -z "$error" ]; then
    set_value_for webhook url "$webhook_url"
    set_value_for webhook message "$webhook_message"
    set_value_for webhook send_photo "$webhook_send_photo"
    set_value_for webhook send_video "$webhook_send_video"

    import_domain_config webhook
    redirect_to "$SCRIPT_NAME?tab=$active_tab" "success" "Webhook settings updated."
  else
    redirect_to "$SCRIPT_NAME?tab=$active_tab" "danger" "Please fix the highlighted errors."
  fi
}

########################################
# POST handling
########################################
if [ "POST" = "$REQUEST_METHOD" ]; then
  case "$POST_domain" in
    email) email_handle_submit ;;
    ftp) ftp_handle_submit ;;
    mqtt) mqtt_handle_submit ;;
    ntfy) ntfy_handle_submit ;;
    storage) storage_handle_submit ;;
    telegram) telegram_handle_submit ;;
    webhook) webhook_handle_submit ;;
  esac
fi

# Load config values for rendering
read_motion_config
read_motion_runtime

send2_json=$(jct "$config_file" print 2>/dev/null)
[ -n "$send2_json" ] || send2_json='{}'
motion_json=$(jct /etc/prudynt.json get motion 2>/dev/null)
[ -n "$motion_json" ] || motion_json='{}'
%>
<%in _header.cgi %>

<p>Configure where snapshots and video clips are delivered. Each tab stores its settings independently.</p>

<script id="send2-config-json" type="application/json"><%= $send2_json %></script>
<script id="motion-config-json" type="application/json"><%= $motion_json %></script>

<ul class="nav nav-tabs mb-3" id="send2-tabs" role="tablist">
<li class="nav-item" role="presentation">
<button class="nav-link<% [ "$active_tab" = "summary" ] && echo -n ' active' %>" id="tab-summary" data-tab="summary" data-bs-toggle="tab" data-bs-target="#pane-summary" type="button" role="tab" aria-controls="pane-summary" aria-selected="<% [ "$active_tab" = "summary" ] && echo -n 'true' || echo -n 'false' %>">Overview</button>
</li>
<li class="nav-item" role="presentation">
<button class="nav-link<% [ "$active_tab" = "email" ] && echo -n ' active' %>" id="tab-email" data-tab="email" data-bs-toggle="tab" data-bs-target="#pane-email" type="button" role="tab" aria-controls="pane-email" aria-selected="<% [ "$active_tab" = "email" ] && echo -n 'true' || echo -n 'false' %>">Email</button>
</li>
<li class="nav-item" role="presentation">
<button class="nav-link<% [ "$active_tab" = "ftp" ] && echo -n ' active' %>" id="tab-ftp" data-tab="ftp" data-bs-toggle="tab" data-bs-target="#pane-ftp" type="button" role="tab" aria-controls="pane-ftp" aria-selected="<% [ "$active_tab" = "ftp" ] && echo -n 'true' || echo -n 'false' %>">FTP</button>
</li>
<li class="nav-item" role="presentation">
<button class="nav-link<% [ "$active_tab" = "mqtt" ] && echo -n ' active' %>" id="tab-mqtt" data-tab="mqtt" data-bs-toggle="tab" data-bs-target="#pane-mqtt" type="button" role="tab" aria-controls="pane-mqtt" aria-selected="<% [ "$active_tab" = "mqtt" ] && echo -n 'true' || echo -n 'false' %>">MQTT</button>
</li>
<li class="nav-item" role="presentation">
<button class="nav-link<% [ "$active_tab" = "ntfy" ] && echo -n ' active' %>" id="tab-ntfy" data-tab="ntfy" data-bs-toggle="tab" data-bs-target="#pane-ntfy" type="button" role="tab" aria-controls="pane-ntfy" aria-selected="<% [ "$active_tab" = "ntfy" ] && echo -n 'true' || echo -n 'false' %>">Ntfy</button>
</li>
<li class="nav-item" role="presentation">
<button class="nav-link<% [ "$active_tab" = "storage" ] && echo -n ' active' %>" id="tab-storage" data-tab="storage" data-bs-toggle="tab" data-bs-target="#pane-storage" type="button" role="tab" aria-controls="pane-storage" aria-selected="<% [ "$active_tab" = "storage" ] && echo -n 'true' || echo -n 'false' %>">Storage</button>
</li>
<li class="nav-item" role="presentation">
<button class="nav-link<% [ "$active_tab" = "telegram" ] && echo -n ' active' %>" id="tab-telegram" data-tab="telegram" data-bs-toggle="tab" data-bs-target="#pane-telegram" type="button" role="tab" aria-controls="pane-telegram" aria-selected="<% [ "$active_tab" = "telegram" ] && echo -n 'true' || echo -n 'false' %>">Telegram</button>
</li>
<li class="nav-item" role="presentation">
<button class="nav-link<% [ "$active_tab" = "webhook" ] && echo -n ' active' %>" id="tab-webhook" data-tab="webhook" data-bs-toggle="tab" data-bs-target="#pane-webhook" type="button" role="tab" aria-controls="pane-webhook" aria-selected="<% [ "$active_tab" = "webhook" ] && echo -n 'true' || echo -n 'false' %>">Webhook</button>
</li>
</ul>

<div class="tab-content" id="send2-content">

<div class="tab-pane fade<% [ "$active_tab" = "summary" ] && echo -n ' show active' %>" id="pane-summary" role="tabpanel" aria-labelledby="tab-summary">
<div class="row g-3">
<div class="col-12 col-lg-4">
<div class="card h-100">
<div class="card-header">
<div class="d-flex flex-wrap align-items-center justify-content-between gap-2">
<span>Motion detection</span>
<div class="d-flex align-items-center gap-2 flex-wrap">
<span class="form-check form-switch m-0"><input class="form-check-input" type="checkbox" id="motion_enabled" <% checked_if_true "$motion_enabled" %>> start on boot</span>
</div>
</div>
</div>
<div class="card-body">
<label for="motion_sensitivity" class="form-label">Sensitivity</label>
<input type="range" class="form-range" id="motion_sensitivity" min="1" max="8" step="1" value="<%= $motion_sensitivity %>">
<label for="motion_cooldown_time" class="form-label">Delay between alerts (sec)</label>
<input type="range" class="form-range" id="motion_cooldown_time" min="5" max="60" step="1" value="<%= $motion_cooldown_time %>">

<div class="mt-3">
<button type="button" class="btn btn-outline-secondary d-flex align-items-center gap-2" id="motion-runtime-toggle" disabled>
<span class="spinner-border spinner-border-sm d-none" role="status" aria-hidden="true" id="motion-runtime-spinner"></span>
<span id="motion-runtime-label">Checking...</span>
</button>
</div>

<div class="alert alert-info mt-3">
<p>Motion events detected by the streamer trigger <code>/sbin/motion</code> script which sends alerts through the selected and preconfigured notification channels.</p>
<% wiki_page "Plugin:-Motion-Guard" %>
</div>

<div class="text-secondary small">Configured values are saved immediately.</div>
</div>
</div>
</div>

<div class="col-12 col-lg-8">
<div class="card h-100">
<div class="card-header d-flex align-items-center justify-content-between">
<span>Send motion alerts to</span>
</div>
<div class="card-body">
<div class="table-responsive">
<table class="table align-middle">
<thead>
<tr>
<th scope="col">Service</th>
<th scope="col">On motion</th>
<th scope="col">Send photo</th>
<th scope="col">Send video</th>
<th scope="col">Test</th>
</tr>
</thead>
<tbody>
<tr>
<td>Email</td>
<td>
<span class="form-check form-switch m-0">
<input class="form-check-input motion-sendto" type="checkbox" id="motion_send2email" data-target="send2email">
</span>
</td>
<td><span id="status-email-photo" class="text-secondary">…</span></td>
<td><span id="status-email-video" class="text-secondary">…</span></td>
<td><button type="button" class="btn border btn-sm" title="Send to email" data-sendto="email" data-sendto-bypass="1">Test</button></td>
</tr>
<tr>
<td>FTP</td>
<td>
<span class="form-check form-switch m-0">
<input class="form-check-input motion-sendto" type="checkbox" id="motion_send2ftp" data-target="send2ftp">
</span>
</td>
<td><span id="status-ftp-photo" class="text-secondary">…</span></td>
<td><span id="status-ftp-video" class="text-secondary">…</span></td>
<td><button type="button" class="btn border btn-sm" title="Send to FTP" data-sendto="ftp" data-sendto-bypass="1">Test</button></td>
</tr>
<tr>
<td>MQTT</td>
<td>
<span class="form-check form-switch m-0">
<input class="form-check-input motion-sendto" type="checkbox" id="motion_send2mqtt" data-target="send2mqtt">
</span>
</td>
<td><span id="status-mqtt-photo" class="text-secondary">…</span></td>
<td><span id="status-mqtt-video" class="text-secondary">…</span></td>
<td><button type="button" class="btn border btn-sm" title="Send to MQTT" data-sendto="mqtt" data-sendto-bypass="1">Test</button></td>
</tr>
<tr>
<td>Ntfy</td>
<td>
<span class="form-check form-switch m-0">
<input class="form-check-input motion-sendto" type="checkbox" id="motion_send2ntfy" data-target="send2ntfy">
</span>
</td>
<td><span id="status-ntfy-photo" class="text-secondary">…</span></td>
<td><span id="status-ntfy-video" class="text-secondary">…</span></td>
<td><button type="button" class="btn border btn-sm" title="Send to Ntfy" data-sendto="ntfy" data-sendto-bypass="1">Test</button></td>
</tr>
<tr>
<td>Storage</td>
<td>
<span class="form-check form-switch m-0">
<input class="form-check-input motion-sendto" type="checkbox" id="motion_send2storage" data-target="send2storage">
</span>
</td>
<td><span id="status-storage-photo" class="text-secondary">…</span></td>
<td><span id="status-storage-video" class="text-secondary">…</span></td>
<td><button type="button" class="btn border btn-sm" title="Send to Storage" data-sendto="storage" data-sendto-bypass="1">Test</button></td>
</tr>
<tr>
<td>Telegram</td>
<td>
<span class="form-check form-switch m-0">
<input class="form-check-input motion-sendto" type="checkbox" id="motion_send2telegram" data-target="send2telegram">
</span>
</td>
<td><span id="status-telegram-photo" class="text-secondary">…</span></td>
<td><span id="status-telegram-video" class="text-secondary">…</span></td>
<td><button type="button" class="btn border btn-sm" title="Send to Telegram" data-sendto="telegram" data-sendto-bypass="1">Test</button></td>
</tr>
<tr>
<td>Webhook</td>
<td>
<span class="form-check form-switch m-0">
<input class="form-check-input motion-sendto" type="checkbox" id="motion_send2webhook" data-target="send2webhook">
</span>
</td>
<td><span id="status-webhook-photo" class="text-secondary">…</span></td>
<td><span id="status-webhook-video" class="text-secondary">…</span></td>
<td><button type="button" class="btn border btn-sm" title="Send to Webhook" data-sendto="webhook" data-sendto-bypass="1">Test</button></td>
</tr>
</tbody>
</table>
</div>
</div>
</div>
</div>
</div>
<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct /etc/prudynt.json get motion" %>
<% ex "jct /etc/thingino.json get motion" %>
</div>
</div>

<div class="modal fade" id="send2-test-modal" tabindex="-1" aria-hidden="true">
<div class="modal-dialog modal-xl  modal-dialog-centered modal-dialog-scrollable">
<div class="modal-content">
<div class="modal-header">
<h5 class="modal-title" id="send2-test-title">Send test</h5>
<button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
</div>
<div class="modal-body">
<pre class="small bg-body-secondary p-3 rounded" id="send2-test-output" style="white-space: break-spaces">(no output yet)</pre>
</div>
<div class="modal-footer">
<button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
</div>
</div>
</div>
</div>

<div class="tab-pane fade<% [ "$active_tab" = "email" ] && echo -n ' show active' %>" id="pane-email" role="tabpanel" aria-labelledby="tab-email">
<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<input type="hidden" name="tab" value="email">
<input type="hidden" name="domain" value="email">
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3 g-4 mb-4">
<div class="col">
<div class="row g-1">
<div class="col-10"><% field_text "email_host" "SMTP server FQDN or IP address" %></div>
<div class="col-2"><% field_text "email_port" "Port" %></div>
</div>
<% field_text "email_username" "SMTP username" %>
<% field_password "email_password" "SMTP password" %>
<% field_switch "email_use_ssl" "Use TLS/SSL" %>
<% field_switch "email_trust_cert" "Ignore SSL certificate validity" %>
</div>
<div class="col">
<% field_text "email_from_name" "Sender's name" %>
<% field_text "email_from_address" "Sender's address" %>
<% field_text "email_to_name" "Recipient's name" %>
<% field_text "email_to_address" "Recipient's address" %>
</div>
<div class="col">
<% field_switch "email_send_photo" "Send snapshot" %>
<% field_switch "email_send_video" "Send video" %>
<% field_text "email_subject" "Email subject" %>
<% field_textarea "email_body" "Email text" "Line breaks will be replaced with whitespaces" %>
</div>
</div>
<% button_submit %>
</form>
<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get email" %>
</div>
</div>

<div class="tab-pane fade<% [ "$active_tab" = "ftp" ] && echo -n ' show active' %>" id="pane-ftp" role="tabpanel" aria-labelledby="tab-ftp">
<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<input type="hidden" name="tab" value="ftp">
<input type="hidden" name="domain" value="ftp">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3">
<div class="col">
<div class="row g-1">
<div class="col-10"><% field_text "ftp_host" "FTP server FQDN or IP address" %></div>
<div class="col-2"><% field_text "ftp_port" "Port" %></div>
</div>
<% field_text "ftp_username" " FTP username" %>
<% field_password "ftp_password" "FTP password" %>
</div>
<div class="col">
<% field_text "ftp_path" "Path on FTP server" "$STR_SUPPORTS_STRFTIME. Relative to FTP root directory" %>
<% field_text "ftp_template" "Filename template" "$STR_SUPPORTS_STRFTIME. Do not use extension" %>
</div>
<div class="col">
<% field_switch "ftp_send_photo" "Send photo" %>
<% field_switch "ftp_send_video" "Send video" %>
</div>
</div>
<% button_submit %>
</form>
<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get ftp" %>
</div>
</div>

<div class="tab-pane fade<% [ "$active_tab" = "mqtt" ] && echo -n ' show active' %>" id="pane-mqtt" role="tabpanel" aria-labelledby="tab-mqtt">
<% if [ "false" = "$mqtt_available" ]; then %>
    <div class="alert alert-warning">MQTT client is not a part of your firmware. Install mosquitto_pub to enable this integration.</div>
<% fi %>
<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<input type="hidden" name="tab" value="mqtt">
<input type="hidden" name="domain" value="mqtt">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3">
<div class="col">
<% field_text "mqtt_client_id" "MQTT client ID" %>
<div class="row g-1">
<div class="col-10"><% field_text "mqtt_host" "MQTT broker FQDN or IP address" %></div>
<div class="col-2"><% field_text "mqtt_port" "Port" %></div>
</div>
<% field_text "mqtt_username" "MQTT broker username" %>
<% field_password "mqtt_password" "MQTT broker password" %>
<% field_switch "mqtt_use_ssl" "Use SSL" %>
</div>
<div class="col">
<% field_text "mqtt_topic" "MQTT topic" %>
<% field_textarea "mqtt_message" "MQTT message" "$STR_SUPPORTS_STRFTIME" %>
</div>
<div class="col">
<% field_switch "mqtt_send_photo" "Send photo" %>
<% field_text "mqtt_topic_photo" "MQTT topic to send the photo to" %>
<% field_switch "mqtt_send_video" "Send video" %>
<% field_text "mqtt_topic_video" "MQTT topic to send the video to" %>
</div>
</div>
<% button_submit %>
</form>
<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get mqtt" %>
</div>
</div>

<div class="tab-pane fade<% [ "$active_tab" = "ntfy" ] && echo -n ' show active' %>" id="pane-ntfy" role="tabpanel" aria-labelledby="tab-ntfy">
<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<input type="hidden" name="tab" value="ntfy">
<input type="hidden" name="domain" value="ntfy">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3">
<div class="col">
<div class="row g-1">
<div class="col-10"><% field_text "ntfy_host" "Ntfy server FQDN or IP address"  "Defaults to <a href=\"https://ntfy.sh/\" target=\"_blank\">ntfy.sh</a>" %></div>
<div class="col-2"><% field_text "ntfy_port" "Port" %></div>
</div>
<% field_text "ntfy_username" "Ntfy username" %>
<% field_password "ntfy_password" "Ntfy password" %>
<% field_text "ntfy_token" "Ntfy token" %>
<% field_switch "ntfy_use_ssl" "Use SSL" %>
</div>
<div class="col">
<% field_text "ntfy_topic" "Ntfy topic" %>
<% field_text "ntfy_title" "Ntfy title" %>
<% field_textarea "ntfy_message" "Ntfy message" "$STR_SUPPORTS_STRFTIME" %>
</div>
<div class="col">
<% field_switch "ntfy_send_photo" "Send photo" %>
<% field_switch "ntfy_send_video" "Send video" %>
</div>
</div>
<% button_submit %>
</form>
<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get ntfy" %>
</div>
</div>

<div class="tab-pane fade<% [ "$active_tab" = "storage" ] && echo -n ' show active' %>" id="pane-storage" role="tabpanel" aria-labelledby="tab-storage">
<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<input type="hidden" name="tab" value="storage">
<input type="hidden" name="domain" value="storage">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3">
<div class="col">
<% field_select "storage_mount" "Storage mount point" "$MOUNTS" "SD card or network share" %>
<% field_text "storage_device_path" "Device-specific path" "Subdirectory within mount point (optional)" %>
</div>
<div class="col">
<% field_text "storage_template" "Filename template" "$STR_SUPPORTS_STRFTIME" "do not use extension" %>
<p class="label">Media to save</p>
</div>
<div class="col">
<% field_switch "storage_send_photo" "Send photo" %>
<% field_switch "storage_send_video" "Send video" %>
<div class="alert alert-info">
<p>Save snapshots and video clips to a mounted storage device (SD card or network share).</p>
<p class="small mb-0">The mount point must be writable. Files will be saved with automatic .jpg or .mp4 extension.</p>
</div>
</div>
</div>
<% button_submit %>
</form>
<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get storage" %>
</div>
</div>

<div class="tab-pane fade<% [ "$active_tab" = "telegram" ] && echo -n ' show active' %>" id="pane-telegram" role="tabpanel" aria-labelledby="tab-telegram">
<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<input type="hidden" name="tab" value="telegram">
<input type="hidden" name="domain" value="telegram">
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<% field_text "telegram_token" "Telegram Bot Token" %>
<% field_text "telegram_channel" "Chat ID" "ID of the channel to post images to." "-100xxxxxxxxxxxx" %>
</div>
<div class="col">
<% field_text "telegram_caption" "Photo caption" "Available variables: %hostname, %datetime" %>
</div>
<div class="col">
<% field_switch "telegram_send_photo" "Send photo" %>
<% field_switch "telegram_send_video" "Send video" %>
</div>
<div class="col">
<button type="button" class="btn" data-bs-toggle="modal" data-bs-target="#helpModal">Help</button>
<%in _tg_bot.cgi %>
</div>
</div>
<% button_submit %>
</form>
<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get telegram" %>
</div>
</div>

<div class="tab-pane fade<% [ "$active_tab" = "webhook" ] && echo -n ' show active' %>" id="pane-webhook" role="tabpanel" aria-labelledby="tab-webhook">
<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<input type="hidden" name="tab" value="webhook">
<input type="hidden" name="domain" value="webhook">
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<% field_text "webhook_url" "Webhook URL" %>
</div>
<div class="col">
<% field_textarea "webhook_message" "Message" %>
</div>
<div class="col">
<% field_switch "webhook_send_photo" "Send photo" %>
<% field_switch "webhook_send_video" "Send video" %>
</div>
</div>
<% button_submit %>
</form>
<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get webhook" %>
</div>
</div>

</div>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file print" %>
</div>

<script>
(() => {
  // Preserve active tab in URL and form submissions
  $$('#send2-tabs button[data-tab]').forEach(btn => {
    btn.addEventListener('shown.bs.tab', ev => {
      const tab = ev.target.dataset.tab;
      const url = new URL(window.location.href);
      url.searchParams.set('tab', tab);
      history.replaceState({}, '', url);
      $$('input[name="tab"]').forEach(hidden => hidden.value = tab);
    });
  });

  // Update File Manager link based on selected mount
  const fmLink = $('#storage-link-fm');
  const storageMount = $('#storage_mount');
  if (fmLink && storageMount) {
    fmLink.addEventListener('click', ev => {
      fmLink.href = 'tool-file-manager.cgi?cd=' + storageMount.value;
    });
  }

  // Helpers to toggle ports on SSL switches
  const syncPort = (checkboxId, portId, plainPort, sslPort) => {
    const toggle = document.getElementById(checkboxId);
    const port = document.getElementById(portId);
    if (!toggle || !port) return;
    toggle.addEventListener('change', ev => {
      if (ev.target.checked && port.value === plainPort) port.value = sslPort;
      if (!ev.target.checked && port.value === sslPort) port.value = plainPort;
    });
  };

    const motionEndpoint  = '/x/json-motion.cgi';
    const prudyntEndpoint = '/x/json-prudynt.cgi';
    let motionRuntimeEnabled = null;

    const runtimeButton = document.getElementById('motion-runtime-toggle');
    const runtimeLabel = document.getElementById('motion-runtime-label');
    const runtimeSpinner = document.getElementById('motion-runtime-spinner');

    const setMotionRuntimeBusy = isBusy => {
      if (!runtimeButton || !runtimeSpinner) return;
      runtimeButton.disabled = isBusy;
      runtimeSpinner.classList.toggle('d-none', !isBusy);
    };

    const setMotionRuntimeUi = enabled => {
      if (!runtimeButton || !runtimeLabel) return;
      motionRuntimeEnabled = enabled === true;
      if (motionRuntimeEnabled) {
        runtimeLabel.textContent = 'Running (tap to stop)';
        runtimeButton.className = 'btn btn-outline-success d-flex align-items-center gap-2';
      } else {
        runtimeLabel.textContent = 'Stopped (tap to start)';
        runtimeButton.className = 'btn btn-outline-secondary d-flex align-items-center gap-2';
      }
      setMotionRuntimeBusy(false);
    };

    const setMotionRuntimeError = () => {
      if (!runtimeButton || !runtimeLabel) return;
      runtimeLabel.textContent = 'Unknown (retry)';
      runtimeButton.className = 'btn btn-outline-warning d-flex align-items-center gap-2';
      setMotionRuntimeBusy(false);
    };

    const loadMotionRuntime = () => {
      setMotionRuntimeBusy(true);
      fetch(prudyntEndpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{"motion":{"enabled":null}}'
      })
        .then(res => res.json())
        .then(data => {
          if (data.motion && data.motion.enabled !== undefined) {
            setMotionRuntimeUi(data.motion.enabled);
          } else {
            throw new Error('Unexpected response');
          }
        })
        .catch(err => {
          console.error('Failed to load motion runtime', err);
          setMotionRuntimeError();
        });
    };

    const toggleMotionRuntime = () => {
      const nextState = motionRuntimeEnabled === null ? true : !motionRuntimeEnabled;
      setMotionRuntimeBusy(true);
      fetch(prudyntEndpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ motion: { enabled: nextState } })
      })
        .then(res => res.json())
        .then(data => {
          if (data.motion && data.motion.enabled !== undefined) {
            setMotionRuntimeUi(data.motion.enabled);
          } else {
            throw new Error('Unexpected response');
          }
        })
        .catch(err => {
          console.error('Failed to toggle motion runtime', err);
          setMotionRuntimeError();
        });
    };

    const sendMotionValue = (target, value) => {
      const qs = new URLSearchParams({ target, state: value }).toString();
      fetch(`${motionEndpoint}?${qs}`)
        .then(res => res.json())
        .then(data => console.log('motion update', data))
        .catch(err => console.error('motion update failed', err));
    };

    const motionEnabled = document.getElementById('motion_enabled');
    if (motionEnabled) {
      motionEnabled.addEventListener('change', ev => {
        sendMotionValue('enabled', ev.target.checked ? 'true' : 'false');
      });
    }

    ['motion_sensitivity','motion_cooldown_time'].forEach(id => {
      const el = document.getElementById(id);
      if (!el) return;
      el.addEventListener('change', ev => {
        sendMotionValue(id.replace('motion_',''), ev.target.value);
      });
    });

    $$('.motion-sendto').forEach(el => {
      el.addEventListener('change', ev => {
        sendMotionValue(ev.target.dataset.target, ev.target.checked ? 'true' : 'false');
      });
    });

    const testModalEl = document.getElementById('send2-test-modal');
    const testModal = testModalEl ? new bootstrap.Modal(testModalEl) : null;
    const testOutput = document.getElementById('send2-test-output');
    const testTitle = document.getElementById('send2-test-title');

    const renderTestResult = data => {
      if (!testOutput) return;
      let text = '';
      const msg = data && data.message;
      const stripAnsi = s => typeof s === 'string' ? s.replace(/\u001b\[[0-9;]*[A-Za-z]/g, '') : s;
      if (!data) {
        text = 'No response received.';
      } else if (data.error) {
        const err = data.error.message || data.error.code || data.error;
        text = `Error: ${err}`;
      } else if (msg && typeof msg === 'object') {
        if (msg.output_b64) {
          try {
            text = stripAnsi(atob(msg.output_b64));
          } catch (e) {
            text = `Failed to decode output_b64: ${e}`;
          }
        } else {
          text = stripAnsi(msg.output || JSON.stringify(msg, null, 2));
        }
        if (msg.status && msg.status !== 'success') {
          text = `[${msg.status}] ${text}`;
        }
      } else if (typeof msg === 'string') {
        text = stripAnsi(msg);
      } else {
        text = stripAnsi(JSON.stringify(data, null, 2));
      }
      testOutput.textContent = text || '(no output)';
    };

    $$('button[data-sendto]').forEach(btn => {
      btn.onclick = null;
      btn.addEventListener('click', ev => {
        ev.preventDefault();
        const target = btn.dataset.sendto;
        if (!target) return;
        if (testTitle) testTitle.textContent = `Test: ${target}`;
        if (testOutput) testOutput.textContent = 'Running...';
        if (testModal) testModal.show();
        btn.disabled = true;
        const params = new URLSearchParams({ to: target, verbose: '1' });
        fetch(`/x/send.cgi?${params.toString()}`)
          .then(res => res.json())
          .then(renderTestResult)
          .catch(err => {
            if (testOutput) testOutput.textContent = `Request failed: ${err}`;
          })
          .finally(() => {
            btn.disabled = false;
          });
      });
    });

    const parseJson = id => {
      const el = document.getElementById(id);
      if (!el) return {};
      try {
        return JSON.parse(el.textContent || '{}');
      } catch (err) {
        console.error('Failed to parse JSON for', id, err);
        return {};
      }
    };

    const send2Config = parseJson('send2-config-json');
    const motionConfig = parseJson('motion-config-json');

    const truthy = v => {
      if (typeof v === 'string') v = v.toLowerCase();
      return v === true || v === 1 || v === '1' || v === 'true' || v === 'yes' || v === 'on';
    };
    const setValue = (id, value) => {
      const el = document.getElementById(id);
      if (!el || value === undefined || value === null) return;
      el.value = value;
    };
    const setChecked = (id, value) => {
      const el = document.getElementById(id);
      if (!el) return;
      el.checked = truthy(value);
    };
    const setStatus = (id, value) => {
      const el = document.getElementById(id);
      if (!el) return;
      const on = truthy(value);
      el.textContent = on ? 'Yes' : 'No';
      el.className = on ? 'text-success' : 'text-secondary';
    };

    const applySend2 = cfg => {
      const email = cfg.email || {};
      setValue('email_host', email.host);
      setValue('email_port', email.port);
      setValue('email_username', email.username);
      setValue('email_password', email.password);
      setChecked('email_use_ssl', email.use_ssl);
      setChecked('email_trust_cert', email.trust_cert);
      setValue('email_from_name', email.from_name);
      setValue('email_from_address', email.from_address);
      setValue('email_to_name', email.to_name);
      setValue('email_to_address', email.to_address);
      setValue('email_subject', email.subject);
      setValue('email_body', email.body);
      setChecked('email_send_photo', email.send_photo);
      setChecked('email_send_video', email.send_video);
      setStatus('status-email-photo', email.send_photo);
      setStatus('status-email-video', email.send_video);

      const ftp = cfg.ftp || {};
      setValue('ftp_host', ftp.host);
      setValue('ftp_port', ftp.port);
      setValue('ftp_username', ftp.username);
      setValue('ftp_password', ftp.password);
      setValue('ftp_path', ftp.path);
      setValue('ftp_template', ftp.template);
      setChecked('ftp_send_photo', ftp.send_photo);
      setChecked('ftp_send_video', ftp.send_video);
      setStatus('status-ftp-photo', ftp.send_photo);
      setStatus('status-ftp-video', ftp.send_video);

      const mqtt = cfg.mqtt || {};
      setValue('mqtt_client_id', mqtt.client_id);
      setValue('mqtt_host', mqtt.host);
      setValue('mqtt_port', mqtt.port);
      setValue('mqtt_username', mqtt.username);
      setValue('mqtt_password', mqtt.password);
      setChecked('mqtt_use_ssl', mqtt.use_ssl);
      setValue('mqtt_topic', mqtt.topic);
      setValue('mqtt_message', mqtt.message);
      setChecked('mqtt_send_photo', mqtt.send_photo);
      setValue('mqtt_topic_photo', mqtt.topic_photo);
      setChecked('mqtt_send_video', mqtt.send_video);
      setValue('mqtt_topic_video', mqtt.topic_video);
      setStatus('status-mqtt-photo', mqtt.send_photo);
      setStatus('status-mqtt-video', mqtt.send_video);

      const ntfy = cfg.ntfy || {};
      setValue('ntfy_host', ntfy.host);
      setValue('ntfy_port', ntfy.port);
      setValue('ntfy_username', ntfy.username);
      setValue('ntfy_password', ntfy.password);
      setValue('ntfy_token', ntfy.token);
      setChecked('ntfy_use_ssl', ntfy.use_ssl);
      setValue('ntfy_topic', ntfy.topic);
      setValue('ntfy_title', ntfy.title);
      setValue('ntfy_message', ntfy.message);
      setChecked('ntfy_send_photo', ntfy.send_photo);
      setChecked('ntfy_send_video', ntfy.send_video);
      setStatus('status-ntfy-photo', ntfy.send_photo);
      setStatus('status-ntfy-video', ntfy.send_video);

      const storage = cfg.storage || {};
      setValue('storage_mount', storage.mount);
      setValue('storage_device_path', storage.device_path);
      setValue('storage_template', storage.template);
      setChecked('storage_send_photo', storage.send_photo);
      setChecked('storage_send_video', storage.send_video);
      setChecked('storage_send_photo', storage.send_photo);
      setChecked('storage_send_video', storage.send_video);
      setStatus('status-storage-photo', storage.send_photo);
      setStatus('status-storage-video', storage.send_video);

      const telegram = cfg.telegram || {};
      setValue('telegram_token', telegram.token);
      setValue('telegram_channel', telegram.channel);
      setValue('telegram_caption', telegram.caption);
      setChecked('telegram_send_photo', telegram.send_photo);
      setChecked('telegram_send_video', telegram.send_video);
      setStatus('status-telegram-photo', telegram.send_photo);
      setStatus('status-telegram-video', telegram.send_video);

      const webhook = cfg.webhook || {};
      setValue('webhook_url', webhook.url);
      setValue('webhook_message', webhook.message);
      setChecked('webhook_send_photo', webhook.send_photo);
      setChecked('webhook_send_video', webhook.send_video);
      setStatus('status-webhook-photo', webhook.send_photo);
      setStatus('status-webhook-video', webhook.send_video);
    };

    const applyMotion = motion => {
      setChecked('motion_enabled', motion.enabled);
      setValue('motion_sensitivity', motion.sensitivity);
      setValue('motion_cooldown_time', motion.cooldown_time);
      setChecked('motion_send2email', motion.send2email);
      setChecked('motion_send2ftp', motion.send2ftp);
      setChecked('motion_send2mqtt', motion.send2mqtt);
      setChecked('motion_send2ntfy', motion.send2ntfy);
      setChecked('motion_send2storage', motion.send2storage);
      setChecked('motion_send2telegram', motion.send2telegram);
      setChecked('motion_send2webhook', motion.send2webhook);
    };

    applySend2(send2Config || {});
    applyMotion(motionConfig || {});

    if (runtimeButton) {
      runtimeButton.addEventListener('click', toggleMotionRuntime);
      loadMotionRuntime();
    }

  syncPort('email_use_ssl', 'email_port', '25', '465');
  syncPort('mqtt_use_ssl', 'mqtt_port', '1883', '8883');
  syncPort('ntfy_use_ssl', 'ntfy_port', '80', '443');

  // Adjust textarea heights to fit typical content
  const emailBody = document.getElementById('email_body');
  if (emailBody) emailBody.style.height = '7rem';
  const mqttMsg = document.getElementById('mqtt_message');
  if (mqttMsg) mqttMsg.style.height = '7rem';
  const ntfyMsg = document.getElementById('ntfy_message');
  if (ntfyMsg) ntfyMsg.style.height = '7rem';
  const webhookMsg = document.getElementById('webhook_message');
  if (webhookMsg) webhookMsg.style.height = '7rem';
})();
</script>

<%in _footer.cgi %>
