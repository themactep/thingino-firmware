#!/usr/bin/haserl
<%in p/common.cgi %>
<%
plugin="admin"
page_title="Admin profile"
params="name email telegram"

tmp_file=/tmp/${plugin}.conf
config_file="${ui_config_dir}/${plugin}.conf"
[ ! -f "$config_file" ] && touch $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	# parse values from parameters
	for p in $params; do
		eval ${plugin}_${p}=\$POST_${plugin}_${p}
		sanitize "${plugin}_${p}"
	done; unset p

	[ -z "$admin_name"  ] && set_error_flag "Admin name cannot be empty."
	[ -z "$admin_email" ] && set_error_flag "Admin email cannot be empty."
	# [ -z "$admin_telegram" ] && error="Admin telegram username cannot be empty."

	# add @ to Telegram username, if missed
	[ -n "$admin_telegram" ] && [ "${admin_telegram:0:1}" != "@" ] && admin_telegram="@$admin_telegram"

	if [ -z "$error" ]; then
		# create temp config file
		:>$tmp_file
		for p in $params; do
			echo "${plugin}_${p}=\"$(eval echo \$${plugin}_${p})\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		update_caminfo
		redirect_back "success" "Admin profile updated."
	fi
else
	include $config_file
fi
%>
<%in p/header.cgi %>

<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<h3>Settings</h3>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "update" %>
<% field_text "admin_name" "Admin's full name" "will be used for sending emails" %>
<% field_text "admin_email" "Admin's email address" %>
<% field_text "admin_telegram" "Admin's nick on Telegram" %>
<% button_submit %>
</form>
</div>
<div class="col">
<h3>Config file</h3>
<% ex "cat $config_file" %>
</div>
</div>

<%in p/footer.cgi %>
