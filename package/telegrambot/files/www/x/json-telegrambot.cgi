#!/bin/sh
# Targeted shellcheck baseline: intentional busybox-ash idioms,
# template artifacts, and runtime-only sources in this file.
# New findings of other codes still fail. Policy: docs/pre-commit-hooks.md
# shellcheck disable=SC1091

# Check authentication
. /var/www/x/auth.sh
require_auth

config_file=/etc/telegrambot.json
if [ "$REQUEST_METHOD" = "POST" ]; then
	cl=${CONTENT_LENGTH:-0}
	json=$(head -c "$cl")
	printf '%s' "$json" >$config_file
fi

echo "Content-Type: application/json"
echo "Connection: close"
echo
cat $config_file
