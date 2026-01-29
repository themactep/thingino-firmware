#!/bin/sh

# Session authentication middleware
# Include this at the top of protected CGI scripts

. /var/www/x/session.sh

API_KEY_FILE="/etc/thingino-api.key"

# Verify API key from header (X-API-Key: your-key-here)
# Returns 0 if valid, 1 if invalid
verify_api_key() {
  local provided_key="$HTTP_X_API_KEY"
  
  [ -z "$provided_key" ] && return 1
  
  # Check if API key file exists
  [ ! -f "$API_KEY_FILE" ] && return 1
  
  # Read stored API key
  local stored_key=$(cat "$API_KEY_FILE" 2>/dev/null | tr -d '\n\r ')
  
  [ -z "$stored_key" ] && return 1
  
  # Compare keys
  [ "$provided_key" = "$stored_key" ] && return 0
  return 1
}

# Check if user is authenticated (session OR API key)
# If not, send 401 or redirect to login page
require_auth() {
  # First try session-based auth
  local session_id=$(get_session_from_cookie)
  
  if [ -n "$session_id" ] && validate_session "$session_id"; then
    # Session is valid - export session data for use in script
    export SESSION_ID="$session_id"
    export SESSION_USER=$(get_session_data "$session_id" "username")
    export SESSION_IS_DEFAULT_PASSWORD=$(get_session_data "$session_id" "is_default_password")
    return 0
  fi
  
  # No valid session - try API key
  if verify_api_key; then
    # API key is valid
    export SESSION_USER="api"
    export SESSION_IS_DEFAULT_PASSWORD="false"
    return 0
  fi
  
  # No valid authentication - check if this is a browser request
  if echo "$HTTP_ACCEPT" | grep -q "text/html"; then
    # Browser request - redirect to login page
    printf "Status: 302 Found\r\n"
    printf "Location: /login.html\r\n"
    printf "Cache-Control: no-store\r\n"
    printf "\r\n"
  else
    # Non-browser (API/automation) - send 401
    printf "Status: 401 Unauthorized\r\n"
    printf "Content-Type: application/json\r\n"
    printf "\r\n"
    printf '{"error":"Authentication required. Use session cookie or X-API-Key header"}\n'
  fi
  exit 0
}

# For HTML pages, use this to check auth and redirect if needed
require_auth_html() {
  local session_id=$(get_session_from_cookie)
  
  if [ -z "$session_id" ] || ! validate_session "$session_id"; then
    # Not authenticated - send HTML redirect
    cat <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="refresh" content="0;url=/login.html">
  <title>Redirecting...</title>
</head>
<body>
  <p>Redirecting to login...</p>
</body>
</html>
EOF
    exit 0
  fi
  
  # Session is valid
  export SESSION_ID="$session_id"
  export SESSION_USER=$(get_session_data "$session_id" "username")
  export SESSION_IS_DEFAULT_PASSWORD=$(get_session_data "$session_id" "is_default_password")
}
