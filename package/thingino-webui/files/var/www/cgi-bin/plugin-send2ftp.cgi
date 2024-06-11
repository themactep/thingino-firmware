#!/usr/bin/haserl
<%in p/common.cgi %>
<%
plugin="ftp"
plugin_name="Send to FTP"
page_title="Send to FTP"
params="enabled host user password path port socks5_enabled template"

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
	if [ "true" = "$ftp_enabled" ]; then
		[ "true" = "$ftp_send2ftp" ] && [ -z "$ftp_ftphost" ] && set_error_flag "FTP address cannot be empty."
		[ "true" = "$ftp_send2tftp" ] && [ -z "$ftp_tftphost" ] && set_error_flag "TFTP address cannot be empty."
		[ "true" = "$ftp_save4web" ] && [ -z "$ftp_localpath" ] && set_error_flag "Local path cannot be empty."
	fi
	[ -z "$ftp_template" ] && ftp_template="${network_hostname}-%Y%m%d-%H%M%S.jpg"

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
	[ -z "$ftp_port" ] && ftp_port="21"
	[ -z "$ftp_template" ] && ftp_template="${network_hostname}-%Y%m%d-%H%M%S.jpg"
fi
%>
<%in p/header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_switch "ftp_enabled" "Enable sending to FTP server" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<% field_text "ftp_host" "FTP host" %>
<% field_text "ftp_port" "FTP port" %>
<% field_text "ftp_user" "FTP user" %>
<% field_password "ftp_password" "FTP password" %>
</div>
<div class="col">
<% field_text "ftp_path" "FTP path" "relative to FTP root directory" %>
<% field_text "ftp_template" "Filename template" ""$STR_SUPPORTS_STRFTIME"" %>
<% field_switch "ftp_socks5_enabled" "Use SOCKS5" "<a href=\"network-socks5.cgi\">Configure</a> SOCKS5 access" %>
</div>
<div class="col">
<% ex "cat $config_file" %>
<% button_webui_log %>
</div>
</div>
<% button_submit %>
</form>

<%in p/footer.cgi %>
