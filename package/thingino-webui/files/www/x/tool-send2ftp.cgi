#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to FTP"

defaults() {
	default_for "ftp_port" "21"
	default_for "ftp_template" "${network_hostname}-%Y%m%d-%H%M%S"
	default_for "ftp_send_video" "false"
	[ -z "$ftp_user" ] && ftp_user="anonymous" && ftp_password="anonymous"
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	read_from_post "ftp" "host password path port send_video template user"

	[ "true" = "$ftp_send2ftp"  ] && error_if_empty "$ftp_ftphost" "FTP address cannot be empty."
	[ "true" = "$ftp_send2tftp" ] && error_if_empty "$ftp_tftphost" "TFTP address cannot be empty."
	[ "true" = "$ftp_save4web"  ] && error_if_empty "$ftp_localpath" "Local path cannot be empty."

	defaults

	if [ -z "$error" ]; then
		save2config "
ftp_host=\"$ftp_host\"
ftp_password=\"$ftp_password\"
ftp_path=\"$ftp_path\"
ftp_port=\"$ftp_port\"
ftp_send_video=\"$ftp_send_video\"
ftp_template=\"$ftp_template\"
ftp_user=\"$ftp_user\"
"
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

<button type="button" class="btn btn-dark border mb-2" title="Send to FTP" data-sendto="ftp">Test</button>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "grep ^ftp_ $CONFIG_FILE" %>
</div>

<%in _footer.cgi %>
