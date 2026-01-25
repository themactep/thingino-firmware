#!/bin/sh

. /usr/share/common

DOMAIN="zerotier"
CONFIG_FILE="/etc/zerotier.json"
TMP_FILE=""

ZT_CLI_BIN=/usr/sbin/zerotier-cli
ZT_ONE_BIN=/usr/sbin/zerotier-one

cleanup() {
  [ -n "$TMP_FILE" ] && rm -f "$TMP_FILE"
}
trap cleanup EXIT

json_escape() {
  # Remove any newlines and escape properly for JSON
  printf '%s' "$1" | tr -d '\n\r' | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g'
}

send_json() {
  status="${2:-200 OK}"
  printf 'Status: %s\n' "$status"
  cat <<EOF
Content-Type: application/json
Cache-Control: no-store
Pragma: no-cache

$1
EOF
  exit 0
}

json_error() {
  code="${1:-400}"
  message="$2"
  send_json "{\"error\":{\"code\":$code,\"message\":\"$(json_escape "$message")\"}}" "${3:-400 Bad Request}"
}

get_value() {
  jct "$CONFIG_FILE" get "$DOMAIN.$1" 2>/dev/null
}

set_value() {
  [ -f "$TMP_FILE" ] || echo '{}' > "$TMP_FILE"
  jct "$TMP_FILE" set "$DOMAIN.$1" "$2" >/dev/null 2>&1
}

# Check if ZeroTier is installed
check_zerotier_support() {
  [ -f "$ZT_CLI_BIN" ] && [ -f "$ZT_ONE_BIN" ]
}

# GET - Return current configuration and status
if [ "$REQUEST_METHOD" = "GET" ]; then
  # Check support
  if ! check_zerotier_support; then
    send_json '{"config":{},"status":{"supported":false}}'
  fi

  # Read config
  enabled=$(get_value enabled)
  nwid=$(get_value nwid)
  saved_network_name=$(get_value network_name)

  # Default values
  [ -z "$enabled" ] && enabled="false"
  [ -z "$nwid" ] && nwid=""
  [ -z "$saved_network_name" ] && saved_network_name=""

  # Get status
  running="false"
  online="false"
  name=""
  network_status=""
  ip=""
  network_name=""
  network_type=""
  network_mac=""

  if pidof zerotier-one >/dev/null 2>&1; then
    running="true"

    # Get ZeroTier info
    zt_info=$($ZT_CLI_BIN info 2>/dev/null)
    if [ -n "$zt_info" ]; then
      status_field=$(echo "$zt_info" | cut -f 5 -d ' ')
      if [ "$status_field" = "ONLINE" ]; then
        online="true"
        name=$(echo "$zt_info" | cut -f 3 -d ' ')
      fi
    fi

    # Get network status if we have a network ID
    if [ -n "$nwid" ] && [ "$online" = "true" ]; then
      # Check what's actually joined by parsing listnetworks
      actual_joined_nwid=$($ZT_CLI_BIN listnetworks 2>/dev/null | grep "^200 listnetworks" | grep -v "<nwid>" | awk '{print $3}')

      # If the configured nwid is not the one actually joined, clear status
      if [ -n "$actual_joined_nwid" ] && [ "$actual_joined_nwid" != "$nwid" ]; then
        # Joined to a different network than configured - inconsistent state
        network_status="INCONSISTENT"
        network_name=""
        network_type=""
        network_mac=""
        ip=""
      else
        # Query status for the configured network
        network_status=$($ZT_CLI_BIN get "$nwid" status 2>/dev/null)
        if [ "$network_status" = "OK" ] || [ "$network_status" = "REQUESTING_CONFIGURATION" ] || [ "$network_status" = "ACCESS_DENIED" ]; then
          ip=$($ZT_CLI_BIN get "$nwid" ip 2>/dev/null)
          network_name=$($ZT_CLI_BIN get "$nwid" name 2>/dev/null)
          network_type=$($ZT_CLI_BIN get "$nwid" type 2>/dev/null)
          network_mac=$($ZT_CLI_BIN get "$nwid" mac 2>/dev/null)

          # Update saved network name if it changed and is valid (not an error message)
          if [ -n "$network_name" ] && [ "$network_name" != "$saved_network_name" ] && ! echo "$network_name" | grep -q "Error\|error\|failed"; then
            jct "$CONFIG_FILE" set "$DOMAIN.network_name" "$network_name" >/dev/null 2>&1
            saved_network_name="$network_name"
          fi
        fi
      fi
    fi

    # Use saved network name if live one is not available
    if [ -z "$network_name" ] && [ -n "$saved_network_name" ]; then
      network_name="$saved_network_name"
    fi
  fi

  # Build and send JSON response
  cat <<EOF
