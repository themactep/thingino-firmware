#!/bin/sh
# Targeted shellcheck baseline: intentional busybox-ash idioms,
# template artifacts, and runtime-only sources in this file.
# New findings of other codes still fail. Policy: docs/pre-commit-hooks.md
# shellcheck disable=SC1091

# Slow heartbeat proxied from Thingino agent

. /var/www/x/auth.sh
require_auth

. /usr/libexec/thingino-webui/heartbeat-lib.sh

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-cache\r\n'
printf 'Connection: close\r\n\r\n'

thingino_heartbeat_payload
