#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Prusa Connect"

state_file="/run/prusa-connect/state"
config_file="/etc/prusa-connect.json"
cmd_test_raw=$(printf %s "prusa-connect test" | base64)
cmd_restart_raw=$(printf %s "service prusa-connect restart" | base64)
cmd_uuid_raw=$(printf %s "prusa-connect generate-fingerprint" | base64)
cmd_status_raw=$(printf %s "prusa-connect status" | base64)
cmd_test=$(printf %s "$cmd_test_raw" | sed -e 's/+/%2B/g' -e 's/\//%2F/g' -e 's/=/%3D/g')
cmd_restart=$(printf %s "$cmd_restart_raw" | sed -e 's/+/%2B/g' -e 's/\//%2F/g' -e 's/=/%3D/g')
cmd_uuid=$(printf %s "$cmd_uuid_raw" | sed -e 's/+/%2B/g' -e 's/\//%2F/g' -e 's/=/%3D/g')
cmd_status=$(printf %s "$cmd_status_raw" | sed -e 's/+/%2B/g' -e 's/\//%2F/g' -e 's/=/%3D/g')

state_read() {
	[ -r "$state_file" ] || return
	while IFS='=' read -r key value; do
		case "$key" in
			last_snapshot_status) prusa_state_snapshot_status="$value" ;;
			last_snapshot_ts) prusa_state_snapshot_ts="$value" ;;
			last_info_status) prusa_state_info_status="$value" ;;
			last_info_ts) prusa_state_info_ts="$value" ;;
			enabled) prusa_state_enabled="$value" ;;
			interval) prusa_state_interval="$value" ;;
			info_interval) prusa_state_info_interval="$value" ;;
		esac
	done < "$state_file"
}

state_read

snapshot_time=""
info_time=""
[ -n "$prusa_state_snapshot_ts" ] && [ "$prusa_state_snapshot_ts" -gt 0 ] && snapshot_time=$(time_http "@$prusa_state_snapshot_ts")
[ -n "$prusa_state_info_ts" ] && [ "$prusa_state_info_ts" -gt 0 ] && info_time=$(time_http "@$prusa_state_info_ts")

[ -n "$prusa_state_snapshot_status" ] || prusa_state_snapshot_status="n/a"
[ -n "$prusa_state_info_status" ] || prusa_state_info_status="n/a"
[ -n "$snapshot_time" ] || snapshot_time=""
[ -n "$info_time" ] || info_time=""
sanitize4web snapshot_time
sanitize4web info_time
sanitize4web prusa_state_snapshot_status
sanitize4web prusa_state_info_status

defaults() {
	default_for prusa_connect_enabled "false"
	default_for prusa_connect_interval "${PRUSA_CONNECT_INTERVAL_DEFAULT:-60}"
	default_for prusa_connect_info_interval "${PRUSA_CONNECT_INFO_INTERVAL_DEFAULT:-600}"
	default_for prusa_connect_online_host "$PRUSA_CONNECT_ONLINE_HOST"
	default_for prusa_connect_snapshot_url "$PRUSA_CONNECT_SNAPSHOT_URL"
	default_for prusa_connect_info_url "$PRUSA_CONNECT_INFO_URL"
}

config_get() {
	local key="$1" value
	value=$(jct "$config_file" get "$key" 2>/dev/null)
	case "$value" in
		null)
			value=""
			;;
	esac
	printf '%s\n' "$value"
}

prusa_connect_enabled=$(config_get enabled)
prusa_connect_token=$(config_get token)
prusa_connect_fingerprint=$(config_get fingerprint)
prusa_connect_interval=$(config_get interval)
prusa_connect_info_interval=$(config_get info_interval)
prusa_connect_online_host=$(config_get online_host)
prusa_connect_snapshot_url=$(config_get snapshot_url)
prusa_connect_info_url=$(config_get info_url)
prusa_connect_has_credentials="false"
if [ -n "$prusa_connect_token" ] && [ -n "$prusa_connect_fingerprint" ]; then
	prusa_connect_has_credentials="true"
fi

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""
	read_from_post "prusa_connect" "enabled token fingerprint interval info_interval online_host snapshot_url info_url"
	if [ "true" = "$prusa_connect_enabled" ]; then
		error_if_empty "$prusa_connect_token" "Camera token cannot be empty."
		error_if_empty "$prusa_connect_fingerprint" "Camera fingerprint cannot be empty."
	fi
	defaults
	if [ -z "$error" ]; then
		tmpfile=$(mktemp /tmp/prusa-connect.XXXXXX) || {
			redirect_to $SCRIPT_NAME "danger" "Failed to prepare temporary config."
		}
		if ! cp "$config_file" "$tmpfile" 2>/dev/null; then
			echo '{}' > "$tmpfile"
		fi
		jct "$tmpfile" set enabled "$prusa_connect_enabled"
		jct "$tmpfile" set token "$prusa_connect_token"
		jct "$tmpfile" set fingerprint "$prusa_connect_fingerprint"
		jct "$tmpfile" set interval "$prusa_connect_interval"
		jct "$tmpfile" set info_interval "$prusa_connect_info_interval"
		jct "$tmpfile" set online_host "$prusa_connect_online_host"
		jct "$tmpfile" set snapshot_url "$prusa_connect_snapshot_url"
		jct "$tmpfile" set info_url "$prusa_connect_info_url"
		if ! mv "$tmpfile" "$config_file"; then
			rm -f "$tmpfile"
			redirect_to $SCRIPT_NAME "danger" "Failed to update config file."
		fi
		service restart prusa-connect >/dev/null
		redirect_to $SCRIPT_NAME "success" "Settings saved."
	else
		redirect_to $SCRIPT_NAME "danger" "Error: $error"
	fi
