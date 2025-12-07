#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to email"

defaults() {
	default_for send_photo "false"
	default_for send_video "true"
	default_for from_name "Camera $network_hostname"
	default_for trust_cert "false"
	default_for port "25"
	default_for to_name "Camera admin"
	default_for subject "Snapshot from $network_hostname"
}

read_config() {
        local CONFIG_FILE=/etc/send2.json
        [ -f "$CONFIG_FILE" ] || return

        from_address=$(jct $CONFIG_FILE get email.from_address)
           from_name=$(jct $CONFIG_FILE get email.from_name)
          to_address=$(jct $CONFIG_FILE get email.to_address)
             to_name=$(jct $CONFIG_FILE get email.to_name)
             subject=$(jct $CONFIG_FILE get email.subject)
                body=$(jct $CONFIG_FILE get email.body)
                host=$(jct $CONFIG_FILE get email.host)
                port=$(jct $CONFIG_FILE get email.port)
            username=$(jct $CONFIG_FILE get email.username)
            password=$(jct $CONFIG_FILE get email.password)
             use_ssl=$(jct $CONFIG_FILE get email.use_ssl)
          trust_cert=$(jct $CONFIG_FILE get email.trust_cert)
          send_photo=$(jct $CONFIG_FILE get email.send_photo)
          send_video=$(jct $CONFIG_FILE get email.send_video)
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	host="$POST_host"
	port="$POST_port"
	username="$POST_username"
	password="$POST_password"
	use_ssl="$POST_use_ssl"
	trust_cert="$POST_trust_cert"
	from_name="$POST_from_name"
	from_address="$POST_from_address"
	to_name="$POST_to_name"
	to_address="$POST_to_address"
	subject="$POST_subject"
	body="$POST_body"
	send_photo="$POST_send_photo"
	send_video="$POST_send_video"

	# normalize
	body="$(echo "$body" | tr "\r?\n" " ")"

	error_if_empty "$host" "SMTP host cannot be empty."
	error_if_empty "$from_address" "Sender email address cannot be empty."
	error_if_empty "$from_name" "Sender name cannot be empty."
	error_if_empty "$to_address" "Recipient email address cannot be empty."
	error_if_empty "$to_name" "Recipient name cannot be empty."

	defaults

	if [ -z "$error" ]; then
		tmpfile="$(mktemp -u).json"
		jct $tmpfile set email.host "$host"
		jct $tmpfile set email.port "$port"
		jct $tmpfile set email.username "$username"
		jct $tmpfile set email.password "$password"
		jct $tmpfile set email.use_ssl "$use_ssl"
		jct $tmpfile set email.trust_cert "$trust_cert"
		jct $tmpfile set email.from_name "$from_name"
		jct $tmpfile set email.from_address "$from_address"
		jct $tmpfile set email.to_name "$to_name"
		jct $tmpfile set email.to_address "$to_address"
		jct $tmpfile set email.subject "$subject"
		jct $tmpfile set email.body "$body"
		jct $tmpfile set email.send_photo "$send_photo"
		jct $tmpfile set email.send_video "$send_video"
		jct /etc/send2.json import $tmpfile
		rm $tmpfile

		redirect_to $SCRIPT_NAME "success" "Data updated."
	else
		redirect_to $SCRIPT_NAME "danger" "Error: $error"
	fi
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3 g-4 mb-4">
<div class="col">
<div class="row g-1">
<div class="col-10"><% field_text "host" "SMTP server FQDN or IP address" %></div>
<div class="col-2"><% field_text "port" "Port" %></div>
</div>
<% field_text "username" "SMTP username" %>
<% field_password "password" "SMTP password" %>
<% field_switch "use_ssl" "Use TLS/SSL" %>
<% field_switch "trust_cert" "Ignore SSL certificate validity" %>
</div>
<div class="col">
<% field_text "from_name" "Sender's name" "Use a real email address where bounce reports can be sent to." %>
<% field_text "from_address" "Sender's address" %>
<% field_text "to_name" "Recipient's name" %>
<% field_text "to_address" "Recipient's address" %>
</div>
<div class="col">
<% field_text "subject" "Email subject" %>
<% field_textarea "body" "Email text" "Line breaks will be replaced with whitespaces." %>
<p class="label">Attachment</p>
<% field_switch "send_photo" "Attach snapshot" %>
<% field_switch "send_video" "Attach video" %>
</div>
</div>
<% button_submit %>
</form>

<button type="button" class="btn btn-dark border mb-2" title="Send to email" data-sendto="email">Test</button>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct /etc/send2.json get email" %>
</div>

<script>
$('#body').style.height = "6rem";
$('#use_ssl').addEventListener('change', ev => {
	const el=$('#port');
	if (ev.target.checked) {
		if (el.value === "25") el.value="465";
	} else {
		if (el.value === "465") el.value="25";
	}
});
</script>

<%in _footer.cgi %>
