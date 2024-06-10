#!/usr/bin/haserl
<%in p/common.cgi %>
<%
plugin="speaker"
plugin_name="Play on speaker"
page_title="Play on speaker"
params="enabled url file"
# volume srate codec outputEnabled speakerPin speakerPinInvert

tmp_file=/tmp/${plugin}.conf

config_file="${ui_config_dir}/${plugin}.conf"
[ ! -f "$config_file" ] && touch $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	# parse values from parameters
	for p in $params; do
		eval ${plugin}_${p}=\$POST_${plugin}_${p}
		sanitize "${plugin}_${p}"
	done; unset p

	### Validation
	if [ "true" = "$speaker_enabled" ]; then
		[ -z "$speaker_url"   ] && set_error_flag "URL cannot be empty."
	fi

	if [ -z "$error" ]; then
		# create temp config file
		:>$tmp_file
		for p in $params; do
			echo "${plugin}_${p}=\"$(eval echo \$${plugin}_${p})\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		update_caminfo
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
else
	include $config_file

	# Default values
	[ -z "$speaker_url" ] && speaker_url="http://127.0.0.1/play_audio"
fi
%>
<%in p/header.cgi %>

<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_switch "speaker_enabled" "Enable playing on speaker" %>
<% field_text "speaker_url" "URL" %>
<% field_text "speaker_file" "Audio file" %>
<% button_submit %>
</form>
</div>
<div class="col">
<% ex "cat $config_file" %>
<% button_webui_log %>
</div>
</div>

<%in p/footer.cgi %>
