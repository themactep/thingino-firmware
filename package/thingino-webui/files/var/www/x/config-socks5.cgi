#!/bin/haserl
<%in _common.cgi %>
<%
plugin="socks5"
page_title="SOCKS5 proxy"
params="enabled host port username password"

config_file="$ui_config_dir/$plugin.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	tmp_file=$(mktemp)
	for v in $params; do
		eval echo "${plugin}_$v=\\\"\$POST_${plugin}_$v\\\"" >>$tmp_file
	done
	mv $tmp_file $config_file
	redirect_to $SCRIPT_NAME
fi
%>

<%in _header.cgi %>

<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "update" %>
<% field_text "socks5_host" "SOCKS5 Host" %>
<% field_text "socks5_port" "SOCKS5 Port" "1080" %>
<% field_text "socks5_username" "SOCKS5 Username" %>
<% field_password "socks5_password" "SOCKS5 Password" %>
<% button_submit %>
</form>
</div>
<div class="col">
<% ex "cat $config_file" %>
</div>
</div>

<%in _footer.cgi %>
