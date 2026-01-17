#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Day/Night Mode Control"

domain="daynight"
config_file="/etc/prudynt.json"
temp_config_file="/tmp/$domain.json"

defaults() {
  default_for enabled "false"
}

set_value() {
  [ -f "$temp_config_file" ] || echo '{}' > "$temp_config_file"
  jct "$temp_config_file" set "$domain.$1" "$2" >/dev/null 2>&1
}

get_value() {
  jct "$config_file" get "$domain.$1" 2>/dev/null
}

read_config() {
  [ -f "$config_file" ] || return

  enabled="$(get_value enabled)"
  ev_day_low_primary="$(get_value ev_day_low_primary)"
  ev_day_low_secondary="$(get_value ev_day_low_secondary)"
  ev_night_high="$(get_value ev_night_high)"
  sample_interval_ms="$(get_value sample_interval_ms)"
  total_gain_night_threshold="$(get_value total_gain_night_threshold)"
  total_gain_day_threshold="$(get_value total_gain_day_threshold)"
  controls_color="$(get_value controls.color)"
  controls_ir850="$(get_value controls.ir850)"
  controls_ir940="$(get_value controls.ir940)"
  controls_ircut="$(get_value controls.ircut)"
  controls_white="$(get_value controls.white)"
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
  error=""

  enabled="$POST_enabled"
  ev_day_low_primary="$POST_ev_day_low_primary"
  ev_day_low_secondary="$POST_ev_day_low_secondary"
  ev_night_high="$POST_ev_night_high"
  sample_interval_ms="$POST_sample_interval_ms"
  total_gain_night_threshold="$POST_total_gain_night_threshold"
  total_gain_day_threshold="$POST_total_gain_day_threshold"
  controls_color="$POST_controls_color"
  controls_ir850="$POST_controls_ir850"
  controls_ir940="$POST_controls_ir940"
  controls_ircut="$POST_controls_ircut"
  controls_white="$POST_controls_white"

  # validate
  if [ "true" = "$enabled" ]; then
    error_if_empty "$total_gain_night_threshold" "Night gain threshold cannot be empty"
    error_if_empty "$total_gain_day_threshold" "Day gain threshold cannot be empty"
  fi

  defaults

  if [ -z "$error" ]; then
    set_value enabled "$enabled"
    set_value ev_day_low_primary "$ev_day_low_primary"
    set_value ev_day_low_secondary "$ev_day_low_secondary"
    set_value ev_night_high "$ev_night_high"
    set_value sample_interval_ms "$sample_interval_ms"
    set_value total_gain_night_threshold "$total_gain_night_threshold"
    set_value total_gain_day_threshold "$total_gain_day_threshold"
    set_value controls.color "$controls_color"
    set_value controls.ir850 "$controls_ir850"
    set_value controls.ir940 "$controls_ir940"
    set_value controls.ircut "$controls_ircut"
    set_value controls.white "$controls_white"

    jct "$config_file" import "$temp_config_file"
    rm "$temp_config_file"

    redirect_to $SCRIPT_NAME "success" "Data updated."
  else
    redirect_to $SCRIPT_NAME "danger" "Error: $error"
  fi
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-3">
  <div class="row row-cols-1 row-cols-md-2 row-cols-xxl-4 mb-4">
    <div class="col">
      <h3 class="alert alert-warning text-center"><span class="dnd-gain"></span></h3>
      <% field_switch "enabled" "Enable photosensing" %>
    </div>
    <div class="col mb-3">
      <h6>Thresholds</h6>
      <% field_number "total_gain_night_threshold" "Switch to night mode above" "0,10000,1" %>
      <% field_number "total_gain_day_threshold" "Switch to day mode below" "0,10000,1" %>
    </div>
    <div class="col mb-3">
      <h5>Controls</h5>
      <% field_checkbox "controls_color" "Change color mode" %>
      <% field_checkbox "controls_ircut" "Flip IR cut filter" %>
      <% field_checkbox "controls_ir850" "Toggle IR 850 nm" %>
      <% field_checkbox "controls_ir940" "Toggle IR 940 nm" %>
      <% field_checkbox "controls_white" "Toggle white light" %>
    </div>
    <div class="col">
      <div class="alert alert-info">
        <p>The day/night mode is controlled by the brightness of the scene.
          Switching between modes is triggered by changes in the gain beyond the threshold values.</p>
        <% wiki_page "Configuration:-Night-Mode" %>
      </div>
    </div>
  </div>
  <% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
  <h4 class="mb-3">Debug info</h4>
  <% ex "jct $config_file get $domain" %>
</div>

<%in _footer.cgi %>
