#!/bin/haserl
<%in _common.cgi %>
<%
plugin="ftp"
plugin_name="Send to FTP"
page_title="Send to FTP"
params="enabled host user password path port socks5_enabled template"

config_file="$ui_config_dir/$plugin.conf"
include $config_file

defaults() {
	default_for "ftp_port" 21
	default_for "ftp_template" "${network_hostname}-%Y%m%d-%H%M%S.jpg"
	[ -z "$ftp_user" ] && ftp_user="anonymous" && ftp_password="anonymous"
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	# parse values from parameters
	read_from_post "$plugin" "$params"

	# validate
	if [ "true" = "$ftp_enabled" ]; then
		[ "true" = "$ftp_send2ftp"  ] && error_if_empty "$ftp_ftphost" "FTP address cannot be empty."
		[ "true" = "$ftp_send2tftp" ] && error_if_empty "$ftp_tftphost" "TFTP address cannot be empty."
		[ "true" = "$ftp_save4web"  ] && error_if_empty "$ftp_localpath" "Local path cannot be empty."
	fi
	defaults

	if [ -z "$error" ]; then
		tmp_file=$(mktemp)
		for p in $params; do
			echo "${plugin}_$p=\"$(eval echo \$${plugin}_$p)\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		update_caminfo
		redirect_back "success" "$plugin_name config updated."
	fi

	redirect_to $SCRIPT_NAME
else
	defaults
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_switch "ftp_enabled" "Enable sending to FTP server" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<div class="row g-1">
<div class="col-10"><% field_text "ftp_host" "Hostname or IP address" %></div>
<div class="col-2"><% field_text "ftp_port" "Port" %></div>
</div>
<% field_text "ftp_user" "Username" %>
<% field_password "ftp_password" "Password" %>
</div>
<div class="col">
<% field_text "ftp_path" "Path" "relative to FTP root directory" %>
<% field_text "ftp_template" "Filename template" "$STR_SUPPORTS_STRFTIME" %>
<% field_switch "ftp_socks5_enabled" "Use SOCKS5" "$STR_CONFIGURE_SOCKS" %>
</div>
<div class="col">
<% ex "cat $config_file" %>
</div>
</div>
<% button_submit %>
</form>

<%in _footer.cgi %>
