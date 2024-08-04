#!/usr/bin/haserl
<%in p/common.cgi %>
<%
page_title="Hostname"

function check_hostname() {
	[ -z "$hostname" ] && hostname="thingino-"
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	# values from the form
	hostname=$POST_hostname

	# default values
	check_hostname

	# update env
	if [ "$hostname" != "$(fw_printenv -n hostname)" ]; then
		tmpfile=$(mktemp)
		echo "hostname $hostname" >> $tmpfile
		fw_setenv -s $tmpfile
		rm $tmpfile
	fi

	# update /etc/hostname
	if [ "$hostname" != "$(cat /etc/hostname)" ]; then
		echo "$hostname" > /etc/hostname
	fi

	# update /etc/hosts
	if [ "$hostname" != "$(sed -nE "s/^127.0.1.1\t(.*)$/\1/p" /etc/os-release)" ]; then
		sed -i "/^127.0.1.1/s/\t.*$/\t$hostname/" /etc/hosts
	fi

	# update os-release
	if [ "$hostname" != "$(sed -nE "s/^HOSTNAME=(.*)$/\1/p" /etc/os-release)" ]; then
		sed -i "/^HOSTNAME/s/=.*$/=$hostname/" /etc/os-release
		. /etc/os-release
	fi

	# update hostname
	hostname "$hostname"
fi

# read data from env
hostname=$(get hostname)

# default values
check_hostname
%>
<%in p/header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<% field_text "hostname" "Hostname" %>
</div>
<div class="col">
<% ex "fw_printenv -n hostname" %>
<% ex "hostname" %>
</div>
<div class="col">
<% ex "cat /etc/hostname" %>
<% ex "echo \$HOSTNAME" %>
<% ex "grep 127.0.1.1 /etc/hosts" %>
</div>
</div>
<% button_submit %>
</form>

<%in p/footer.cgi %>
