#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to FTP"

domain="ftp"
config_file="/etc/send2.json"
temp_config_file="/tmp/$domain.json"

defaults() {
	default_for "port" "21"
	default_for "template" "${network_hostname}-%Y%m%d-%H%M%S"
	default_for "send_video" "false"
	default_for "send_photo" "false"

	[ -z "$username" ] && username="anonymous" && password="anonymous"
}

set_value() {
	[ -f "$temp_config_file" ] || echo '{}' > "$temp_config_file"
	local sanitized_value
	sanitized_value="$(sanitize_json_value "$2")"
	jct "$temp_config_file" set "$domain.$1" "$sanitized_value" >/dev/null 2>&1
}

get_value() {
	jct $config_file get "$domain.$1"
}

read_config() {
	[ -f "$config_file" ] || return

	host=$(get_value "host")
	port=$(get_value "port")
	username=$(get_value "username")
	password=$(get_value "password")
	path=$(get_value "path")
	template=$(get_value "template")
	send_photo=$(get_value "send_photo")
	send_video=$(get_value "send_video")
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	host="$POST_host"
	port="$POST_port"
	username="$POST_username"
	password="$POST_password"
	path="$POST_path"
	template="$POST_template"
	send_photo="$POST_send_photo"
	send_video="$POST_send_video"

#	[ "true" = "$send2ftp"  ] && error_if_empty "$host" "FTP address cannot be empty."
#	[ "true" = "$send2tftp" ] && error_if_empty "$host" "TFTP address cannot be empty."
#	[ "true" = "$save4web"  ] && error_if_empty "$localpath" "Local path cannot be empty."

	defaults

	if [ -z "$error" ]; then
		set_value host "$host"
		set_value port "$port"
		set_value username "$username"
		set_value password "$password"
		set_value path "$path"
		set_value template "$template"
		set_value send_photo "$send_photo"
		set_value send_video "$send_video"

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

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3">
<div class="col">
<div class="row g-1">
<div class="col-10"><% field_text "host" "FTP server FQDN or IP address" %></div>
<div class="col-2"><% field_text "port" "Port" %></div>
</div>
<% field_text "username" " FTP username" %>
<% field_password "password" "FTP password" %>
</div>
<div class="col">
<% field_text "path" "Path on FTP server" "relative to FTP root directory" %>
<% field_text "template" "Filename template" "$STR_SUPPORTS_STRFTIME" "do not use extension" %>
<% field_switch "send_photo" "Send photo" %>
<% field_switch "send_video" "Send video" %>
</div>
</div>
<% button_submit %>
</form>

<button type="button" class="btn btn-dark border mb-2" title="Send to FTP" data-sendto="ftp">Test</button>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get $domain" %>
</div>

<%in _footer.cgi %>
