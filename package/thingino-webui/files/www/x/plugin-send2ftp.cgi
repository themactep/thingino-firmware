#!/bin/haserl
<%in _common.cgi %>
<%
plugin="ftp"
plugin_name="Send to FTP"
page_title="Send to FTP"
params="host password path port send_video template user"

config_file="$ui_config_dir/ftp.conf"
include $config_file

defaults() {
	default_for "ftp_port" "21"
	default_for "ftp_template" "${network_hostname}-%Y%m%d-%H%M%S"
	default_for "ftp_send_video" "false"
	[ -z "$ftp_user" ] && ftp_user="anonymous" && ftp_password="anonymous"
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "ftp" "$params"

	[ "true" = "$ftp_send2ftp"  ] && error_if_empty "$ftp_ftphost" "FTP address cannot be empty."
	[ "true" = "$ftp_send2tftp" ] && error_if_empty "$ftp_tftphost" "TFTP address cannot be empty."
	[ "true" = "$ftp_save4web"  ] && error_if_empty "$ftp_localpath" "Local path cannot be empty."

	defaults

	if [ -z "$error" ]; then
		tmp_file=$(mktemp -u)
		[ -f "$config_file" ] && cp "$config_file" "$tmp_file"
		for p in $params; do
			sed -i -r "/^ftp_$p=/d" "$tmp_file"
			echo "ftp_$p=\"$(eval echo \$ftp_$p)\"" >> "$tmp_file"
		done
		mv $tmp_file $config_file
	fi
	redirect_to $SCRIPT_NAME
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3">
<div class="col">
<div class="row g-1">
<div class="col-10"><% field_text "ftp_host" "FTP server FQDN or IP address" %></div>
<div class="col-2"><% field_text "ftp_port" "Port" %></div>
</div>
<% field_text "ftp_user" " FTP username" %>
<% field_password "ftp_password" "FTP password" %>
</div>
<div class="col">
<% field_text "ftp_path" "Path on FTP server" "relative to FTP root directory" %>
<% field_text "ftp_template" "Filename template" "$STR_SUPPORTS_STRFTIME" "do not use extension" %>
<% field_radio "ftp_send_video" "Upload video file" %>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "cat $config_file" %>
</div>

<%in _footer.cgi %>
