#!/bin/haserl
<%in _common.cgi %>
<%
plugin="dusk2dawn"
plugin_name="Day/Night by Sun"
page_title="Dusk to Dawn"
params="enabled lat lng runat offset_sr offset_ss"

config_file="$ui_config_dir/dusk2dawn.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "dusk2dawn" "$params"

	default_for "$dusk2dawn_runat" "0:00"
	default_for "$dusk2dawn_offset_sr" "0"
	default_for "$dusk2dawn_offset_ss" "0"

	error_if_empty "$dusk2dawn_lat" "Latitude cannot be empty"
	error_if_empty "$dusk2dawn_lng" "Longitude cannot be empty"

	if [ -z "$error" ]; then
		tmp_file=$(mktemp)
		for p in $params; do
			echo "dusk2dawn_$p=\"$(eval echo \$dusk2dawn_$p)\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		dusk2dawn > /dev/null

		update_caminfo
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
else
	# Default values
	default_for dusk2dawn_enabled "false"
	default_for dusk2dawn_runat "0:00"
	default_for dusk2dawn_offset_sr "0"
	default_for dusk2dawn_offset_ss "0"
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_switch "dusk2dawn_enabled" "Enable dusk2dawn script" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<% field_text "dusk2dawn_lat" "Latitude"  %>
<% field_text "dusk2dawn_lng" "Longitude" %>
<p><a href="https://my-coordinates.com/">Find your coordinates</a></p>
</div>
<div class="col">
<% field_text "dusk2dawn_offset_sr" "Sunrise offset, minutes" %>
<% field_text "dusk2dawn_offset_ss" "Sunset offset, minutes" %>
</div>
<div class="col">
<% field_text "dusk2dawn_runat" "Run at" %>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "crontab -l" %>
<% [ -f $config_file ] && ex "cat $config_file" %>
</div>

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
