#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Day/Night Daemon Control"

domain="daynight"
config_file="/etc/daynightd.json"
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
  threshold_low="$(get_value threshold_low)"
  threshold_high="$(get_value threshold_high)"
  hysteresis_factor="$(get_value hysteresis_factor)"

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
  threshold_low="$POST_threshold_low"
  thershold_high="$POST_threshold_high"
  hysteresis_factor="$POST_hysteresis_factor"
  controls_color="$POST_controls_color"
  controls_ir850="$POST_controls_ir850"
  controls_ir940="$POST_controls_ir940"
  controls_ircut="$POST_controls_ircut"
  controls_white="$POST_controls_white"

  # validate
  if [ "true" = "$enabled" ]; then
    error_if_empty "$threshold_low" "Day mode threshold cannot be empty"
    error_if_empty "$threshold_high" "Night mode threshold cannot be empty"
    error_if_empty "$hysteresis_factor" "Hysteresis cannot be empty"
  fi

  defaults

  if [ -z "$error" ]; then
    set_value enabled "$enabled"
    set_value threshold_low "$threshold_low"
    set_value threshold_high "$threshold_high"
    set_value hysteresis_factor "$hysteresis_factor"
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
      <h3 class="alert alert-warning text-center"><span class="dnd-gain"></span>%</h3>
      <% field_switch "enabled" "Enable photosensing" %>
    </div>
    <div class="col mb-3">
      <% field_range "threshold_low" "Day mode at value below, %" %>
      <% field_range "threshold_high" "Night mode at value above, %" %>
      <% field_range "hysteresis_factor" "Tolerance, %" %>
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
