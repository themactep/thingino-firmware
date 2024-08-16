#!/usr/bin/haserl
<%in _common.cgi %>
<%
plugin="daynight"
plugin_name="Day/Night"
page_title="Day and Night Mode"
params="enabled interval max min"

CRONTABS=/etc/crontabs/root
tmp_file=/tmp/$plugin

config_file="${ui_config_dir}/${plugin}.conf"
[ ! -f "$config_file" ] && touch $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	# parse values from parameters
	for p in $params; do
		eval ${plugin}_${p}=\$POST_${plugin}_${p}
		sanitize "${plugin}_${p}"
	done; unset p

	# Validation
	[ -z "$daynight_min" ] && set_error_flag "Min value cannot be empty"
	[ -z "$daynight_max" ] && set_error_flag "Max cannot be empty"
	[ -z "$daynight_interval" ] && daynight_interval="1"

	if [ -z "$error" ]; then
		: > $tmp_file
		for p in $params; do
			echo "${plugin}_${p}=\"$(eval echo \$${plugin}_${p})\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		# update crontab
		tmpfile=$(mktemp)
		cat $CRONTABS > $tmpfile
		sed -i '/daynight/d' $tmpfile
		echo "# run daynight every ${daynight_interval} minutes" >> $tmpfile
		[ "true" != "$daynight_enabled" ] && echo -n "#" >> $tmpfile
		echo "*/${daynight_interval} * * * * daynight" >> $tmpfile
		mv $tmpfile $CRONTABS

		# update values in env
		tmpfile=$(mktemp)
		echo "day_night_min $daynight_min" >> $tmpfile
		echo "day_night_max $daynight_max" >> $tmpfile
		fw_setenv -s $tmpfile
		rm $tmpfile

		[ "true" = "$daynight_enabled" ] && daynight >/dev/null 2>&1 &

		update_caminfo
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
else
	include $config_file

	# Default values
	if [ -z "$daynight_enabled" ] && [ "*" = "$(awk -F/ '/daynight$/{print $1}' $CRONTABS)" ]; then
		daynight_enabled="true"
	fi
	[ -z "$daynight_min" ] && daynight_min=500
	[ -z "$daynight_max" ] && daynight_max=15000
	[ -z "$daynight_interval" ] && daynight_interval=1

	maxgain=131072
	pb_day=$((daynight_min / 128))
	pb_night=$((daynight_max / 128))
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="row g-4 mb-4">
<div class="col col-12 col-xl-4">
<% field_switch "daynight_enabled" "Enable daynight script" %>
<% field_number "daynight_min" "Minimum gain in night mode" %>
<% field_number "daynight_max" "Maximum gain in day mode" %>
<% field_number "daynight_interval" "Run every X minutes" %>
</div>
<div class="col col-12 col-xl-8">

<% ex "fw_printenv | grep day_night" %>
<% [ -f $config_file ] && ex "cat $config_file" %>
<% ex "crontab -l" %>
</div>
</div>

<% button_submit %>
</form>

<%in _footer.cgi %>


