#!/bin/sh
# shellcheck disable=SC1091,SC3043

. /var/www/x/auth.sh
require_auth

CONFIG_SECTION="webtorrent"

send_json() {
	status="${2:-200 OK}"
	printf 'Status: %s\n' "$status"
	cat <<EOF
Content-Type: application/json
Cache-Control: no-store
Pragma: no-cache
Connection: close

$1
EOF
	exit 0
}

json_error() {
	code="${1:-400}"
	message="$2"
	# Keep the HTTP status line consistent with the JSON error code
	# unless the caller overrides it.
	status="${3:-}"
	if [ -z "$status" ]; then
		case "$code" in
			400) status="400 Bad Request" ;;
			422) status="422 Unprocessable Entity" ;;
			500) status="500 Internal Server Error" ;;
			504) status="504 Gateway Timeout" ;;
			*) status="$code" ;;
		esac
	fi
	send_json "{\"error\":{\"code\":$code,\"message\":\"$(json_escape "$message")\"}}" "$status"
}

json_escape() {
	printf '%s' "$1" | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g' \
		-e "s/\r/\\r/g" \
		-e "s/\n/\\n/g"
}

bool_to_json() {
	[ "${1}" = "true" ] && printf 'true' || printf 'false'
}

normalize_bool() {
	case "${1}" in
		1 | true | TRUE | on | ON | yes | YES) printf 'true' ;;
		*) printf 'false' ;;
	esac
}

is_int_in_range() {
	value=$1
	min=$2
	max=$3
	case "$value" in
		'' | *[!0-9]*) return 1 ;;
	esac
	[ "$value" -ge "$min" ] 2>/dev/null && [ "$value" -le "$max" ] 2>/dev/null
}

# Recompute rwd's 4-char share-key prefix locally. rwd folds the
# configured key (seed 5a a5 3c c3, XOR into fold[i&3], %36 into
# lowercase alphanumerics) and serves prefix_<key> as the runtime
# share key. Used for down-fallback URLs and stale-state detection.
key_prefix_from_key() {
	local key="$1" i=0 c n
	local fold0=90 fold1=165 fold2=60 fold3=195
	local cs="abcdefghijklmnopqrstuvwxyz0123456789"
	while [ "$i" -lt "${#key}" ]; do
		c=$(printf '%d' "'$(printf '%s' "$key" | cut -c "$((i + 1))")")
		case "$((i % 4))" in
			0) fold0=$((fold0 ^ c)) ;;
			1) fold1=$((fold1 ^ c)) ;;
			2) fold2=$((fold2 ^ c)) ;;
			3) fold3=$((fold3 ^ c)) ;;
		esac
		i=$((i + 1))
	done
	local out=""
	for n in $fold0 $fold1 $fold2 $fold3; do
		out="$out$(printf '%s' "$cs" | cut -c "$((n % 36 + 1))")"
	done
	printf '%s' "$out"
}

# Settings mirror the config FILE (/etc/raptor.conf): that is the
# persisted truth that the next restart will load. raptorctl `config get`
# would answer from the RUNNING daemon's in-memory copy when rwd is up,
# hiding just-saved or hand-edited values (cfg_live_get keeps that
# behavior for the live-vs-file comparison in build_state_payload).
# File reads are section-scoped (keys like `enabled` exist in several
# sections) and ignore commented-out template defaults.
cfg_file_get() {
	key=$1
	sed -n "/^\[$CONFIG_SECTION\]/,/^\[/p" "${WT_CONF_FILE:-/etc/raptor.conf}" 2>/dev/null |
		grep -E "^${key}[[:space:]]*=" |
		head -n 1 |
		sed "s/^${key}[[:space:]]*=[[:space:]]*//" |
		tr -d '\r"'
}
config_get() {
	cfg_file_get "$1"
}
# What the running daemon (or the file, when it is down) reports.
cfg_live_get() {
	raptorctl config get "$CONFIG_SECTION" "$1" 2>/dev/null | tr -d '\r\n"'
}

config_set() {
	key=$1
	value=$2
	raptorctl config set "$CONFIG_SECTION" "$key" "$value" >/dev/null 2>&1
}

read_config() {
	wt_enabled=$(config_get enabled)
	wt_tracker=$(config_get tracker)
	wt_stun_server=$(config_get stun_server)
	wt_stun_port=$(config_get stun_port)
	wt_tls_verify=$(config_get tls_verify)
	wt_viewer_url=$(config_get viewer_url)
	wt_share_key=$(config_get share_key)
}

