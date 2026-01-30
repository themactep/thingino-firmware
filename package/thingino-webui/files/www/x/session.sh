#!/bin/sh

# Session management library for thingino webui
# Provides session creation, validation, and cleanup

SESSION_DIR="/tmp/sessions"
COOKIE_NAME="thingino_session"

# Ensure session directory exists
ensure_session_dir() {
  mkdir -p "$SESSION_DIR"
  chmod 700 "$SESSION_DIR"
}

# Generate a random session ID
generate_session_id() {
  # Use urandom for cryptographically secure random ID
  head -c 16 /dev/urandom | hexdump -e '16/1 "%02x" "\n"'
}

# Create a new session
# Usage: create_session <username> <is_default_password>
create_session() {
  local username="$1"
  local is_default="${2:-false}"

  ensure_session_dir

  local session_id=$(generate_session_id)
  local session_file="$SESSION_DIR/$session_id"
  local timestamp=$(date +%s)

  # Write session data
  cat > "$session_file" <<EOF
username=$username
created=$timestamp
last_access=$timestamp
is_default_password=$is_default
EOF

  chmod 600 "$session_file"
  echo "$session_id"
}

# Validate and update session
# Usage: validate_session <session_id>
# Returns: 0 if valid, 1 if invalid
validate_session() {
  local session_id="$1"
  local session_file="$SESSION_DIR/$session_id"

  # Check if session file exists
  [ -f "$session_file" ] || return 1

  # Read session data
  . "$session_file"

  # Update last access time
  sed -i "s/^last_access=.*/last_access=$(date +%s)/" "$session_file"

  return 0
}

# Get session data
# Usage: get_session_data <session_id> <key>
get_session_data() {
  local session_id="$1"
  local key="$2"
  local session_file="$SESSION_DIR/$session_id"

  [ -f "$session_file" ] || return 1

  . "$session_file"
  eval echo "\$$key"
}

# Delete a session
# Usage: delete_session <session_id>
delete_session() {
  local session_id="$1"
  rm -f "$SESSION_DIR/$session_id"
}

# Clean up expired sessions
# Usage: cleanup_sessions
cleanup_sessions() {
  ensure_session_dir
}

# Extract session ID from Cookie header
# Usage: get_session_from_cookie
get_session_from_cookie() {
  echo "$HTTP_COOKIE" | tr ';' '\n' | grep "^${COOKIE_NAME}=" | cut -d= -f2 | tr -d ' '
}
