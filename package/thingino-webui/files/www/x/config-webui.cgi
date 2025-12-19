#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Web Interface"

domain="webui"
config_file="/etc/thingino.json"
temp_config_file="/tmp/$domain.json"

defaults() {
	[ -z "$theme" ] && theme="auto"
	[ -z "$paranoid" ] && paranoid="false"
	[ -z "$username" ] && username="$USER"
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

	theme="$(get_value "theme")"
	paranoid="$(get_value "paranoid")"
	username="$(get_value "username")"
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	paranoid="$POST_paranoid"
	theme="$POST_theme"

	defaults

	if [ -z "$error" ]; then
		save_config "paranoid" "$paranoid"
		save_config "theme" "$theme"

		jct "$config_file" import "$temp_config_file"
		rm "$temp_config_file"

		new_password="$POST_password_new"
		[ -n "$new_password" ] && echo "root:$new_password" | chpasswd -c sha512 >/dev/null

		redirect_to $SCRIPT_NAME "success" "Data updated."
	else
		redirect_to $SCRIPT_NAME "danger" "Error: $error"
	fi
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<div class="string mb-2">
<label for="username" class="form-label">Web UI username</label>
<input type="text" id="username" name="username" value="<%= $username %>" class="form-control" autocomplete="username" disabled>
</div>
<% field_password "password_new" "Password" %>
</div>
<div class="col">
<% field_select "theme" "Theme" "light,dark,auto" %>
<% field_switch "paranoid" "Paranoid mode" "Isolated from internet by air gap, firewall, VLAN etc." %>
</div>
<div class="col">
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get $domain" %>
<% ex "cat /etc/httpd.conf" %>
<% ex "grep ^$username /etc/shadow" %>
</div>

<%in _footer.cgi %>
