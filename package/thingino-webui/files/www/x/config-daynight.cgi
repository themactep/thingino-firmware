#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Day/Night Mode Control"
LOG=/tmp/webui.log

defaults() {
	default_from_json day_night_color
	default_for day_night_color "false"
	default_from_json day_night_ircut
	default_for day_night_ircut "false"
	default_from_json day_night_ir850
	default_for day_night_ir850 "false"
	default_from_json day_night_ir940
	default_for day_night_ir940 "false"
	default_from_json day_night_white
	default_for day_night_white "false"
	default_from_json dusk2dawn_enabled
	default_for dusk2dawn_enabled "false"
	default_from_json dusk2dawn_lat
	default_from_json dusk2dawn_lng
	default_from_json dusk2dawn_offset_sr
	default_for dusk2dawn_offset_sr "0"
	default_from_json dusk2dawn_offset_ss
	default_for dusk2dawn_offset_ss "0"

	if [ "enabled" = $(service status daynightd) ]; then
		default_for dnd_enabled "true"
	else
		default_for dnd_enabled "false"
	fi
	default_for dnd_threshold_low "$(jct /etc/daynightd.json get brightness_thresholds.threshold_low)"
	default_for dnd_threshold_high "$(jct /etc/daynightd.json get brightness_thresholds.threshold_high)"
	default_for dnd_hysteresis "$(jct /etc/daynightd.json get brightness_thresholds.hysteresis_factor)"
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	read_from_post "dnd" "enabled threshold_low threshold_high hysteresis"
	read_from_post "day_night" "color enabled ir850 ir940 ircut white"
	read_from_post "dusk2dawn" "enabled lat lng offset_sr offset_ss"

	defaults

	# validate
	if [ "true" = "$dnd_enabled" ]; then
		error_if_empty "$dnd_threshold_low" "Day mode threshold cannot be empty"
		error_if_empty "$dnd_threshold_high" "Night mode threshold cannot be empty"
		error_if_empty "$dnd_hysteresis" "Hysteresis cannot be empty"
	fi

	if [ "true" = "$dusk2dawn_enabled" ]; then
		error_if_empty "$dusk2dawn_lat" "Latitude cannot be empty"
		error_if_empty "$dusk2dawn_lng" "Longitude cannot be empty"
	fi

	if [ -z "$error" ]; then
		save2config "
day_night_color=\"$day_night_color\"
day_night_ir850=\"$day_night_ir850\"
day_night_ir940=\"$day_night_ir940\"
day_night_ircut=\"$day_night_ircut\"
day_night_white=\"$day_night_white\"
dusk2dawn_enabled=\"$dusk2dawn_enabled\"
dusk2dawn_lat=\"$dusk2dawn_lat\"
dusk2dawn_lng=\"$dusk2dawn_lng\"
dusk2dawn_offset_sr=\"$dusk2dawn_offset_sr\"
dusk2dawn_offset_ss=\"$dusk2dawn_offset_ss\"
"
		jct /etc/daynightd.json set brightness_thresholds.threshold_low "$dnd_threshold_low" >>$LOG 2>&1
		jct /etc/daynightd.json set brightness_thresholds.threshold_high "$dnd_threshold_high" >>$LOG 2>&1
		jct /etc/daynightd.json set brightness_thresholds.hysteresis_factor "$dnd_hysteresis" >>$LOG 2>&1

		if [ "true" = "$dnd_enabled" ]; then
			service enable daynightd >>$LOG 2>&1
			service start daynightd >>$LOG 2>&1
		else
			service stop daynightd >>$LOG 2>&1
			service disable daynightd >>$LOG 2>&1
		fi

		if [ "true" = "$dusk2dawn_enabled" ]; then
			dusk2dawn >>$LOG 2>&1
		fi

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
<h3 class="alert alert-warning text-center">Gain <span class="dnd_gain"></span>%</h3>
<% field_range "dnd_threshold_low" "Switch to Day mode at value below, %" %>
<% field_range "dnd_threshold_high" "Switch to Night at value above, %" %>
<% field_range "dnd_hysteresis" "Hysteresis factor" "0.1,0.9,0.1" %>
</div>

<div class="col mb-3">
<h3>By Illumination</h3>
<% field_switch "dnd_enabled" "Enable Day/Night daemon" %>

<h5>Actions to perform</h5>
<% field_checkbox "day_night_color" "Change color mode" %>
<% [ -z "$gpio_ircut" ] || field_checkbox "day_night_ircut" "Flip IR cut filter" %>
<% [ -z "$gpio_ir850" ] || field_checkbox "day_night_ir850" "Toggle IR 850 nm" %>
<% [ -z "$gpio_ir940" ] || field_checkbox "day_night_ir940" "Toggle IR 940 nm" %>
<% [ -z "$gpio_white" ] || field_checkbox "day_night_white" "Toggle white light" %>
</div>

<div class="col">
<h3>By Sun</h3>
<% field_switch "dusk2dawn_enabled" "Enable Sun tracking" %>
<div class="row g-1">
<div class="col"><% field_text "dusk2dawn_lat" "Latitude"  %></div>
<div class="col"><% field_text "dusk2dawn_lng" "Longitude" %></div>
</div>
<p><a href="https://my-coordinates.com/">Find your coordinates</a></p>
<div class="row g-1">
<div class="col"><% field_text "dusk2dawn_offset_sr" "Sunrise offset" "minutes" %></div>
<div class="col"><% field_text "dusk2dawn_offset_ss" "Sunset offset" "minutes" %></div>
</div>
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
<% ex "jct /etc/daynightd.json print" %>
<% ex "crontab -l" %>
</div>

<%in _footer.cgi %>
