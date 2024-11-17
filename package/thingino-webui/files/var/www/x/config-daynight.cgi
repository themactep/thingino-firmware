#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Day/Night Mode Control"

CRONTABS="/etc/crontabs/root"

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	# values from the form
	day_night_max=${POST_day_night_max:-15000}
	day_night_min=${POST_day_night_min:-5000}
	daynight_enabled=${POST_daynight_enabled:-true}
	daynight_interval=${POST_daynight_interval:-1}

	save2env "day_night_min $day_night_min\n" \
		"day_night_max $day_night_max\n"

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

grep -q '^[^#].*daynight$' $CRONTABS && daynight_enabled="true"
default_for daynight_enabled "false"

daynight_interval=$(awk -F'[/ ]' '/daynight$/{print $2}' $CRONTABS)
default_for daynight_interval 1

day_night_max=$(get day_night_max)
default_for day_night_max 15000

day_night_min=$(get day_night_min)
default_for day_night_min 5000
%>
<%in _header.cgi %>

<div class="row mb-4">
<div class="col-lg-8 col-xxl-9 mb-3">
<div class="alert alert-info">
<p>The day/night mode is controlled by the brightness of the scene.
<p>Changes in illumination affect the gain required to normalise a darkened image - the darker the scene, the higher the gain value.</p>
<p>Switching between modes is triggered by changes in gain beyond the thresholds set below.
<p>The current gain value is displayed at the top of each page next to the sun emoji.</p>
<% wiki_page "Configration:-Night-Mode" %>
</div>
</div>

<div class="col-lg-4 col-xxl-3 mb-3">

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_switch "daynight_enabled" "Enable Day/Night script" %>
<p>Run it with <a href="info-cron.cgi">cron</a> every <input type="text" id="daynight_interval" name="daynight_interval" value="<%= $daynight_interval %>" class="form-control text-end" pattern="[0-9]{1,}" data-min="1" data-max="60" data-step="1" title="numeric value"> min.</p>
<div class="row g-2 mb-3">
<div class="col-3"><input type="text" id="day_night_min" name="day_night_min" class="form-control text-end" value="<%= $day_night_min %>" pattern="[0-9]{1,}" title="numeric value" data-min="0" data-max="150000" data-step="1"></div>
<label class="col-9 col-form-label" for="day_night_min">Min. gain in Night mode</label>
</div>
<div class="row g-2 mb-3">
<div class="col-3"><input type="text" id="day_night_max" name="day_night_max" class="form-control text-end" value="<%= $day_night_max %>" pattern="[0-9]{1,}" title="numeric value" data-min="0" data-max="150000" data-step="1"></div>
<label class="col-9 col-form-label" for="day_night_max">Max. gain in Day mode</label>
</div>
<% button_submit %>
</form>

</div>
</div>

<div class="alert alert-dark ui-debug">
<h4 class="mb-3">Debug info</h4>
<% ex "fw_printenv | grep gpio | sort" %>
<% ex "crontab -l" %>
</div>

<%in _footer.cgi %>
