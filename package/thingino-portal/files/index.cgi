#!/bin/haserl
<%
timestamp=$(date +%s)
ttl_in_sec=120

# POST request older than 2 minutes
if [ "POST" = "$REQUEST_METHOD" ] && [ -n "$POST_timestamp" ] && [ "$POST_timestamp" -lt "$((timestamp - $ttl_in_sec))" ]; then
	http_header="HTTP/1.1 303 See Other"
	http_redirect="Location: $SCRIPT_NAME"

# POST request with initial or confirmed data
elif [ "POST" = "$REQUEST_METHOD" ]; then
	wlanssid="$POST_wlanssid"
	wlanpass="$POST_wlanpass"
	hostname="$POST_hostname"
	rootpass="$POST_rootpass"
	rootpkey="$POST_rootpkey"
	timezone="$POST_timezone"
	frombrowser="$POST_frombrowser"

	# POST request with confirmed data
	if [ "save" = "$POST_mode" ]; then
		tempfile=$(mktemp)
		printf "wlanssid %s\nwlanpass %s\nhostname %s\ntimezone %s\n" "$wlanssid" "$wlanpass" "$hostname" "$timezone" > "$tempfile"
		fw_setenv -s $tempfile
		echo "root:$rootpass" | chpasswd -c sha512
		echo "$rootpkey" > /root/.ssh/authorized_keys
		sed -i "s/^ifs=.*$/ifs=wlan0/" /etc/onvif.conf

		reboot -d 2 &

		http_header="HTTP/1.1 303 See Other"
		http_redirect="Location: $SCRIPT_NAME"
	else
		http_header="HTTP/1.1 200 OK"
		http_redirect=""
	fi

# Initial GET request
elif [ "GET" = "$REQUEST_METHOD" ]; then
	wlanssid=$(get wlanssid | tr -d '\n')
	wlanpass=$(get wlanpass | tr -d '\n')
	wlanmac=$(get wlanmac | tr -d '\n')
	hostname=$(get hostname | tr -d '\n')
	[ -z "$hostname" ] && hostname=$(hostname | tr -d '\n')

	http_header="HTTP/1.1 200 OK"
	http_redirect=""
fi

	echo "$http_header
