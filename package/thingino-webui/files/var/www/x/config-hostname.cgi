#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Hostname"

check_hostname() {
	default_for hostname "thingino-"
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	hostname=$POST_hostname
	check_hostname
	[ "$hostname" = "$(fw_printenv -n hostname)" ] || save2env "hostname $hostname"
	[ "$hostname" = "$(cat /etc/hostname)" ] || echo "$hostname" > /etc/hostname
	[ "$hostname" = "$(sed -nE "s/^127.0.1.1\t(.*)$/\1/p" /etc/os-release)" ] || sed -i "/^127.0.1.1/s/\t.*$/\t$hostname/" /etc/hosts
	[ "$hostname" = "$(sed -nE "s/^HOSTNAME=(.*)$/\1/p" /etc/os-release)" ] || sed -i "/^HOSTNAME/s/=.*$/=$hostname/" /etc/os-release
	. /etc/os-release
	hostname "$hostname"
	redirect_to $SCRIPT_NAME
fi

hostname=$(get hostname)
check_hostname
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<% field_text "hostname" "Hostname" %>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug">
<h4 class="mb-3">Debug info</h4>
<% ex "fw_printenv -n hostname" %>
<% ex "hostname" %>
<% ex "cat /etc/hostname" %>
<% ex "echo \$HOSTNAME" %>
<% ex "grep 127.0.1.1 /etc/hosts" %>
</div>

<%in _footer.cgi %>
