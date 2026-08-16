#!/bin/sh

OS_RELEASE_FILE="/etc/os-release"

urldecode() {
	printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}

set_param() {
	key="$1"
	value="$2"

	case "$key" in
		action) PARAM_action="$value" ;;
		hostname) PARAM_hostname="$value" ;;
		rootpass) PARAM_rootpass="$value" ;;
		rootpass_hash) PARAM_rootpass_hash="$value" ;;
		rootpkey) PARAM_rootpkey="$value" ;;
		timezone) PARAM_timezone="$value" ;;
		wlan_pass) PARAM_wlan_pass="$value" ;;
		wlan_psk) PARAM_wlan_psk="$value" ;;
		wlan_ssid) PARAM_wlan_ssid="$value" ;;
		wlan_ap) PARAM_wlan_ap="$value" ;;
		*) ;;
	esac
}

parse_form_data() {
	while IFS='=' read -r key value; do
		[ -n "$key" ] || continue
		set_param "$(urldecode "$key")" "$(urldecode "$value")"
	done <<-FORM
		$(printf '%s' "$1" | tr '&' '\n')
	FORM
}

parse_query() {
	parse_form_data "$QUERY_STRING"
}

json_encode() {
	echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//'
}

json_response() {
	echo "Content-type: application/json; charset=UTF-8"
	echo "Cache-Control: no-store"
	echo "Pragma: no-cache"
	echo ""
	echo "$1"
}

get_info() {
	hostname=$(hostname)
	image_id=$(awk -F= '/IMAGE_ID/{print $2}' $OS_RELEASE_FILE)
	build_id=$(awk -F= '/BUILD_ID/{print $2}' $OS_RELEASE_FILE | tr -d '"')
	wlan_mac=$(ip link show wlan0 2>/dev/null | awk '/ether/ {print $2}')

	cat <<-EOF
		{
			"hostname": "$(json_encode "$hostname")",
			"image_id": "$(json_encode "$image_id")",
			"build_id": "$(json_encode "$build_id")",
			"wlan_mac": "$(json_encode "$wlan_mac")"
		}
	EOF
}

# The portal starts exactly one wpa_supplicant instance (S38), so the
# control socket directory tells us which netdev to talk to. The legacy
# hardcoded `wlan0` breaks on cameras whose AP interface is ap0/wlan1
# (hi3881, wq9001) and on ATBM6461 which has no ctrl socket at all.
wpa_iface() {
	# Explicit override first, then probe the ctrl socket directory
	iface="${WPA_IFACE:-}"
	[ -n "$iface" ] && { echo "$iface"; return; }

	# One socket = one supplicant instance = the right interface
	first_socket=$(ls /run/wpa_supplicant 2>/dev/null | head -n 1)
	if [ -n "$first_socket" ]; then
		echo "$first_socket"
		return
	fi

	echo "wlan0"
}

scan_networks() {
	# Check if wpa_cli is available
	if ! command -v wpa_cli >/dev/null 2>&1; then
		echo '{"error": "wpa_cli not available"}'
		return
	fi

	IFACE=$(wpa_iface)

	# Check if scan is already in progress
	SCAN_LOCK="/tmp/wpa_scan.lock"
	SCAN_WAIT=0
	SHOULD_SCAN=1

	# Wait up to 8 seconds for ongoing scan to complete
	while [ -f "$SCAN_LOCK" ] && [ $SCAN_WAIT -lt 8 ]; do
		# Check if lock is stale (older than 15 seconds)
		LOCK_AGE=$(($(date +%s) - $(stat -c %Y "$SCAN_LOCK" 2>/dev/null || echo 0)))
		if [ $LOCK_AGE -gt 15 ]; then
			rm -f "$SCAN_LOCK"
			break
		fi
		sleep 1
		SCAN_WAIT=$((SCAN_WAIT + 1))
	done

	# If still locked after waiting, use cached results
	if [ -f "$SCAN_LOCK" ]; then
		SHOULD_SCAN=0
	else
		# Create lock file and trigger new scan
		touch "$SCAN_LOCK"
		wpa_cli -i "$IFACE" scan >/dev/null 2>&1
		sleep 2
	fi

	# Get scan results and format as JSON
	echo "{\"networks\": ["

	first=1
	wpa_cli -i "$IFACE" scan_results 2>/dev/null | tail -n +2 | while IFS="$(printf '\t')" read -r bssid _ signal flags ssid; do
		# Skip empty SSIDs and header
		[ -z "$ssid" ] || [ "$ssid" = "ssid" ] && continue

		# Determine security type
		if echo "$flags" | grep -q "WPA2-PSK"; then
			security="WPA2"
		elif echo "$flags" | grep -q "WPA-PSK"; then
			security="WPA"
		elif echo "$flags" | grep -q "WEP"; then
			security="WEP"
		else
			security="Open"
		fi

		# Output JSON without trailing commas
		if [ $first -eq 0 ]; then
			echo ","
		else
			first=0
		fi
		cat <<-NETWORK
			{
				"ssid": "$(json_encode "$ssid")",
				"bssid": "$(json_encode "$bssid")",
				"signal": $signal,
				"security": "$(json_encode "$security")"
			}
		NETWORK
	done

	echo "]}"

	# Clean up lock if we created it
	[ $SHOULD_SCAN -eq 1 ] && rm -f "$SCAN_LOCK"
}

