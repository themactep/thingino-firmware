#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

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

scan_networks() {
	# Check if wpa_cli is available
	if ! command -v wpa_cli >/dev/null 2>&1; then
		echo '{"error": "wpa_cli not available"}'
		return
	fi

	# Check if scan is already in progress
	SCAN_LOCK="/tmp/wpa_scan.lock"
	SCAN_WAIT=0
	SHOULD_SCAN=1

	# Wait up to 8 seconds for ongoing scan to complete
	while [ -f "$SCAN_LOCK" ] && [ $SCAN_WAIT -lt 8 ]; do
		# Check if lock is stale (older than 15 seconds)
		LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$SCAN_LOCK" 2>/dev/null || echo 0) ))
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
		wpa_cli -i wlan0 scan >/dev/null 2>&1
		sleep 2
	fi

	# Get scan results and format as JSON
	echo "{"
	echo "\"networks\": ["

	first=1
	wpa_cli -i wlan0 scan_results 2>/dev/null | tail -n +2 | while IFS=$'\t' read -r bssid freq signal flags ssid; do
		# Skip empty SSIDs and header
		[ -z "$ssid" ] || [ "$ssid" = "ssid" ] && continue

		# Determine security type
		security="Open"
		if echo "$flags" | grep -q "WPA2-PSK"; then
			security="WPA2"
		elif echo "$flags" | grep -q "WPA-PSK"; then
			security="WPA"
		elif echo "$flags" | grep -q "WEP"; then
			security="WEP"
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

	echo "]"
	echo "}"

	# Clean up lock if we created it
	[ $SHOULD_SCAN -eq 1 ] && rm -f "$SCAN_LOCK"
}

json_response "$(scan_networks)"

