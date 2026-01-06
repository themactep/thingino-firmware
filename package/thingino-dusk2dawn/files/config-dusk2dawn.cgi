#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Dusk2Dawn Control"

domain="dusk2dawn"
config_file="/etc/thingino.json"
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
  latitude="$(get_value latitude)"
  longitude="$(get_value longitude)"
  sunrise_offset="$(get_value sunrise_offset)"
  sunset_offset="$(get_value sunset_offset)"
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
  error=""

  enabled="$POST_enabled"
  latitude="$POST_latitude"
  longitude="$POST_longitude"
  sunrise_offset="$POST_sunrise_offset"
  sunset_offset="$POST_sunset_offset"

  # validate
  if [ "true" = "$enabled" ]; then
    error_if_empty "$latitude" "GeoCoordinates cannot be empty"
    error_if_empty "$longitide" "GeoCoordinates cannot be empty"
  fi

  defaults

  if [ -z "$error" ]; then
    set_value enabled "$enabled"
    set_value latitude "$latitude"
    set_value longitude "$longitude"
    set_value sunrise_offset "$sunrise_offset"
    set_value sunset_offset "$sunset_offset"

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
      <h3>By Sun</h3>
      <% field_switch "enabled" "Enable Sun tracking" %>
      <div class="row g-1">
        <div class="col"><% field_text "latitude" "Latitude" %></div>
        <div class="col"><% field_text "longitude" "Longitude" %></div>
      </div>
      <p><a href="https://my-coordinates.com/">Find your coordinates</a></p>
      <div class="row g-1">
        <div class="col"><% field_text "sunrise_offset" "Sunrise offset" "minutes" %></div>
        <div class="col"><% field_text "sunset_offset" "Sunset offset" "minutes" %></div>
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
