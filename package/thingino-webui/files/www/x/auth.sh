#!/bin/sh

# Session authentication middleware
# Include this at the top of protected CGI scripts

. /var/www/x/session.sh

API_KEY_FILE="/etc/thingino-api.key"
THINGINO_CONFIG="/etc/thingino.json"

# Normalise a client IP address using shell builtins only: strip IPv6
# brackets and the IPv4-mapped prefix ([::ffff:1.2.3.4] -> 1.2.3.4).
# The old tr|sed pipeline forked three processes per request for this.
normalize_client_ip() {
	local ip="$1"
	ip="${ip#\[}"
	ip="${ip%\]}"
	case "$ip" in
		::[Ff][Ff][Ff][Ff]:*) ip="${ip#::*:}" ;;
	esac
	printf '%s' "$ip"
}

# Check if the client IP is in the trusted IP bypass list (webui.auth_bypass_ips).
# Supports exact IPs, prefix notation (e.g. 192.168.1.), and CIDR ranges (e.g. 192.168.1.0/24).
# Returns 0 if the client should bypass auth, 1 otherwise.
is_trusted_ip() {
	local client_ip="${REMOTE_ADDR:-}"
	[ -z "$client_ip" ] && return 1

	# Read the bypass list first: it is empty on most cameras, and then this
	# check costs a single jct lookup and no other processes at all.
	local bypass_list
	bypass_list=$(jct "$THINGINO_CONFIG" get webui.auth_bypass_ips 2>/dev/null)
	bypass_list="${bypass_list#\"}"
	bypass_list="${bypass_list%\"}"
	[ -z "$bypass_list" ] || [ "$bypass_list" = "null" ] && return 1

	client_ip=$(normalize_client_ip "$client_ip")
	[ -z "$client_ip" ] && return 1

	# Split on commas/whitespace via IFS - no tr forks per entry
	local entry IFS=', 	'
	for entry in $bypass_list; do
		[ -z "$entry" ] && continue

		case "$entry" in
			*/*)
				# CIDR notation: awk runs only when a CIDR entry is configured
				if printf '%s %s\n' "$client_ip" "$entry" | awk '
          function ip2int(ip,    a) {
            split(ip, a, ".")
            return (a[1]+0)*16777216 + (a[2]+0)*65536 + (a[3]+0)*256 + (a[4]+0)
          }
          function prefix2base(p,    n, i) {
            n = 1
            for (i = 0; i < 32 - p; i++) n = n * 2
            return n
          }
          {
            split($2, cidr, "/")
            base = prefix2base(int(cidr[2]))
            exit (int(ip2int($1) / base) == int(ip2int(cidr[1]) / base)) ? 0 : 1
          }'; then
					return 0
				fi
				;;
			*.)
				# Prefix entry ending with a dot, e.g. "192.168.1."
				# (the old code built "192.168.1..*" here, which never matched)
				case "$client_ip" in
					"$entry"*) return 0 ;;
				esac
				;;
			*)
				# Exact match, or dot-bounded prefix match ("192.168.1" must not
				# match 192.168.10.5)
				case "$client_ip" in
					"$entry" | "$entry".*) return 0 ;;
				esac
				;;
		esac
	done

	return 1
}

# Verify API key from header (X-API-Key: your-key-here) or ?token= query param
# Returns 0 if valid, 1 if invalid
verify_api_key() {
	local provided_key="$HTTP_X_API_KEY"

	# Fall back to ?token= query parameter (used by ONVIF snapshot URLs)
	if [ -z "$provided_key" ]; then
		case "$QUERY_STRING" in
			token=*) provided_key="${QUERY_STRING#token=}" ;;
			*token=*) provided_key="${QUERY_STRING##*token=}" ;;
		esac
		provided_key="${provided_key%%&*}"
	fi

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
	# Trusted IP bypass - skip auth entirely for allowlisted addresses
	if is_trusted_ip; then
		export SESSION_USER="local"
		export SESSION_IS_DEFAULT_PASSWORD="false"
		return 0
	fi

	# First try session-based auth
	local session_id=$(get_session_from_cookie)

	if [ -n "$session_id" ] && validate_session "$session_id"; then
		# Session is valid. validate_session sourced the session file into this
		# shell - use its variables directly instead of forking two
		# get_session_data subshells per request.
		export SESSION_ID="$session_id"
		export SESSION_USER="$username"
		export SESSION_IS_DEFAULT_PASSWORD="$is_default_password"
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
	case "$HTTP_ACCEPT" in
		*text/html*)
			# Browser request - redirect to login page
			printf "Status: 302 Found\r\n"
			printf "Location: /login.html\r\n"
			printf "Cache-Control: no-store\r\n"
			printf "\r\n"
			;;
		*)
			# Non-browser (API/automation) - send 401
			printf "Status: 401 Unauthorized\r\n"
			printf "Content-Type: application/json\r\n"
			printf "\r\n"
			printf '{"error":"Authentication required. Use session cookie or X-API-Key header"}\n'
			;;
	esac
	exit 0
}

# For HTML pages, use this to check auth and redirect if needed
require_auth_html() {
	# Trusted IP bypass - skip auth entirely for allowlisted addresses
	if is_trusted_ip; then
		export SESSION_USER="local"
		export SESSION_IS_DEFAULT_PASSWORD="false"
		return 0
	fi

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

	# Session is valid. validate_session sourced the session file - use its
	# variables directly instead of forking get_session_data subshells.
	export SESSION_ID="$session_id"
	export SESSION_USER="$username"
	export SESSION_IS_DEFAULT_PASSWORD="$is_default_password"
}