scan_start() {
	if ! command -v wpa_cli >/dev/null 2>&1; then
		echo '{"error": "wpa_cli not available", "scanning": false}'
		return
	fi

	IFACE=$(wpa_iface)

	# Ignore stale locks (older than 15 seconds)
	SCAN_LOCK="/tmp/wpa_scan.lock"
	LOCK_AGE=$(($(date +%s) - $(stat -c %Y "$SCAN_LOCK" 2>/dev/null || echo 0)))
	[ $LOCK_AGE -gt 15 ] && rm -f "$SCAN_LOCK"

	if [ -f "$SCAN_LOCK" ]; then
		# A scan is already running; poller will pick it up
		echo '{"scanning": true}'
		return
	fi

	touch "$SCAN_LOCK"
	wpa_cli -i "$IFACE" scan >/dev/null 2>&1
	# Reply immediately; scan_status() reports completion
	echo '{"scanning": true}'
}

scan_status() {
	if ! command -v wpa_cli >/dev/null 2>&1; then
		echo '{"error": "wpa_cli not available", "scanning": false}'
		return
	fi

	IFACE=$(wpa_iface)

	# Poll wpa_supplicant for scan progress: FAIL-BUSY while the radio
	# sweeps, OK once results are ready to read.
	if wpa_cli -i "$IFACE" scan 2>/dev/null | grep -q FAIL; then
		echo '{"scanning": true}'
		return
	fi

	# Scan finished; release the lock and hand over the results
	rm -f "/tmp/wpa_scan.lock"

	# Refresh the prescan cache so page reloads after a manual scan
	# show the freshest list without another radio sweep. Only write
	# when the live results actually have entries: AP-mode supplicants
	# return a header-only list when the driver cannot survey while
	# hosting, and that must not poison the S38 cache.
	FRESH="$(wpa_cli -i "$IFACE" scan_results 2>/dev/null)"
	if [ "$(count_networks "$FRESH")" -gt 0 ]; then
		echo "$FRESH" >/tmp/wifi_prescan
	fi

	scan_networks_cached
}

# Count real BSS entries in raw wpa_cli output: strip the banner and
# the column header, then count what is left. Header-only output from
# an AP-mode supplicant counts as zero.
count_networks() {
	echo "$1" | grep -v '^Selected interface' | tail -n +2 | grep -c .
}

# Read-only results reader without triggering a new scan
scan_networks_cached() {
	IFACE=$(wpa_iface)

	# Live results when a reachable supplicant has BSS entries. The
	# portal supplicant is always reachable in portal mode, but its BSS
	# list stays empty unless a manual scan just ran: scan_results then
	# succeeds with header-only output. That must not shadow the
	# prescan cache written by S38 before the AP went up.
	RESULTS="$(wpa_cli -i "$IFACE" scan_results 2>/dev/null)"
	if [ "$(count_networks "$RESULTS")" -eq 0 ] && [ -f /tmp/wifi_prescan ]; then
		RESULTS="$(cat /tmp/wifi_prescan)"
	fi

	format_networks "$RESULTS"
}

# Format raw `wpa_cli scan_results` output (tab-separated) as JSON
format_networks() {
	echo "{\"networks\": ["

	first=1
	# Strip the "Selected interface" banner wpa_cli prints when run
	# without -i, then drop the column header line before parsing
	echo "$1" | grep -v '^Selected interface' | tail -n +2 | while IFS="$(printf '\t')" read -r bssid _ signal flags ssid; do
		# Skip empty SSIDs and header
		[ -z "$ssid" ] || [ "$ssid" = "ssid" ] && continue

		# Determine security type
		if echo "$flags" | grep -q "WPA2-PSK"; then
			security="WPA2"
		elif echo "$flags" | grep -q "WPA-PSK"; then
			security="WPA"
		elif echo "$flags" | grep -q "WEP"; then
			security="WEP"
		else
			security="Open"
		fi

		# Output JSON without trailing commas
		if [ $first -eq 0 ]; then
			echo ","
		else
			first=0
		fi
		cat <<-NETWORK
			{
				"ssid": "$(json_encode "$ssid")",
				"bssid": "$(json_encode "$bssid")",
				"signal": $signal,
				"security": "$(json_encode "$security")"
			}
		NETWORK
	done

	echo "]}"
}

