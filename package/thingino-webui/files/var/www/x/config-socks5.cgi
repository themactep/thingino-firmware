#!/bin/haserl
<%in _common.cgi %>
<%
plugin="socks5"
page_title="SOCKS5 proxy"
params="enabled host port username password"

config_file="$ui_config_dir/socks5.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	tmp_file=$(mktemp)
	for v in $params; do
		eval echo "socks5_$v=\\\"\$POST_socks5_$v\\\"" >>$tmp_file
	done
	mv $tmp_file $config_file
	redirect_to $SCRIPT_NAME
fi
%>

<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<% field_hidden "action" "update" %>
<% field_text "socks5_host" "SOCKS5 Host" %>
<% field_text "socks5_port" "SOCKS5 Port" "1080" %>
</div>
<div class="col">
<% field_text "socks5_username" "SOCKS5 Username" %>
<% field_password "socks5_password" "SOCKS5 Password" %>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "cat $config_file" %>
</div>

<%in _footer.cgi %>
