#!/bin/haserl --upload-limit=100 --upload-dir=/tmp
<%in _common.cgi %>
<%
plugin="webui"
plugin_name="User interface settings"
page_title="Web Interface Settings"

config_file="$ui_config_dir/$plugin.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	params="theme"
	read_from_post "$plugin" "$params"

	if [ -z "$error" ]; then
		tmp_file=$(mktemp)
		for p in $params; do
			echo "${plugin}_$p=\"$(eval echo \$${plugin}_$p)\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		new_password="$POST_ui_password_new"
		if [ -n "$new_password" ]; then
			echo "root:$new_password" | chpasswd -c sha512
			pwbackup save
		fi

		update_caminfo
		redirect_back "success" "Data updated."
	fi
fi

# data for form fields
ui_username="$USER"
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<div class="string mb-2">
<label for="ui_username" class="form-label">Web UI username</label>
<input type="text" id="ui_username" name="ui_username" value="<%= $ui_username %>" class="form-control" autocomplete="username" disabled>
</div>
<% field_password "ui_password_new" "Password" %>
</div>
<div class="col">
<% field_select "webui_theme" "Theme" "light,dark,auto" %>
</div>
<div class="col">
<% field_password "ws_token" "Websockets security token" "FIXME: a stub" %>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "cat /etc/httpd.conf" %>
<% ex "cat $config_file" %>
</div>

<%in _footer.cgi %>
