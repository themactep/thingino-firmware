#!/bin/sh

# Save configuration to /etc/prudynt.json using jct
# Receives JSON payload and merges it into the config file

. /var/www/x/auth.sh
require_auth

CONFIG_FILE="/etc/prudynt.json"
TEMP_FILE="/tmp/prudynt-save-$$.json"

http_200() {
  printf 'Status: 200 OK\r\n'
}

send_headers() {
  http_200
  printf 'Content-Type: application/json\r\n\r\n'
}

error_response() {
  send_headers
  printf '{"error":"%s"}\n' "$1"
  rm -f "$TEMP_FILE"
  exit 1
}

# Read POST body from stdin
if [ -z "$CONTENT_LENGTH" ] || [ "$CONTENT_LENGTH" -eq 0 ]; then
  error_response "No payload provided"
fi

# Read the JSON payload
cat > "$TEMP_FILE"

# Check if file was created and has content
if [ ! -s "$TEMP_FILE" ]; then
  error_response "Empty payload received"
fi

# First, send to prudynt to update in-memory config
prudyntctl json - < "$TEMP_FILE" >/dev/null 2>&1

# Then merge the changes into the config file
if ! jct "$CONFIG_FILE" import "$TEMP_FILE" 2>&1; then
  error_response "Failed to merge configuration"
fi

# Clean up
rm -f "$TEMP_FILE"

# Return success
send_headers
printf '{"status":"ok","message":"Configuration saved to %s"}\n' "$CONFIG_FILE"
