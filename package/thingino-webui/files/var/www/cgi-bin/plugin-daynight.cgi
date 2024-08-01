#!/usr/bin/haserl
<%in p/common.cgi %>
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

		tmpfile=$(mktemp)
		cat $CRONTABS > $tmpfile
		sed -i '/daynight/d' $tmpfile
		echo "# run daynight every ${daynight_interval} minutes" >> $tmpfile

		[ "true" != "$daynight_enabled" ] && echo -n "#" >> $tmpfile
		echo "1/${daynight_interval} * * * * daynight" >> $tmpfile
		mv $tmpfile $CRONTABS

		update_caminfo
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
else
	include $config_file

	# Default values
	[ -z "$daynight_min" ] && daynight_min=300
	[ -z "$daynight_max" ] && daynight_max=150000
	[ -z "$daynight_interval" ] && daynight_interval=1
fi
%>
<%in p/header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="row g-4 mb-4">
<div class="col col-12 col-xl-4">
<% field_switch "daynight_enabled" "Enable daynight script" %>
<% field_number "daynight_min" "Switch to day mode when gain value is below" %>
<% field_number "daynight_max" "Switch to night mode when gain value is above" %>
<% field_number "daynight_interval" "Run every X minutes" %>
</div>
<div class="col col-12 col-xl-4">
<div id="demo"></div>
<% ex "crontab -l" %>
</div>
<div class="col col-12 col-xl-4">
<% [ -f $config_file ] && ex "cat $config_file" %>
</div>
</div>

<% button_submit %>
</form>

<%in p/footer.cgi %>


