#!/usr/bin/haserl
<%in _common.cgi %>
<%
plugin="audio"
page_title="Audio"
params="debug net_enabled net_port"

tmp_file=/tmp/$plugin
config_file="${ui_config_dir}/${plugin}.conf"
[ ! -f "$config_file" ] && touch $config_file

audio_control=/etc/init.d/S96iad

if [ "POST" = "$REQUEST_METHOD" ]; then
	# parse values from parameters
	for p in $params; do
		eval ${plugin}_${p}=\$POST_${plugin}_${p}
		sanitize "${plugin}_${p}"
	done; unset p

	# validation

	if [ -z "$error" ]; then
		:>$tmp_file
		for p in $params; do
			echo "${plugin}_${p}=\"$(eval echo \$${plugin}_${p})\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		if [ -f "$audio_control" ]; then
			$audio_control restart >> /tmp/webui.log
		else
			echo "$audio_control not found" >> /tmp/webui.log
		fi

		update_caminfo
		redirect_to "$SCRIPT_NAME"
	fi
else
	include $config_file

	# default values
	[ -z "$audio_debug" ] && audio_debug=false
	[ -z "$audio_net_enabled" ] && audio_net_enabled=false
	[ -z "$audio_net_port" ] && audio_net_port=8081
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<h3>Audio Backchannel</h3>
<% field_switch "audio_net_enabled" "Enable Audio Backchannel" "Live stream audio to the camera speaker over the network" %>
<% field_number "audio_net_port" "Audio Backchannel Port" "" "Which port to listen on" %>
<a href="https://github.com/gtxaspec/ingenic-audiodaemon?tab=readme-ov-file#on-pc">See this repo for usage instructions</a>
<p><% button_submit %></p>
</div>
<div class="col">
<h3>Audio Output Settings</h3>
Work in progress
</div>
<div class="col">
<% field_switch "audio_debug" "Enable Debugging" %>
<h3>Configuration</h3>
<% ex "cat $config_file" %>
</div>
</div>
</form>

<%in _footer.cgi %>