fi

defaults
%>
<%in _header.cgi %>

<div class="row g-4 mb-4">
<div class="col col-lg-7">
<form action="<%= $SCRIPT_NAME %>" method="post">
<% if [ "false" = "$prusa_connect_has_credentials" ]; then %>
<div class="card mb-3">
<div class="card-header d-flex justify-content-between align-items-center">
<span>Credentials</span>
<button type="button" class="btn btn-sm btn-outline-secondary" id="fingerprint-generate" data-cmd="<%= $cmd_uuid_raw %>">Generate fingerprint</button>
</div>
<div class="card-body">
<% field_text "prusa_connect_fingerprint" "Camera fingerprint" "Use a unique UUID for each camera." %>
<% field_text "prusa_connect_token" "Camera token" "Find it in <a href=\"https://connect.prusa3d.com/\" target=\"_blank\">Prusa Connect</a> → Printer → Add web camera." %>
</div>
</div>
<% fi %>

<% if [ "true" = "$prusa_connect_has_credentials" ]; then %>
<div class="card">
<div class="card-header">Scheduling</div>
<div class="card-body">
<% field_switch "prusa_connect_enabled" "Enable Prusa Connect" %>
<% field_number "prusa_connect_interval" "Snapshot upload interval (seconds)" "10,3600,10" "Allowed range: 10-3600 seconds." %>
<% field_number "prusa_connect_info_interval" "Metadata refresh (seconds)" "60,86400,60" "Allowed range: 60-86400 seconds." %>
<% field_text "prusa_connect_online_host" "Reachability host" "Optional host to ping before uploading." %>
<details class="mt-3">
<summary class="text-secondary">Advanced</summary>
<% field_text "prusa_connect_snapshot_url" "Snapshot API URL" %>
<% field_text "prusa_connect_info_url" "Info API URL" %>
</details>
</div>
</div>
<% fi %>
<% button_submit "Save settings" %>
</form>
</div>

<div class="col">
<% if [ "true" = "$prusa_connect_has_credentials" ]; then %>
<div class="card mb-3">
<div class="card-header d-flex justify-content-between">
<span>Service status</span>
<% button_refresh %>
</div>
<div class="card-body">
<p class="mb-2">Daemon: <a class="btn btn-link px-0" href="run.cgi?cmd=<%= $cmd_status %>">Check via CLI</a></p>
<ul class="list-unstyled small mb-3">
<li>Snapshots: <strong><%= $prusa_state_snapshot_status %></strong> <span class="text-secondary"><%= $snapshot_time %></span></li>
<li>Metadata: <strong><%= $prusa_state_info_status %></strong> <span class="text-secondary"><%= $info_time %></span></li>
</ul>
<div class="d-flex flex-wrap gap-2">
<a class="btn btn-outline-primary" href="run.cgi?cmd=<%= $cmd_test %>">Test upload now</a>
<a class="btn btn-outline-secondary" href="run.cgi?cmd=<%= $cmd_restart %>">Restart service</a>
<a class="btn btn-outline-dark" href="https://github.com/themactep/thingino-firmware/blob/stable/docs/thingino/services/prusa-connect.md" target="_blank">Documentation</a>
</div>
</div>
</div>
<% else %>
<div class="card">
<div class="card-header">Tips</div>
<div class="card-body">
<ul>
<li>Use the CLI helper via SSH: <code>prusa-connect status</code></li>
<li>Tokens and fingerprints live in <code>/etc/prusa-connect.json</code></li>
<li>Each camera needs a unique fingerprint in Prusa Connect.</li>
</ul>
</div>
</div>
<% fi %>
</div>
</div>

<script>
(() => {
	const btn = document.getElementById('fingerprint-generate');
	if (!btn) return;
	btn.addEventListener('click', () => {
		btn.disabled = true;
		const url = 'run.cgi?cmd=' + btn.dataset.cmd;
		fetch(url)
			.then(resp => resp.text())
			.then(text => {
				let raw = text;
				if (window.DOMParser) {
					try {
						const parser = new DOMParser();
						const doc = parser.parseFromString(text, 'text/html');
						raw = (doc && doc.body) ? doc.body.textContent : text;
					} catch (e) {
						raw = text;
					}
				}
				const uuid = raw.split(/\r?\n/)
					.map(line => line.trim())
					.find(line => /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.test(line));
				if (uuid) {
					const input = document.getElementById('prusa_connect_fingerprint');
					if (input) input.value = uuid;
				}
			})
			.catch(() => {})
			.finally(() => btn.disabled = false);
	});
})();
</script>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file print" %>
<% ex "cat $state_file" %>
</div>

<%in _footer.cgi %>
