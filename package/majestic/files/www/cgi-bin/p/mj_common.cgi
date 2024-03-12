<%
button_mj_backup() {
	echo "<form action=\"majestic-config-actions.cgi\" method=\"post\"><input type=\"hidden\" name=\"action\" value=\"backup\">"
	button_submit "Backup settings"
	echo "</form>"
}

button_mj_reset() {
	echo "<form action=\"majestic-config-actions.cgi\" method=\"post\"><input type=\"hidden\" name=\"action\" value=\"reset\">"
	button_submit "Reset Majestic" "danger"
	echo "</form>"
}

update_caminfo() {
	local_variables = "mj_version"
	
	mj_version=$($mj_bin_file -v)
}

mj_bin_file=/usr/bin/majestic

include p/mj.cgi
%>
