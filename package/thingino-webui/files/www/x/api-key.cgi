#!/bin/sh

. /var/www/x/auth.sh

# Trusted-IP bypass is handled inside require_auth; API key auth is intentionally
# excluded here (would be circular), so verify_api_key is skipped via the fallback.
session_id=$(get_session_from_cookie)
if ! is_trusted_ip && { [ -z "$session_id" ] || ! validate_session "$session_id"; }; then
  printf "Status: 401 Unauthorized\r\n"
  printf "Content-Type: application/json\r\n"
  printf "Connection: close\r\n"
  printf "\r\n"
  printf '{"error":"Session authentication required"}\n'
  exit 0
fi

API_KEY_FILE="/etc/thingino-api.key"

send_json() {
  printf "Content-Type: application/json\r\n"
  printf "Cache-Control: no-store\r\n"
  printf "Connection: close\r\n"
  printf "\r\n"
  printf "%s\n" "$1"
}

case "$REQUEST_METHOD" in
  GET)
    # Show current API key (if exists)
    if [ -f "$API_KEY_FILE" ]; then
      key=$(cat "$API_KEY_FILE" 2>/dev/null | tr -d '\n\r ')
      send_json "{\"api_key\":\"$key\",\"exists\":true}"
    else
      send_json "{\"exists\":false}"
    fi
    ;;

  POST)
    # Generate new API key
    new_key=$(head -c 32 /dev/urandom | hexdump -e '32/1 "%02x" "\n"')
    echo "$new_key" > "$API_KEY_FILE"
    chmod 600 "$API_KEY_FILE"
    send_json "{\"api_key\":\"$new_key\",\"generated\":true}"
    ;;

  DELETE)
    # Delete API key
    rm -f "$API_KEY_FILE"
    send_json "{\"deleted\":true}"
    ;;

  *)
    printf "Status: 405 Method Not Allowed\r\n"
    printf "Content-Type: application/json\r\n"
    printf "Connection: close\r\n"
    printf "\r\n"
    printf '{"error":"Method not allowed"}\n'
    ;;
esac
