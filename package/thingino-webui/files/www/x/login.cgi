#!/bin/sh

. /var/www/x/session.sh

send_json() {
  status="${2:-200 OK}"
  printf "Status: %s\r\n" "$status"
  printf "Content-Type: application/json\r\n"
  printf "Cache-Control: no-store\r\n"
  printf "Pragma: no-cache\r\n"
  printf "\r\n"
  printf "%s\n" "$1"
  exit 0
}

json_error() {
  code="${1:-400}"
  message="$2"
  send_json "{\"error\":{\"code\":$code,\"message\":\"$message\"}}" "${3:-400 Bad Request}"
}

# Read POST data
read_post_data() {
  if [ -n "$CONTENT_LENGTH" ]; then
    dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null
  else
    cat
  fi
}

# Verify password
# Returns 0 if valid, 1 if invalid
verify_password() {
  local username="$1"
  local password="$2"

  # Get shadow entry for user
  local shadow_entry=$(grep "^${username}:" /etc/shadow 2>/dev/null)
  [ -z "$shadow_entry" ] && return 1

  # Extract the stored hash
  local stored_hash=$(echo "$shadow_entry" | cut -d: -f2)

  # Empty or locked password
  case "$stored_hash" in
    ""|"!"|"*") return 1 ;;
  esac

  # Extract salt from stored hash (format: $id$salt$hash)
  local salt=$(echo "$stored_hash" | cut -d'$' -f3)

  # Generate hash with mkpasswd
  # Note: mkpasswd defaults to sha512, or use -m sha512 (no dash)
  local test_hash=$(mkpasswd "$password" -S "$salt" 2>/dev/null)

  # Compare hashes
  [ "$test_hash" = "$stored_hash" ] && return 0
  return 1
}

case "$REQUEST_METHOD" in
  POST)
    # Read JSON POST data
    post_data=$(read_post_data)

    # Extract username and password from JSON
    # Simple parsing - in production, use jq or proper JSON parser
    username=$(echo "$post_data" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
    password=$(echo "$post_data" | grep -o '"password":"[^"]*"' | cut -d'"' -f4)

    # Validate inputs
    [ -z "$username" ] && json_error 400 "Username required"
    [ -z "$password" ] && json_error 400 "Password required"

    # Verify credentials
    if verify_password "$username" "$password"; then
      # Check if using default password
      is_default="false"
      if [ "$username" = "root" ] && [ "$password" = "root" ]; then
        is_default="true"
      fi

      # Create session
      session_id=$(create_session "$username" "$is_default")

      # Set cookie and return success
      printf "Status: 200 OK\r\n"
      printf "Content-Type: application/json\r\n"
      printf "Set-Cookie: %s=%s; Path=/; HttpOnly; SameSite=Strict\r\n" \
        "$COOKIE_NAME" "$session_id"
      printf "Cache-Control: no-store\r\n"
      printf "\r\n"
      printf '{"success":true,"is_default_password":%s}\n' "$is_default"
      exit 0
    else
      json_error 401 "Invalid credentials" "401 Unauthorized"
    fi
    ;;

  *)
    json_error 405 "Method not allowed" "405 Method Not Allowed"
    ;;
esac