Content-type: text/html; charset=UTF-8
Cache-Control: no-store
Pragma: no-cache
Date: $(TZ=GMT0 date +"%a, %d %b %Y %T %Z" | tr -d '\n')
Server: Tingino Portal
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
.container {max-width:24rem}
.form-label {margin:0}
h1,h2 {font-weight:400}
h1 {font-size:3rem}
h1 span {color:#f80}
h2 {font-size:1.3rem}
</style>
<script src="/a/bootstrap.bundle.min.js"></script>
</head>
<body>
<header class="my-4 text-center">
<div class="container">
<h1>th<span>ing</span>ino</h1>
<h2>Initial Configuration</h2>
</div>
</header>
<main>
<div class="container">
<%
# GET request with configuration saved
if [ "GET" = "$REQUEST_METHOD" ] && [ -n "$wlanssid" ] && [ -n "$wlanpass" ]; then
%>
<h3>Configuration Completed</h3>
<p class="lead">Your camera is rebooting to connect to your wireless network.</p>
<p>To get started, go to <a href="http://<%= $hostname %>.local/">http://<%= $hostname %>.local/</a>
 or find the IP address that the DHCP server (usually in your wireless router) has assigned to the camera.</p>
<p class="alert alert-warning text-center">The MAC address is <%= $wlanmac %></p>
<p>Find more information <a href="https://github.com/themactep/thingino-firmware/wiki/">in the project Wiki</a>.</p>
<%
# Initial GET request or POST request to edit data
elif [ "GET" = "$REQUEST_METHOD" ] || [ "edit" = "$POST_mode" ]; then
%>
<p class="alert alert-warning text-center">Your MAC address is <% get "wlanmac" %></p>
<p class="alert alert-warning text-center">For security, portal will automatically shutoff after 5 minutes. Power cycle camera to re-activate portal.</p>
<form action="<%= $SCRIPT_NAME %>" method="post" class="my-3 needs-validation" novalidate style="max-width:26rem">
<div class="mb-2">
<label class="form-label">Wireless Network Name (SSID)</label>
<input class="form-control bg-light text-dark" type="text" name="wlanssid" value="<%= $wlanssid %>" required autocapitalize="none">
<div class="invalid-feedback">Please enter network name</div>
</div>
<div class="mb-2">
<label class="form-label">Wireless Network Password</label>
<input class="form-control bg-light text-dark" type="text" name="wlanpass" id="wlanpass" value="<%= $wlanpass %>" required autocapitalize="none" minlength="8" pattern=".{8,64}">
<div class="invalid-feedback">Please enter a password 8 - 64 characters</div>
</div>
<div class="mb-2">
<label class="form-label">User <b>root</b> Password</label>
<input class="form-control bg-light text-dark" type="text" name="rootpass" id="rootpass" value="<%= $rootpass %>" required autocapitalize="none">
<div class="invalid-feedback">Please enter password</div>
</div>
<div class="mb-2">
<label class="form-label">Camera Hostname</label>
<input class="form-control bg-light text-dark" type="text" name="hostname" value="<%= $hostname %>" required autocapitalize="none">
<div class="invalid-feedback">Please enter hostname</div>
</div>
<div class="my-3">
<div class="form-check form-switch">
<input class="form-check-input" type="checkbox" role="switch" id="frombrowser" name="frombrowser" value="true"<% [ "false" != $frombrowser ] && echo " checked" %>>
<label class="form-check-label" for="frombrowser">Pick up time settings from the browser</label>
</div>
</div>
<div class="mb-4">
<label class="form-label">User <b>root</b> Public SSH Key (optional)</label>
<textarea class="form-control bg-light text-dark text-break" name="rootpkey" id="rootpkey" rows="3"><%= $rootpkey %></textarea>
</div>
<input type="hidden" name="timezone" id="timezone" value="">
<input type="hidden" name="timestamp" value="<%= $timestamp %>">
<input type="submit" value="Save Credentials" class="btn btn-primary">
</form>

<script>
document.querySelector("#frombrowser").addEventListener("change", ev => {
	const tz = document.querySelector("#timezone");
	if (ev.target.checked) {
		tz.value = Intl.DateTimeFormat().resolvedOptions().timeZone.replaceAll('_', ' ');
	} else {
		tz.value = "";
	}
});

(() => {
	const forms = document.querySelectorAll('.needs-validation');
	Array.from(forms).forEach(form => {
		form.addEventListener('submit', event => {
			if (!form.checkValidity()) {
				event.preventDefault()
				event.stopPropagation()
			}
			form.classList.add('was-validated')
		}, false)
	})
})()
</script>
<%
# POST request with initial data
elif [ "POST" = "$REQUEST_METHOD" ] && [ "save" != "$POST_mode" ]; then %>
<div class="alert alert-secondary my-3">
<h3>Ready to connect</h3>
<p>Please double-check the entered data and correct it if you see an error!</p>
<dl>
<dt>Wireless Network SSID</dt>
<dd class="lead"><%= $wlanssid %></dd>
<dt>Wireless Network Password</dt>
<dd class="lead text-break"><%= $wlanpass %></dd>
<dt>User <b>root</b> Password</dt>
<dd class="lead"><%= $rootpass %></dd>
<dt>Camera Hostname</dt>
<dd class="lead"><%= $hostname %></dd>
<dt>Time settings</dt>
<dd class="lead"><%= $timezone %></dd>
<dt>User <b>root</b> Public SSH Key</dt>
<dd class="lead text-break"><%= $rootpkey %></dd>
</dl>
<div class="row text-center">
<div class="col my-2">
<form action="<%= $SCRIPT_NAME %>" method="POST">
<input type="hidden" name="mode" value="edit">
<input type="hidden" name="timestamp" value="<%= $timestamp %>">
<input type="hidden" name="wlanssid" value="<%= $wlanssid %>">
<input type="hidden" name="wlanpass" value="<%= $wlanpass %>">
<input type="hidden" name="hostname" value="<%= $hostname %>">
<input type="hidden" name="rootpass" value="<%= $rootpass %>">
<input type="hidden" name="rootpkey" value="<%= $rootpkey %>">
<input type="hidden" name="timezone" value="<%= $timezone %>">
<input type="hidden" name="frombrowser" value="<%= $frombrowser %>">
<input type="submit" class="btn btn-danger" value="Edit data">
</form>
</div>
<div class="col my-2">
<form action="<%= $SCRIPT_NAME %>" method="POST">
<input type="hidden" name="mode" value="save">
<input type="hidden" name="timestamp" value="<%= $timestamp %>">
<input type="hidden" name="wlanssid" value="<%= $wlanssid %>">
<input type="hidden" name="wlanpass" value="<%= $wlanpass %>">
<input type="hidden" name="hostname" value="<%= $hostname %>">
<input type="hidden" name="rootpass" value="<%= $rootpass %>">
<input type="hidden" name="rootpkey" value="<%= $rootpkey %>">
<input type="hidden" name="timezone" value="<%= $timezone %>">
<input type="submit" class="btn btn-success" value="Proceed">
</form>
</div>
</div>
</div>
<% fi %>
</div>
</main>
</body>
</html>
