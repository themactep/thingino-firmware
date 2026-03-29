#!/bin/sh

# Slow heartbeat status - serves daemon-maintained cache for expensive device state.

. /var/www/x/auth.sh
require_auth

CACHE_FILE="/tmp/heartbeat_slow_cache.json"

read_cache_line() {
  local line

  if IFS= read -r line < "$1" || [ -n "$line" ]; then
    printf '%s\n' "$line"
  else
    printf '{}\n'
  fi
}

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-cache\r\n'
printf 'Connection: close\r\n\r\n'

if [ -r "$CACHE_FILE" ]; then
  read_cache_line "$CACHE_FILE"
else
  printf '{}\n'
fi