defaults() {
	case "$wt_enabled" in true | false) : ;; *) wt_enabled=false ;; esac
	case "$wt_tls_verify" in true | false) : ;; *) wt_tls_verify=true ;; esac
	case "$wt_stun_port" in
		'' | *[!0-9]*) wt_stun_port="" ;;
	esac
}

viewer_default_url() {
	if [ -n "$wt_viewer_url" ]; then
		printf '%s' "$wt_viewer_url"
	else
		printf 'https://viewer.thingino.com/share.html'
	fi
}

current_share_url() {
	local payload url key
	payload=$(raptorctl rwd share 2>/dev/null)
	url=$(printf '%s' "$payload" | json_field url)
	key=$(printf '%s' "$payload" | json_field key)
	# Only rwd's absolute URLs pass through; anything else (bare fragment,
	# scheme-less host) is rebuilt from the configured/default viewer so
	# the page never shows an incomplete link.
	if [ -n "$url" ]; then
		case "$url" in
			http://* | https://*)
				printf '%s' "$url"
				return
				;;
		esac
	fi
	# rwd down: do not guess. rwd serves a pinned config key as
	# prefix_<key> where prefix is a deterministic fold of the key,
	# so build exactly the URL the next start will serve. Without a
	# pin there is no deterministic URL - show nothing rather than
	# a link that never worked.
	key=$(config_get share_key)
	if [ -n "$key" ]; then
		printf '%s#key=%s_%s' "$(viewer_default_url)" "$(key_prefix_from_key "$key")" "$key"
	fi
}

current_share_key() {
	local live
	live=$(raptorctl rwd share 2>/dev/null | json_field key)
	if [ -n "$live" ]; then
		printf '%s' "$live"
	else
		config_get share_key
	fi
}

json_field() {
	tr ',' '\n' | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

build_state_payload() {
	local cfg_key live_key share_url pinned pending
	# The settings field mirrors the config key only; the live runtime key
	# (prefixed or random) belongs to the share payload and the URL.
	cfg_key=$(config_get share_key)
	live_key=$(current_share_key)
	share_url=$(current_share_url)
	if [ -n "$cfg_key" ]; then
		pinned=true
	else
		pinned=false
	fi
	# pending_restart: when rwd is up, compare the config FILE the next
	# restart will load against what the running daemon holds in memory.
	# Any difference (saved via this page or hand-edited with
	# `raptorctl config set`) means the URL/key shown is the one the
	# daemon STARTED with, and the page must say "restart to apply"
	# instead of presenting running state as configured state.
	# (config set writes the file only; it never notifies the daemon.)
	pending=false
	if raptorctl rwd status >/dev/null 2>&1; then
		local f v
		for f in enabled tracker stun_server stun_port tls_verify viewer_url share_key; do
			v=$(cfg_live_get "$f")
			[ "$(config_get "$f")" != "$v" ] && pending=true
		done
	fi
	local url_json cfg_json key_json viewer_json
	if [ -n "$share_url" ]; then
		url_json="\"$(json_escape "$share_url")\""
	else
		url_json="null"
	fi
	if [ -n "$live_key" ]; then
		key_json="\"$(json_escape "$live_key")\""
	else
		key_json="null"
	fi
	if [ -n "$cfg_key" ]; then
		cfg_json="\"$(json_escape "$cfg_key")\""
	else
		cfg_json="null"
	fi
	if [ -n "$wt_viewer_url" ]; then
		viewer_json="\"$(json_escape "$wt_viewer_url")\""
	else
		viewer_json="null"
	fi
	cat <<EOF
{
  "webtorrent": {
    "enabled": $(bool_to_json "$wt_enabled"),
    "tracker": $(if [ -n "$wt_tracker" ]; then printf '"%s"' "$(json_escape "$wt_tracker")"; else printf null; fi),
    "stun_server": $(if [ -n "$wt_stun_server" ]; then printf '"%s"' "$(json_escape "$wt_stun_server")"; else printf null; fi),
    "stun_port": $(if [ -n "$wt_stun_port" ]; then printf '%s' "$wt_stun_port"; else printf null; fi),
    "tls_verify": $(bool_to_json "$wt_tls_verify"),
    "viewer_url": $viewer_json,
    "share_key": $cfg_json
  },
  "share": {
    "url": $url_json,
    "key": $key_json,
    "pinned": $(bool_to_json "$pinned"),
    "pending_restart": $(bool_to_json "$pending")
  }
}
EOF
}

send_state_response() {
	local message="$1"
	read_config
	defaults
	local data
	data=$(build_state_payload)
	if [ -n "$message" ]; then
		send_json "{\"ok\":true,\"message\":\"$(json_escape "$message")\",\"data\":$data}"
	else
		send_json "{\"ok\":true,\"data\":$data}"
	fi
}

urldecode() {
	printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}

read_request_body() {
	request_body=""
	[ "$REQUEST_METHOD" = "POST" ] || return
	local length="${CONTENT_LENGTH:-0}"
	case "$length" in
		'' | *[!0-9]*) length=0 ;;
	esac
	if [ "$length" -gt 0 ] 2>/dev/null; then
		request_body=$(dd bs=1 count="$length" 2>/dev/null)
	else
		request_body=""
	fi
}

