#!/usr/bin/haserl
<%in _common.cgi %>
<%
plugin="dusk2dawn"
plugin_name="Day/Night by Sun"
page_title="Dusk to Dawn"
params="enabled lat lng runat"

tmp_file=/tmp/$plugin

config_file="${ui_config_dir}/${plugin}.conf"
[ ! -f "$config_file" ] && touch $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	# parse values from parameters
	for p in $params; do
		eval ${plugin}_${p}=\$POST_${plugin}_${p}
		sanitize "${plugin}_${p}"
	done; unset p

	[ -z "$dusk2dawn_runat" ] && dusk2dawn_runat="0:00"

	# Validation
	[ -z "$dusk2dawn_lat" ] && set_error_flag "Latitude cannot be empty"
	[ -z "$dusk2dawn_lng" ] && set_error_flag "Longitude cannot be empty"

	if [ -z "$error" ]; then
		: > $tmp_file
		for p in $params; do
			echo "${plugin}_${p}=\"$(eval echo \$${plugin}_${p})\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		dusk2dawn > /dev/null

		update_caminfo
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
else
	include $config_file

	# Default values
	[ -z "$dusk2dawn_enabled" ] && dusk2dawn_enabled=false
	[ -z "$dusk2dawn_runat" ] && dusk2dawn_runat="0:00"
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="row g-4 mb-4">
<div class="col col-12 col-xl-4">
<% field_switch "dusk2dawn_enabled" "Enable dusk2dawn script" %>
<p>Find your coordinated on <a href="https://latitude.to/">latitude.to</a>.</p>
<% field_text "dusk2dawn_lat" "Latitude" %>
<% field_text "dusk2dawn_lng" "Longitude" %>
<% field_text "dusk2dawn_runat" "Run at" %>
</div>
<div class="col col-12 col-xl-4">
<% ex "crontab -l" %>
</div>
<div class="col col-12 col-xl-4">
<% [ -f $config_file ] && ex "cat $config_file" %>
</div>
</div>

<% button_submit %>
</form>

<script>
function getCoordinates() {
	if ("geolocation" in navigator) {
		navigator.geolocation.getCurrentPosition((pos) => {
			$('#dusk2dawn_lat').value= pos.coords.latitude;
			$('#dusk2dawn_lng').value = pos.coords.longitude;
		}, function(error) {
			switch (error.code) {
				case error.PERMISSION_DENIED:
					console.error("The request for geolocation was denied.");
					break;
				case error.TIMEOUT:
					console.error("The request for geolocation timed out.");
					break;
				case error.POSITION_UNAVAILABLE:
					console.error("Location information is unavailable.");
					break;
				case error.UNKNOWN_ERROR:
					console.error("An unknown error occurred.");
					break;
			}
		});
	} else {
		alert("Geolocation is not available in this browser.");
	}
}
</script>

<%in _footer.cgi %>