Content-Type: application/json
Cache-Control: no-store
Pragma: no-cache

{
  "config": {
    "enabled": $enabled,
    "nwid": "$(json_escape "$nwid")",
    "network_name": "$(json_escape "$saved_network_name")"
  },
  "status": {
    "supported": true,
    "running": $running,
    "online": $online,
    "name": "$(json_escape "$name")",
    "networkStatus": "$(json_escape "$network_status")",
    "ip": "$(json_escape "$ip")",
    "networkName": "$(json_escape "$network_name")",
    "networkType": "$(json_escape "$network_type")",
    "networkMac": "$(json_escape "$network_mac")"
  }
}
EOF
  exit 0
fi

# POST - Handle configuration updates and actions
if [ "$REQUEST_METHOD" = "POST" ]; then
  # Check support
  if ! check_zerotier_support; then
    json_error 501 "ZeroTier is not installed on this system" "501 Not Implemented"
  fi

  # Read POST data
  if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ]; then
    post_data=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
  else
    json_error 400 "No POST data received"
  fi

  # Save to temp file for parsing
  TMP_FILE=$(mktemp)
  echo "$post_data" > "$TMP_FILE"

  # Check for action field
  action=$(jct "$TMP_FILE" get action 2>/dev/null)

  if [ -n "$action" ]; then
    # Handle service control actions
    case "$action" in
      start)
        service force zerotier >&2
        send_json '{"success":true,"message":"Service started"}'
        ;;
      stop)
        service stop zerotier >&2
        send_json '{"success":true,"message":"Service stopped"}'
        ;;
      leave)
        nwid=$(get_value nwid)
        if [ -n "$nwid" ]; then
          $ZT_CLI_BIN leave "$nwid" >&2 2>/dev/null
        fi

        # Clear all zerotier config by writing empty object
        echo '{}' > "$CONFIG_FILE"

        service stop zerotier >&2
        send_json '{"success":true,"message":"Network removed"}'
        ;;
      *)
        json_error 400 "Unknown action: $action"
        ;;
    esac
  else
    # Handle configuration update
    enabled=$(jct "$TMP_FILE" get enabled 2>/dev/null)
    nwid=$(jct "$TMP_FILE" get nwid 2>/dev/null)

    # Validate
    if [ "$enabled" = "true" ]; then
      if [ -z "$nwid" ]; then
        json_error 400 "Network ID cannot be empty when enabled"
      fi

      # Check network ID length
      nwid_len=${#nwid}
      if [ "$nwid_len" -ne 16 ]; then
        json_error 400 "Network ID must be exactly 16 characters"
      fi
    fi

    # Save configuration
    [ ! -f "$CONFIG_FILE" ] && echo '{}' > "$CONFIG_FILE"

    set_value enabled "$enabled"
    set_value nwid "$nwid"

    jct "$CONFIG_FILE" import "$TMP_FILE" >/dev/null 2>&1
    sync

    # Update caminfo
    update_caminfo >/dev/null 2>&1

    send_json '{"success":true,"message":"Configuration saved"}'
  fi
fi

# Method not allowed
send_json '{"error":{"code":405,"message":"Method not allowed"}}' "405 Method Not Allowed"
