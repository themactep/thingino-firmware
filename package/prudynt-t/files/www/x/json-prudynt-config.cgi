#!/bin/sh
# Targeted shellcheck baseline: intentional busybox-ash idioms,
# template artifacts, and runtime-only sources in this file.
# New findings of other codes still fail. Policy: docs/pre-commit-hooks.md
# shellcheck disable=SC1091,SC2059
# Export full prudynt configuration from memory

# Check authentication
. /var/www/x/auth.sh
require_auth

printf "Content-Type: application/json\r\n"
printf "Content-Disposition: attachment; filename=\"prudynt-config-$(date +%Y%m%d-%H%M%S).json\"\r\n"
printf "Connection: close\r\n"
printf "\r\n"

# Use dump_config action to get full config from memory
echo '{"action":{"dump_config":null}}' | prudyntctl json -
