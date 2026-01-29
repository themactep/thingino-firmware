#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

. /usr/share/common

config_file="/etc/send2.json"
prudynt_config="/etc/prudynt.json"

send_json_response() {
  printf 'Content-Type: application/json\r\n\r\n'
  printf '%s' "$1"
}

send_error() {
  send_json_response "{\"error\":{\"message\":\"$1\"}}"
}

# GET - Load configuration
if [ "$REQUEST_METHOD" = "GET" ]; then
  # Read motion config from prudynt
  if [ -f "$prudynt_config" ]; then
    motion_data=$(jct "$prudynt_config" get motion 2>/dev/null || echo '{}')
  else
    motion_data='{}'
  fi

  # Helper to safely get config values
  get_domain_config() {
    if [ -f "$config_file" ]; then
      jct "$config_file" get "$1" 2>/dev/null || echo '{}'
    else
      echo '{}'
    fi
  }

  # Combine into response
  printf 'Content-Type: application/json\r\n\r\n'
  cat <<EOF
{
  "motion": $motion_data,
  "email": $(get_domain_config email),
  "ftp": $(get_domain_config ftp),
  "telegram": $(get_domain_config telegram),
  "mqtt": $(get_domain_config mqtt),
  "webhook": $(get_domain_config webhook),
  "storage": $(get_domain_config storage),
  "ntfy": $(get_domain_config ntfy),
  "gphotos": $(get_domain_config gphotos)
}
EOF
  exit 0
fi

# POST - Save configuration
if [ "$REQUEST_METHOD" = "POST" ]; then
  # Read POST body (read entire content based on CONTENT_LENGTH)
  if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ]; then
    post_data=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
  else
    post_data=""
  fi

  if [ -z "$post_data" ]; then
    send_error "No POST data received"
    exit 1
  fi

  # Save to temp file for processing
  temp_json=$(mktemp)
  echo "$post_data" > "$temp_json"

  # Detect which domain is being updated by checking keys
  if jct "$temp_json" get motion >/dev/null 2>&1; then
    # Motion config - import into prudynt.json
    jct "$prudynt_config" import "$temp_json"
    sync

    # Update running prudynt instance if it's running
    if pidof prudynt >/dev/null 2>&1; then
      prudyntctl json - < "$temp_json" >/dev/null 2>&1
    fi

  elif jct "$temp_json" get email >/dev/null 2>&1; then
    jct "$config_file" import "$temp_json"

  elif jct "$temp_json" get ftp >/dev/null 2>&1; then
    jct "$config_file" import "$temp_json"

  elif jct "$temp_json" get telegram >/dev/null 2>&1; then
    jct "$config_file" import "$temp_json"

  elif jct "$temp_json" get mqtt >/dev/null 2>&1; then
    jct "$config_file" import "$temp_json"

  elif jct "$temp_json" get webhook >/dev/null 2>&1; then
    jct "$config_file" import "$temp_json"

  elif jct "$temp_json" get storage >/dev/null 2>&1; then
    # Expand variables in storage config
    hostname=$(hostname)
    storage_json=$(jct "$temp_json" get storage)

    # Replace %hostname with actual hostname
    storage_json=$(echo "$storage_json" | sed "s/%hostname/$hostname/g")

    # Write expanded config back to temp file
    echo "{\"storage\":$storage_json}" > "$temp_json"
    jct "$config_file" import "$temp_json"

  elif jct "$temp_json" get ntfy >/dev/null 2>&1; then
    jct "$config_file" import "$temp_json"

  elif jct "$temp_json" get gphotos >/dev/null 2>&1; then
    jct "$config_file" import "$temp_json"

  else
    rm -f "$temp_json"
    send_error "Unknown configuration domain"
    exit 1
  fi

  rm -f "$temp_json"
  send_json_response '{"result":"success","message":"Settings saved"}'
  exit 0
fi

send_error "Invalid request method"
exit 1
