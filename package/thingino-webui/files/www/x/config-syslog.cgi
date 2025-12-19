#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Remote Logging"

domain="rsyslog"
config_file="/etc/thingino.json"
temp_config_file="/tmp/$domain.json"

defaults() {
	[ -z "$enabled" ] && enabled="false"
	[ -z "$port" ] && port="514"
	[ -z "$file" ] && file="false"
}

save_config() {
	[ -f "$temp_config_file" ] || echo '{}' > "$temp_config_file"
	jct "$temp_config_file" set "$domain.$1" "$2" >/dev/null 2>&1
}

get_value() {
	jct $config_file get "$domain.$1"
}

read_config() {
	[ -f "$config_file" ] || return

	enabled="$(get_value "enabled")"
	host="$(get_value "host")"
	port="$(get_value "port")"
	file="$(get_value "file")"
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	enabled="$POST_enabled"
	host="$POST_host"
	port="$POST_port"
	file="$POST_file"

	if [ "true" = "$enabled" ]; then
		error_if_empty "$host" "Remote host cannot be empty"
	fi

	defaults

	if [ -z "$error" ]; then
		save_config "enabled" "$enabled"
		save_config "host" "$host"
		save_config "port" "$port"
		save_config "file" "$file"

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

<div class="row row-cols-1 row-cols-lg-3">
<div class="col">
<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row g-1">
<div class="col-10"><% field_text "host" "Syslog server FQDN or IP address" %></div>
<div class="col-2"><% field_text "port" "Port" %></div>
</div>
<% field_switch "enabled" "Enable remote logging" %>
<% field_switch "file" "Enable local logging" %>

<% button_submit %>
</form>
</div>
</div>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get $domain" %>
</div>

<%in _footer.cgi %>
