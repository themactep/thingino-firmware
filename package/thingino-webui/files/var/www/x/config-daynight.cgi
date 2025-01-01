#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Day/Night Mode Control"

CRONTABS="/etc/cron/crontabs/root"

grep -q '^[^#].*daynight$' $CRONTABS && daynight_enabled=true
default_for daynight_enabled false

daynight_interval=$(awk -F'[/ ]' '/daynight$/{print $2}' $CRONTABS)
default_for daynight_interval 1

day_night_max=$(fw_printenv -n day_night_max)
default_for day_night_max 15000

day_night_min=$(fw_printenv -n day_night_min)
default_for day_night_min 5000

day_night_color=$(fw_printenv -n day_night_color)
default_for day_night_color false

day_night_ircut=$(fw_printenv -n day_night_ircut)
default_for day_night_ircut false

day_night_ir850=$(fw_printenv -n day_night_ir850)
default_for day_night_ir850 false

day_night_ir940=$(fw_printenv -n day_night_ir940)
default_for day_night_ir940 false

day_night_white=$(fw_printenv -n day_night_white)
default_for day_night_white false

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	# env values
	day_night_max=$POST_day_night_max
	day_night_min=$POST_day_night_min
	day_night_color=$POST_day_night_color
	day_night_ircut=$POST_day_night_ircut
	day_night_ir850=$POST_day_night_ir850
	day_night_ir940=$POST_day_night_ir940
	day_night_white=$POST_day_night_white

	# cron values
	daynight_enabled=$POST_daynight_enabled
	daynight_interval=$POST_daynight_interval

	save2env "
day_night_min $day_night_min
day_night_max $day_night_max
day_night_color $day_night_color
day_night_ircut $day_night_ircut
day_night_ir850 $day_night_ir850
day_night_ir940 $day_night_ir940
day_night_white $day_night_white
"
	# update crontab
	tmpfile=$(mktemp -u)
	cat $CRONTABS > $tmpfile
	sed -i '/daynight/d' $tmpfile
	echo "# run daynight every $daynight_interval minutes" >> $tmpfile
	[ "true" = "$daynight_enabled" ] || echo -n "#" >> $tmpfile
	echo "*/$daynight_interval * * * * daynight" >> $tmpfile
	mv $tmpfile $CRONTABS

	update_caminfo
	redirect_back "success" "Data updated"
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-3">
<% field_switch "daynight_enabled" "Enable Day/Night script" %>
<div class="row mb-4">

<div class="col-sm-6 col-xl-3 col-xxl-3 mb-3">
	<p>Run with <a href="info-cron.cgi">cron</a> every <input type="text" id="daynight_interval"
		name="daynight_interval" value="<%= $daynight_interval %>" pattern="[0-9]{1,}" title="numeric value"
		class="form-control text-end" data-min="1" data-max="60" data-step="1"> min.</p>

	<h5>Actions to perform</h5>
	<% field_checkbox "day_night_color" "Change color mode" %>
	<% fw_printenv -n gpio_ircut >/dev/null && field_checkbox "day_night_ircut" "Flip IR cut filter" %>
	<% fw_printenv -n gpio_ir850 >/dev/null && field_checkbox "day_night_ir850" "Toggle IR 850 nm" %>
	<% fw_printenv -n gpio_ir940 >/dev/null && field_checkbox "day_night_ir940" "Toggle IR 940 nm" %>
	<% fw_printenv -n gpio_white >/dev/null && field_checkbox "day_night_white" "Toggle white light" %>
</div>

<div class="col-sm-6 col-xl-3 col-xxl-4 mb-3">
	<h3 class="alert alert-warning text-center">Gain <span class="gain"></span></h3>
	<% field_number "day_night_min" "Switch to Day mode when gain drops below" %>
	<% field_number "day_night_max" "Switch to Night mode when gain raises above" %>
</div>

<div class="col-xl-6 col-xxl-5">
<div class="alert alert-info">
<p>The day/night mode is controlled by the brightness of the scene.
Changes in illumination affect the gain required to normalise a darkened image - the darker the scene, the higher the gain value.
The current gain value is displayed at the top of each page next to the sun emoji.
Switching between modes is triggered by changes in the gain beyond the threshold values.</p>
<% wiki_page "Configuration:-Night-Mode" %>
</div>
</div>
</div>

<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "fw_printenv | grep day_night | sort" %>
<% ex "crontab -l" %>
</div>

<%in _footer.cgi %>
