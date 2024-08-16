#!/usr/bin/haserl --upload-limit=100 --upload-dir=/tmp
<%in _common.cgi %>
<%
plugin="webui"
plugin_name="User interface settings"
page_title="Web Interface Settings"

tmp_file=/tmp/${plugin}.conf

config_file="${ui_config_dir}/${plugin}.conf"
[ ! -f "$config_file" ] && touch $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	case "$POST_action" in
		access)
			new_password="$POST_ui_password_new"
			[ -z "$new_password" ] && redirect_to $SCRIPT_NAME "danger" "Password cannot be empty!"

			echo "root:${new_password}" | chpasswd -c sha512
			update_caminfo

			redirect_to "/" "success" "Password updated."
			;;
		init)
			update_caminfo
			redirect_to "$HTTP_REFERER" "success" "Environment re-initialized."
			;;
		interface)
			params="level theme"
			for p in $params; do
				eval ${plugin}_${p}=\$POST_${plugin}_${p}
				sanitize "${plugin}_${p}"
			done; unset p

			[ -z "$webui_level" ] && webui_level="user"

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
			;;
		*)
			redirect_to $SCRIPT_NAME "danger" "UNKNOWN ACTION: $POST_action"
			;;
	esac
fi

page_title="Web Interface Settings"

# data for form fields
ui_username="$USER"
%>
<%in _header.cgi %>

<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<h3>Access</h3>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "access" %>
<p class="string">
<label for="ui_username" class="form-label">Username</label>
<input type="text" id="ui_username" name="ui_username" value="<%= $ui_username %>" class="form-control" autocomplete="username" disabled>
</p>
<% field_password "ui_password_new" "Password" %>
<% button_submit %>
</form>
</div>
<div class="col">
<h3>Interface Details</h3>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "interface" %>
<% field_select "webui_level" "Level" "user,expert" %>
<% field_select "webui_theme" "Theme" "light,dark" %>
<% button_submit %>
</form>
</div>
<div class="col">
<h3>Configuration</h3>
<%
ex "cat /etc/httpd.conf"
ex "cat $config_file"
%>
</div>
</div>

<%in _footer.cgi %>