parse_post() {
	if [ "$REQUEST_METHOD" = "POST" ]; then
		case "$CONTENT_LENGTH" in
			'' | *[!0-9]*) POST_DATA='' ;;
			0) POST_DATA='' ;;
			*) POST_DATA=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null) ;;
		esac

		parse_form_data "$POST_DATA"
	fi
}

save_config() {
	hostname="$PARAM_hostname"
	rootpass="$PARAM_rootpass"
	rootpass_hash="$PARAM_rootpass_hash"
	rootpkey="$PARAM_rootpkey"
	timezone="$PARAM_timezone"
	wlan_pass="$PARAM_wlan_pass"
	wlan_psk="$PARAM_wlan_psk"
	wlan_ssid="$PARAM_wlan_ssid"
	wlan_ap="$PARAM_wlan_ap"

	# Trim trailing whitespaces from submitted values
	hostname=$(echo "$hostname" | sed 's/[[:space:]]*$//')
	rootpass=$(echo "$rootpass" | sed 's/[[:space:]]*$//')
	rootpkey=$(echo "$rootpkey" | sed 's/[[:space:]]*$//')
	timezone=$(echo "$timezone" | sed 's/[[:space:]]*$//')
	wlan_pass=$(echo "$wlan_pass" | sed 's/[[:space:]]*$//')
	wlan_ssid=$(echo "$wlan_ssid" | sed 's/[[:space:]]*$//')

	# FIXME: Sanitize ssid and password

	# A client that can hash locally sends these instead, so neither secret
	# crosses the portal in the clear. The portal AP is open, so anything sent
	# as plaintext is readable by anyone in range.
	if [ -n "$wlan_psk" ] && ! echo "$wlan_psk" | grep -qE '^[0-9a-fA-F]{64}$'; then
		cat <<-EOF
			{
				"success": false,
				"error": "wlan_psk must be 64 hex characters"
			}
		EOF
		return
	fi

	# shellcheck disable=SC2016 # regex, not a shell expansion
	if [ -n "$rootpass_hash" ] && ! echo "$rootpass_hash" | grep -q '^\$6\$'; then
		cat <<-EOF
			{
				"success": false,
				"error": "rootpass_hash must be a SHA-512 crypt string"
			}
		EOF
		return
	fi

	# Validate hostname
	bad_chars=$(echo "$hostname" | sed 's/[0-9A-Z\.-]//ig')
	if [ -n "$bad_chars" ]; then
		cat <<-EOF
			{
				"success": false,
				"error": "Hostname cannot contain $bad_chars"
			}
		EOF
		return
	fi

	# Update hostname
	hostname "$hostname"
	echo "$hostname" >/etc/hostname

	# Update wlan settings. `wlan configure` already accepts a 64-hex PSK in
	# place of a passphrase, so a pre-derived one just passes straight through.
	wlan_secret="$wlan_pass"
	[ -n "$wlan_psk" ] && wlan_secret="$wlan_psk"

	if [ "true" = "$wlan_ap" ]; then
		wlan configure "$wlan_ssid" "$wlan_secret" ap
	else
		wlan configure "$wlan_ssid" "$wlan_secret"
	fi

	# Update timezone
	if [ -n "$timezone" ]; then
		timectl set-timezone --source user "$timezone"
	fi

	# Update root password. -e takes an already-encrypted field, so a client
	# that hashed it locally never sends the plaintext.
	if [ -n "$rootpass_hash" ]; then
		printf '%s:%s\n' "root" "$rootpass_hash" | chpasswd -e
	else
		printf '%s:%s\n' "root" "$rootpass" | chpasswd -c sha512
	fi

	# Update SSH key if provided
	if [ -n "$rootpkey" ]; then
		echo "$rootpkey" | tr -d '\r' | sed 's/^ //g' >/root/.ssh/authorized_keys
	fi

	# Update interface for onvif
	jct /etc/onvif.json set ifs wlan0

	# Success response
	cat <<-EOF
		{
			"success": true
		}
	EOF

	# Reboot in background
	reboot -d 2 &
}

parse_query

case "$PARAM_action" in
	get_info)
		json_response "$(get_info)"
		;;
	scan_networks)
		json_response "$(scan_networks)"
		;;
	scan_cached)
		json_response "$(scan_networks_cached)"
		;;
	scan_start)
		json_response "$(scan_start)"
		;;
	scan_status)
		json_response "$(scan_status)"
		;;
	save)
		parse_post
		json_response "$(save_config)"
		;;
	*)
		json_response '{"error": "Invalid action"}'
		;;
esac
