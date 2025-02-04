#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to Yandex Disk"
params="username password path"

config_file="$ui_config_dir/yadisk.conf"
include $config_file

defaults() {
	#
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "yadisk" "$params"

	error_if_empty "$yadisk_username" "Yandex Disk username cannot be empty."
	error_if_empty "$yadisk_password" "Yandex Disk password cannot be empty."

	defaults

	if [ -z "$error" ]; then
		tmp_file=$(mktemp -u)
		[ -f "$config_file" ] && cp "$config_file" "$tmp_file"
		for p in $params; do
			sed -i -r "/^yadisk_$p=/d" "$tmp_file"
			echo "yadisk_$p=\"$(eval echo \$yadisk_$p)\"" >> "$tmp_file"
		done
		mv $tmp_file $config_file
	fi
	redirect_to $SCRIPT_NAME
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<% field_text "yadisk_username" "Yandex Disk username" %>
<% field_password "yadisk_password" "Yandex Disk password" %>
</div>
<div class="col">
<% field_text "yadisk_path" "Yandex Disk path" "$STR_SUPPORTS_STRFTIME" %>
</div>
<div class="col">
<div class="alert alert-info">
<p>Access to your Yandex Disk from thingino requires a dedicated password for application.
Learn how to create it on <a href="https://yandex.com/support/id/authorization/app-passwords.html">this page</a>.</p>
<% wiki_page "Plugin:-Yandex-Disk" %>
</div>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "cat $config_file" %>
</div>

<%in _footer.cgi %>
