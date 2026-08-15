#!/bin/sh
# BusyBox httpd CGI for JSON API
# Expects request body (application/json)

# Check authentication
. /var/www/x/auth.sh
require_auth

# Read the full request body before emitting headers so we can validate first
body=""
if [ -n "$CONTENT_LENGTH" ]; then
	body=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
else
	body=$(cat)
fi

# Pre-flight check for recording start: verify mount is available
if echo "$body" | grep -q '"mp4".*"start"'; then
	recorder_mount=$(jct /etc/prudynt.json get recorder.mount 2>/dev/null)
	if [ -n "$recorder_mount" ] && [ ! -d "$recorder_mount" ]; then
		echo "Content-Type: application/json"
		echo "Connection: close"
		echo
		printf '{"mp4":{"start":"Mountpoint %s does not exist"}}\n' "$recorder_mount"
		exit 0
	fi
	if [ -n "$recorder_mount" ] && ! mountpoint -q "$recorder_mount" 2>/dev/null; then
		echo "Content-Type: application/json"
		echo "Connection: close"
		echo
		printf '{"mp4":{"start":"Mountpoint %s is not available"}}\n' "$recorder_mount"
		exit 0
	fi
fi

echo "Content-Type: application/json"
echo "Connection: close"
echo

printf '%s' "$body" | prudyntctl json -
