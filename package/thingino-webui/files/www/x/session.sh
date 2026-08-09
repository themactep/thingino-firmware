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
	cat >"$session_file" <<EOF
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
# Side effect: sources the session file into the current shell, so callers
# can use $username, $created, $last_access, $is_default_password directly.
validate_session() {
	local session_id="$1"
	local session_file="$SESSION_DIR/$session_id"
	local now

	# Check if session file exists
	[ -f "$session_file" ] || return 1

	# Read session data
	. "$session_file"

	# Refresh last_access at most once per minute. Rewriting the file with
	# sed -i on every request forked an extra process per hit for a
	# timestamp nobody reads with more precision than that.
	now=$(date +%s)
	if [ $((now - ${last_access:-0})) -ge 60 ]; then
		printf 'username=%s\ncreated=%s\nlast_access=%s\nis_default_password=%s\n' \
			"$username" "$created" "$now" "$is_default_password" >"$session_file"
	fi

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
# Parses with shell builtins only: this runs on every authenticated CGI
# request, and the old echo|tr|grep|cut|tr pipeline forked five processes
# per hit.
get_session_from_cookie() {
	local c val IFS=';'
	for c in $HTTP_COOKIE; do
		c="${c# }"
		case "$c" in
			"$COOKIE_NAME"=*)
				val="${c#*=}"
				printf '%s' "${val%% *}"
				return 0
				;;
		esac
	done
	return 1
}