parse_form_data() {
	local data="$1" pair key value
	[ -z "$data" ] && return
	local oldifs="$IFS"
	IFS='&'
	for pair in $data; do
		IFS="$oldifs"
		case "$pair" in
			*=*)
				key="${pair%%=*}"
				value="${pair#*=}"
				;;
			*)
				key="$pair"
				value=""
				;;
		esac
		key=$(urldecode "$key")
		value=$(urldecode "$value")
		case "$key" in
			action) POST_action="$value" ;;
			enabled) POST_enabled="$value" ;;
			tracker) POST_tracker="$value" ;;
			stun_server) POST_stun_server="$value" ;;
			stun_port) POST_stun_port="$value" ;;
			tls_verify) POST_tls_verify="$value" ;;
			viewer_url) POST_viewer_url="$value" ;;
			share_key) POST_share_key="$value" ;;
			*) : ;;
		esac
		IFS='&'
	done
	IFS="$oldifs"
}

process_save() {
	read_config
	wt_enabled=$(normalize_bool "$POST_enabled")
	wt_tracker="$POST_tracker"
	wt_stun_server="$POST_stun_server"
	wt_stun_port="$POST_stun_port"
	wt_tls_verify=$(normalize_bool "$POST_tls_verify")
	wt_viewer_url="$POST_viewer_url"
	wt_share_key="$POST_share_key"

	if [ -n "$wt_tracker" ]; then
		case "$wt_tracker" in
			wss://* | ws://*) : ;;
			*) json_error 422 "Tracker URL must start with wss:// or ws://" ;;
		esac
	fi
	if [ -n "$wt_viewer_url" ]; then
		case "$wt_viewer_url" in
			http://* | https://*) : ;;
			*) json_error 422 "Viewer URL must start with http:// or https://" ;;
		esac
	fi
	# Values land verbatim in raptor.conf single-line "key = value" lines:
	# reject CR/LF/TAB (newline injection) and cap lengths. The ${var%x}
	# sentinel keeps printf's control characters intact — a plain
	# $(printf '\n') collapses to an empty string. grep is NOT usable
	# here: [[:cntrl:]] never matches the newline because it is the
	# line separator, not line content.
	nl=$(printf '_\n_')
	nl=${nl#_}
	nl=${nl%_}
	cr=$(printf '_\r_')
	cr=${cr#_}
	cr=${cr%_}
	tab=$(printf '_\t_')
	tab=${tab#_}
	tab=${tab%_}
	for v in "$wt_tracker" "$wt_viewer_url" "$wt_stun_server"; do
		case "$v" in
			*"$nl"* | *"$cr"* | *"$tab"*)
				json_error 422 "Control characters are not allowed in URL or host fields"
				;;
		esac
	done
	if ! is_int_in_range "${#wt_tracker}" 0 128; then
		json_error 422 "Tracker URL must be 128 characters or fewer"
	fi
	if ! is_int_in_range "${#wt_viewer_url}" 0 128; then
		json_error 422 "Viewer URL must be 128 characters or fewer"
	fi
	if ! is_int_in_range "${#wt_stun_server}" 0 64; then
		json_error 422 "STUN server must be 64 characters or fewer"
	fi
	if [ -n "$wt_stun_port" ]; then
		if ! is_int_in_range "$wt_stun_port" 1 65535; then
			json_error 422 "STUN port must be an integer between 1 and 65535"
		fi
	fi
	case "$wt_share_key" in
		'')
			# Pin by default: an empty key field generates a fresh
			# key so the share URL survives streamer restarts.
			# Clearing a pin is done via Rotate, not by emptying.
			wt_share_key=$(config_fresh_key)
			;;
		*[!A-Za-z0-9_-]*)
			json_error 422 "Share key may only contain letters, digits, hyphen and underscore"
			;;
		*)
			# rwd requires >= 4 chars and <= sizeof(share_key) - 6
			# (share_key[32] = 4-char prefix + '_' + null = 26 usable)
			if ! is_int_in_range "${#wt_share_key}" 4 26; then
				json_error 422 "Share key length must be between 4 and 26 characters"
			fi
			;;
	esac

	local save_ok=true
	config_set enabled "$wt_enabled" || save_ok=false
	config_set tracker "$wt_tracker" || save_ok=false
	config_set stun_server "$wt_stun_server" || save_ok=false
	config_set stun_port "$wt_stun_port" || save_ok=false
	config_set tls_verify "$wt_tls_verify" || save_ok=false
	config_set viewer_url "$wt_viewer_url" || save_ok=false
	config_set share_key "$wt_share_key" || save_ok=false
	if [ "$save_ok" != true ]; then
		json_error 500 "Failed to persist WebTorrent settings" "500 Internal Server Error"
	fi

	# config set already wrote /etc/raptor.conf; `config save` would tell
	# the running daemon to write back its own stale in-memory copy.
	# The state below mirrors the file we just wrote; pending_restart
	# (file vs daemon memory) tells the page the running key is old.
	send_state_response "Settings saved. Restart the streamer to apply."
}

