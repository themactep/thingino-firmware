#!/bin/haserl
<%
. /usr/share/common

hostname=$(hostname)
image_id=$(awk -F= '/IMAGE_ID/{print $2}' $OS_RELEASE_FILE)
build_id=$(awk -F= '/BUILD_ID/{print $2}' $OS_RELEASE_FILE | tr -d '"')
timestamp=$(date +%s)
ttl_in_sec=600

sanitize() {
	echo $1 | sed -E 's/([`"])/\\\1/g'
}

html_safe() {
	text=$*
	text=${text//&/\&amp;}
	text=${text//\`/\&grave;}
	text=${text//\"/\&quot;}
	text=${text// /\&nbsp;}
	echo $text
}

get_request() {
	[ "GET" = "$REQUEST_METHOD" ]
}

get_request_with_wlan_credentials() {
	get_request && [ -n "$wlan_ssid" ] && [ -n "$wlan_pass" ]
}

get_request_with_wlanap_credentials() {
	get_request && [ -n "$wlanap_ssid" ] && [ -n "$wlanap_pass" ]
}

post_request() {
	[ "POST" = "$REQUEST_METHOD" ]
}

post_request_expired() {
	post_request && [ -n "$POST_timestamp" ] && [ "$POST_timestamp" -lt "$((timestamp - $ttl_in_sec))" ]
}

post_request_to_edit() {
	post_request && [ "edit" = "$POST_mode" ]
}

post_request_to_review() {
	post_request && [ "review" = "$POST_mode" ]
}

post_request_to_save() {
	post_request && [ "save" = "$POST_mode" ]
}

set_error() {
	error_message="$1"
	POST_mode="edit"
}

debug_file=/tmp/portaldebug
post_request && echo "POST request" >> $debug_file
post_request_to_review && echo "POST request to review" >> $debug_file
post_request_to_save && echo "POST request to save" >> $debug_file
post_request_expired && echo "POST request expired" >> $debug_file
get_request && echo "GET request" >> $debug_file
get_request_with_wlan_credentials && echo "GET request with WLAN credentials" >> $debug_file
get_request_with_wlanap_credentials && echo "GET request with WLAN AP credentials" >> $debug_file

if post_request_expired; then
	http_header="HTTP/1.1 303 See Other"
	http_redirect="Location: $SCRIPT_NAME"

elif post_request; then
	hostname="$POST_hostname"
	rootpass="$POST_rootpass"
	rootpkey="$POST_rootpkey"
	timezone="$POST_timezone"
	wlanap_enabled="$POST_wlanap_enabled"
	wlanap_pass="$POST_wlanap_pass"
	wlanap_ssid="$POST_wlanap_ssid"
	wlan_pass="$POST_wlan_pass"
	wlan_ssid="$POST_wlan_ssid"

	bad_chars=$(echo "$hostname" | sed 's/[0-9A-Z\.-]//ig')
	[ -z "$bad_chars" ] || set_error "Hostname cannot contain $bad_chars"

	if [ -z "$error_message" ] && post_request_to_save; then
		# update hostname
		hostname "$hostname"
		echo "$hostname"> /etc/hostname

		# update wlan settings in environment
		temp_file=$(mktemp -u)
		if [ "true" = "$wlanap_enabled" ]; then
			wlanap_pass=$(convert_psk "$wlanap_ssid" "$wlanap_pass")
			printf "wlanap_ssid %s\nwlanap_pass %s\n" \
				"$wlanap_ssid" "$wlanap_pass" > $temp_file
		else
			wlan_pass=$(convert_psk "$wlan_ssid" "$wlan_pass")
			printf "wlan_ssid %s\nwlan_pass %s\n" \
				"$wlan_ssid" "$wlan_pass" > $temp_file
		fi
		fw_setenv -s $temp_file
		rm -f $temp_file

		# set wlanap status
		conf s wlanap_enabled $wlanap_enabled

		# update env dump
		refresh_env_dump

		# update timezone
		echo "$timezone" > /etc/timezone

		# update root password
		echo "root:$rootpass" | chpasswd -c sha512
		echo "$rootpkey" | tr -d '\r' | sed 's/^ //g' > /root/.ssh/authorized_keys

		# update interface for onvif
		sed -i "s/^ifs=.*$/ifs=wlan0/" /etc/onvif.conf

		# done
		http_header="HTTP/1.1 303 See Other"
		http_redirect="Location: $SCRIPT_NAME"
		reboot -d 2 &
	else
		http_header="HTTP/1.1 200 OK"
		http_redirect=""
	fi

elif get_request; then
	http_header="HTTP/1.1 200 OK"
	http_redirect=""
fi

echo "$http_header
Content-type: text/html; charset=UTF-8
Cache-Control: no-store
Pragma: no-cache
Date: $(TZ=GMT0 date +"%a, %d %b %Y %T %Z" | tr -d '\n')
Server: Thingino Portal
$http_redirect
"
	[ -n "$http_redirect" ] && exit 0
%>
<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
<head>
<meta charset="utf-8">
<meta content="width=device-width,initial-scale=1" name="viewport">
<title>Thingino Initial Configuration</title>
<link rel="stylesheet" href="/a/bootstrap.min.css">
<style>
h1,h2 {font-weight:400}
h1 {font-size:3rem}
h1 span {color:#f80}
h2 {font-size:1.3rem}
.container {max-width:26rem}
.form-label {margin:0}
#logo {max-width:16rem}
#verify dd, b {color:#f80;font-weight:700}
#verify dd#pkey {max-height:5em;overflow:auto;font-size:medium}
</style>
<script src="/a/bootstrap.bundle.min.js"></script>
</head>
<body>
<header class="my-4 text-center">
<div class="container">
<h1><img src="/a/logo.svg" alt="Thingino Logo" class="img-fluid" id="logo"></h1>
<h2>Initial Configuration</h2>
</div>
</header>
<main>
<div class="container">

<% if get_request_with_wlan_credentials; then %>

<div class="alert alert-success text-center">
<h3>Configuration Completed</h3>
<p class="lead">Your camera is rebooting to connect to your wireless network.</p>
<p class="alert alert-warning mb-0">The MAC address is<br><span class="lead"><%= $wlan_mac %></span></p>
</div>

<p>To get started, just tap the reset button on your camera. If it's connected to the internet, it'll tell
 you its IP address. If you're not hearing that, no worries! Find the IP address among DHCP server leases
 (usually in your wireless router).</p>

<p>For configuration information and troubleshooting steps please refer to
 <a href="https://github.com/themactep/thingino-firmware/wiki/">the project Wiki</a>.</p>

<% elif get_request_with_wlanap_credentials; then %>

<div class="alert alert-success text-center">
<h3>Configuration Completed</h3>
<p class="lead mb-0">Your camera is rebooting to create a wireless access point.</p>
</div>

<p>To start, locate the <b><%= $wlanap_ssid %></b> wireless network on your device,
 connect using your password then open the web interface at <b>http://thingino.local/</b>
 using login <b>root</b> and the password you have just set up for that user.</p>

<% elif get_request || post_request_to_edit; then %>

<% if [ -n "$error_message" ]; then %>
<p class="alert alert-danger"><%= $error_message %></p>
<% fi %>
<form action="<%= $SCRIPT_NAME %>" method="post" class="my-3 needs-validation" novalidate style="max-width:26rem">
<div class="mb-2">
<label class="form-label">Hostname</label>
<input class="form-control bg-light text-dark" type="text" name="hostname" value="<%= $hostname %>" required autocapitalize="none">
<div class="invalid-feedback">Please enter hostname</div>
</div>
<div class="mb-2">
<label class="form-label">Create a password for user <b>root</b></label>
<input class="form-control bg-light text-dark" type="text" name="rootpass" id="rootpass" value="<%= $rootpass %>" required autocapitalize="none">
<div class="invalid-feedback">Please enter password</div>
</div>
<div class="mb-2">
<label class="form-label"><a data-bs-toggle="collapse" href="#collapse-rootpkey" role="button" aria-expanded="false" aria-controls="collapse-rootpkey">Public SSH Key for user <b>root</b></a> <span class="small">(optional)</span></label>
<div class="collapse" id="collapse-rootpkey">
<textarea class="form-control bg-light text-dark text-break" name="rootpkey" id="rootpkey" rows="3"><%= $rootpkey %></textarea>
</div>
</div>
<ul class="nav nav-underline mb-3" role="tablist">
<li class="nav-item" role="presentation"><button type="button" role="tab" class="nav-link active" aria-current="page" data-bs-toggle="tab" data-bs-target="#wlan-tab-pane" id="wlan-tab">Wi-Fi Network</button></li>
<li class="nav-item" role="presentation"><button type="button" role="tab" class="nav-link" data-bs-toggle="tab" data-bs-target="#wlanap-tab-pane" id="wlanap-tab">Wi-Fi Access Point</button></li>
</ul>
<div class="tab-content" id="wireless-tabs">
<div class="tab-pane fade show active" id="wlan-tab-pane" role="tabpanel" aria-labelledby="wlan-tab" tabindex="0">
<div class="mb-2">
<label class="form-label">Wireless Network Name (SSID)</label>
<input class="form-control bg-light text-dark" type="text" id="wlan_ssid" name="wlan_ssid" value="<%= $wlan_ssid %>" autocapitalize="none" required>
<div class="invalid-feedback">Please enter network name</div>
</div>
<div class="mb-2">
<label class="form-label">Wireless Network Password</label>
<input class="form-control bg-light text-dark" type="text" id="wlan_pass" name="wlan_pass" value="<%= $wlan_pass %>" autocapitalize="none" minlength="8" pattern=".{8,64}" required>
<div class="invalid-feedback">Please enter a password 8 - 64 characters</div>
</div>
</div>
<div class="tab-pane fade" id="wlanap-tab-pane" role="tabpanel" aria-labelledby="wlanap-tab" tabindex="1">
<div class="mb-2 boolean" id="wlanap_enabled_wrap">
<span class="form-check form-switch">
<input type="hidden" id="wlanap_enabled-false" name="wlanap_enabled" value="false">
<input type="checkbox" id="wlanap_enabled" name="wlanap_enabled" value="true" role="switch" class="form-check-input"<% [ "true" = "$wlanap_enabled" ] && echo " checked" %>>
<label for="wlanap_enabled" class="form-check-label">Enable Wireless AP</label>
</span>
</div>
<div class="mb-2">
<label class="form-label">Wireless AP Network Name (SSID)</label>
<input class="form-control bg-light text-dark" type="text" id="wlanap_ssid" name="wlanap_ssid" value="<%= $wlanap_ssid %>" autocapitalize="none">
<div class="invalid-feedback">Please enter network name</div>
</div>
<div class="mb-2">
<label class="form-label">Wireless AP Network Password</label>
<input class="form-control bg-light text-dark" type="text" id="wlanap_pass" name="wlanap_pass" value="<%= $wlanap_pass %>" autocapitalize="none" minlength="8" pattern=".{8,64}">
<div class="invalid-feedback">Please enter a password 8 - 64 characters</div>
</div>
</div>
</div>
<input type="hidden" name="timezone" id="timezone" value="">
<input type="hidden" name="timestamp" value="<%= $timestamp %>">
<input type="hidden" name="mode" value="review">
<input type="submit" value="Save Credentials" class="btn btn-primary my-4">
</form>

<script>
document.querySelector("#timezone").value = Intl.DateTimeFormat().resolvedOptions().timeZone.replaceAll('_', ' ')
document.querySelector("#wlanap_enabled").addEventListener("change", ev => {
	document.querySelector('#wlan_pass').required = !ev.target.checked
	document.querySelector('#wlan_ssid').required = !ev.target.checked
	document.querySelector('#wlanap_pass').required = ev.target.checked
	document.querySelector('#wlanap_ssid').required = ev.target.checked
});
(() => {
	const forms = document.querySelectorAll('.needs-validation');
	Array.from(forms).forEach(form => { form.addEventListener('submit', ev => {
		if (!form.checkValidity()) { ev.preventDefault(); ev.stopPropagation(); }
		form.classList.add('was-validated')}, false)
	})
})()
</script>

<% elif post_request_to_review; then %>

<div class="alert alert-secondary my-3">
<h3>Ready to connect</h3>
<p>Please double-check the entered data and correct it if you see an error!</p>
<dl class="row" id="verify">
<% if [ "true" = "$wlanap_enabled" ]; then %>
<dt>Wireless AP Network SSID</dt>
<dd><%= $wlanap_ssid %></dd>
<dt>Wireless AP Network Password</dt>
<dd class="text-break"><%= $wlanap_pass %></dd>
<% else %>
<dt>Wireless Network SSID</dt>
<dd><%= $wlan_ssid %></dd>
<dt>Wireless Network Password</dt>
<dd class="text-break"><% html_safe $wlan_pass %></dd>
<% fi %>
<dt>User <b>root</b> Password</dt>
<dd><%= $rootpass %></dd>
<dt>Camera Hostname</dt>
<dd><%= $hostname %></dd>
<% if [ -n "$timezone" ]; then %>
<dt>Time zone</dt>
<dd><%= $timezone %></dd>
<% fi %>
<% if [ -n "$rootpkey" ]; then %>
<dt>User <b>root</b> Public SSH Key</dt>
<dd class="small text-break" id="pkey"><%= $rootpkey %></dd>
<% fi %>
</dl>

<div class="row text-center">
<div class="col my-2">
<form action="<%= $SCRIPT_NAME %>" method="POST">
<input type="hidden" name="mode" value="edit">
<input type="hidden" name="hostname" value="<%= $hostname %>">
<input type="hidden" name="rootpass" value="<%= ${rootpass//\"/&quot;} %>">
<input type="hidden" name="rootpkey" value="<%= $rootpkey %>">
<input type="hidden" name="timestamp" value="<%= $timestamp %>">
<input type="hidden" name="timezone" value="<%= $timezone %>">
<input type="hidden" name="wlanap_enabled" value="<%= $wlanap_enabled %>">
<input type="hidden" name="wlanap_pass" value="<%= ${wlanap_pass//\"/&quot;} %>">
<input type="hidden" name="wlanap_ssid" value="<%= ${wlanap_ssid//\"/&quot;} %>">
<input type="hidden" name="wlan_pass" value="<%= ${wlan_pass//\"/&quot;} %>">
<input type="hidden" name="wlan_ssid" value="<%= ${wlan_ssid//\"/&quot;} %>">
<input type="submit" class="btn btn-danger" value="Edit data">
</form>
</div>
<div class="col my-2">
<form action="<%= $SCRIPT_NAME %>" method="POST">
<input type="hidden" name="mode" value="save">
<input type="hidden" name="hostname" value="<%= $hostname %>">
<input type="hidden" name="rootpass" value="<%= ${rootpass//\"/&quot;} %>">
<input type="hidden" name="rootpkey" value="<%= $rootpkey %>">
<input type="hidden" name="timestamp" value="<%= $timestamp %>">
<input type="hidden" name="timezone" value="<%= $timezone %>">
<input type="hidden" name="wlanap_enabled" value="<%= $wlanap_enabled %>">
<input type="hidden" name="wlanap_pass" value="<%= ${wlanap_pass//\"/&quot;} %>">
<input type="hidden" name="wlanap_ssid" value="<%= ${wlanap_ssid//\"/&quot;} %>">
<input type="hidden" name="wlan_pass" value="<%= ${wlan_pass//\"/&quot;} %>">
<input type="hidden" name="wlan_ssid" value="<%= ${wlan_ssid//\"/&quot;} %>">
<input type="submit" class="btn btn-success" value="Proceed">
</form>
</div>
</div>
</div>

<% fi %>

<p class="small text-muted text-center">Built for <%= $image_id %><br><%= $build_id %></p>
</div>
</main>

<div class="offcanvas offcanvas-bottom" tabindex="-1" id="timeout">
<div class="offcanvas-header">
<h5 class="offcanvas-title">Timeout Warning</h5>
<button type="button" class="btn-close" data-bs-dismiss="offcanvas" aria-label="Close"></button>
</div>
<div class="offcanvas-body small">
<p class="alert alert-warning text-center">
For security, portal will automatically shutoff after 5 minutes.
Power cycle camera to re-activate portal.
</p>
</div>
</div>

</body>
</html>
