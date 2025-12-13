#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to FTP"

defaults() {
	default_for "port" "21"
	default_for "template" "${network_hostname}-%Y%m%d-%H%M%S"
	default_for "send_video" "false"
	default_for "send_photo" "false"

	[ -z "$username" ] && username="anonymous" && password="anonymous"
}

read_config() {
	local CONFIG_FILE=/etc/send2.json
	[ -f "$CONFIG_FILE" ] || return

	      host=$(jct $CONFIG_FILE get ftp.host)
	      port=$(jct $CONFIG_FILE get ftp.port)
	  username=$(jct $CONFIG_FILE get ftp.username)
	  password=$(jct $CONFIG_FILE get ftp.password)
	      path=$(jct $CONFIG_FILE get ftp.path)
	  template=$(jct $CONFIG_FILE get ftp.template)
	send_photo=$(jct $CONFIG_FILE get ftp.send_photo)
	send_video=$(jct $CONFIG_FILE get ftp.send_video)
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
		tmpfile="$(mktemp -u).json"
		echo '{}' > $tmpfile
		jct $tmpfile set ftp.host "$host"
		jct $tmpfile set ftp.port "$port"
		jct $tmpfile set ftp.username "$username"
		jct $tmpfile set ftp.password "$password"
		jct $tmpfile set ftp.path "$path"
		jct $tmpfile set ftp.template "$template"
		jct $tmpfile set ftp.send_photo "$send_photo"
		jct $tmpfile set ftp.send_video "$send_video"
		jct /etc/send2.json import $tmpfile
		rm $tmpfile

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
<% field_switch "send_photo" "Send snapshot" %>
<% field_switch "send_video" "Send video" %>
</div>
</div>
<% button_submit %>
</form>

<button type="button" class="btn btn-dark border mb-2" title="Send to FTP" data-sendto="ftp">Test</button>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct /etc/send2.json get ftp" %>
</div>

<%in _footer.cgi %>