# Restart rwd so pending settings take effect, then return fresh state so
# the page can refill keys and URLs without another round trip.
wait_for_rwd() {
	local n=0
	while [ "$n" -lt 15 ]; do
		raptorctl rwd status >/dev/null 2>&1 && return 0
		usleep 1000000 2>/dev/null || sleep 1
		n=$((n + 1))
	done
	return 1
}

process_restart() {
	local action="restart"
	if ! raptorctl rwd status >/dev/null 2>&1; then
		# Nothing to restart; bring it up fresh.
		action="start"
	fi
	if ! raptorctl rwd "$action" >/dev/null 2>&1; then
		json_error 500 "Failed to $action the streamer" "500 Internal Server Error"
	fi
	if ! wait_for_rwd; then
		json_error 504 "Streamer restarted but did not become ready in time - reload the page to check state" "504 Gateway Timeout"
	fi
	send_state_response "Streamer restarted. Settings are now live."
}

config_fresh_key() {
	local key
	key=$(dd if=/dev/urandom bs=1 count=12 2>/dev/null | base64 | tr '+/=' '_-')
	printf '%s' "$key"
}

process_rotate() {
	# Rotate = generate a fresh key WE choose, persist it, and bounce the
	# streamer so the running key matches the config. rwd's own
	# share-rotate generates a full-length random key that cannot be
	# stored in the config (26-char bound vs 31 random chars), so a
	# rotated key can never be pinned directly - the previous flow
	# silently pinned a DIFFERENT key instead. Bouncing also invalidates
	# the old link immediately instead of at some later restart.
	local new_key
	new_key=$(config_fresh_key)
	if ! config_set share_key "$new_key"; then
		json_error 500 "Failed to persist share key" "500 Internal Server Error"
	fi
	if raptorctl rwd status >/dev/null 2>&1; then
		if ! raptorctl rwd restart >/dev/null 2>&1; then
			json_error 500 "Key rotated in config but the streamer refused to restart" "500 Internal Server Error"
		fi
		if ! wait_for_rwd; then
			json_error 504 "Key rotated in config but the streamer did not become ready in time - reload the page to check state" "504 Gateway Timeout"
		fi
		send_state_response "Share key rotated. The new key is live and the old link no longer works."
	else
		# Streamer down: the config is authoritative for the next start.
		send_state_response "Share key rotated. The streamer is not running - the new key goes live at the next start."
	fi
}

REQUEST_METHOD=${REQUEST_METHOD:-GET}

case "$REQUEST_METHOD" in
	GET | HEAD)
		send_state_response ""
		;;
	POST)
		read_request_body
		parse_form_data "$request_body"
		case "$POST_action" in
			rotate) process_rotate ;;
			restart) process_restart ;;
			*) process_save ;;
		esac
		;;
	*)
		json_error 405 "Method not allowed" "405 Method Not Allowed"
		;;
esac
