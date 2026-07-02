#!/bin/sh
#
# json-config-doorbell.cgi – manage Wyze Doorbell Chime configuration
#
# GET  → returns current chime config from /etc/thingino.json
# POST → executes actions: pair, unpair, play, play-group, play-all,
#         save-groups, save-events
#

. /var/www/x/auth.sh
require_auth

CONFIG_FILE="/etc/thingino.json"

json_escape() {
	printf '%s' "$1" | tr '\n' '\r' | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g' \
		-e 's/\r/\\n/g'
}

send_json() {
	status="${2:-200 OK}"
	printf 'Status: %s\n' "$status"
	printf 'Content-Type: application/json\n'
	printf 'Cache-Control: no-store\n'
	printf 'Pragma: no-cache\n'
	printf 'Connection: close\n\n'
	printf '%s\n' "$1"
	exit 0
}

json_error() {
	code="${1:-400}"
	message="$2"
	send_json "{\"error\":{\"code\":$code,\"message\":\"$(json_escape "$message")\"}}" "${3:-400 Bad Request}"
}

# ── GET: return full chime config ─────────────────────────────────

handle_get() {
	chime=$(jct "$CONFIG_FILE" get chime 2>/dev/null)
	[ -z "$chime" ] && chime='{"units":{},"groups":{},"events":{}}'

	sounds='['
	first=1
	for s in SPACE_WAVE WIND_CHIME CURIOSITY SURPRISE CHEERFUL \
		DOORBELL_1 DOORBELL_2 DOORBELL_3 DOORBELL_4 BIRD_CHIRP \
		DOG_BARK_1 DOG_BARK_2 DOOR_CLOSE DOOR_OPEN \
		SIMPLE_1 SIMPLE_2 SIMPLE_3 SIMPLE_4 INTRUDER; do
		[ $first -eq 0 ] && sounds="$sounds,"
		sounds="$sounds\"$s\""
		first=0
	done
	sounds="$sounds]"

	send_json "{\"chime\":$chime,\"sounds\":$sounds}"
}

# ── POST helpers ──────────────────────────────────────────────────

read_body() {
	REQ_FILE=$(mktemp /tmp/doorbell-req.XXXXXX)
	if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ]; then
		dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"
	else
		cat >"$REQ_FILE"
	fi
}

get_field() {
	jct "$REQ_FILE" get "$1" 2>/dev/null | tr -d '"' | tr -d '\r\n'
}

# ── Actions ───────────────────────────────────────────────────────

do_pair() {
	name=$(get_field name)
	[ -z "$name" ] && json_error 400 "Name is required for pairing"
	output=$(doorbell_ctrl pair "$name" 2>&1 </dev/null)
	rc=$?
	send_json "{\"status\":\"ok\",\"message\":\"$(json_escape "$output")\",\"rc\":$rc}"
}

do_unpair() {
	id=$(get_field id)
	[ -z "$id" ] && json_error 400 "Chime ID is required"
	output=$(doorbell_ctrl unpair "$id" 2>&1)
	rc=$?
	send_json "{\"status\":\"ok\",\"message\":\"$(json_escape "$output")\",\"rc\":$rc}"
}

do_play() {
	id=$(get_field id)
	sound=$(get_field sound)
	vol=$(get_field volume)
	rep=$(get_field repeat)
	[ -z "$id" ] && json_error 400 "Chime ID is required"
	[ -z "$sound" ] && json_error 400 "Sound is required"
	[ -z "$vol" ] && vol=5
	[ -z "$rep" ] && rep=1
	output=$(doorbell_ctrl play "$id" "$sound" "$vol" "$rep" 2>&1)
	rc=$?
	send_json "{\"status\":\"ok\",\"message\":\"$(json_escape "$output")\",\"rc\":$rc}"
}

do_play_all() {
	sound=$(get_field sound)
	vol=$(get_field volume)
	rep=$(get_field repeat)
	[ -z "$sound" ] && json_error 400 "Sound is required"
	[ -z "$vol" ] && vol=5
	[ -z "$rep" ] && rep=1
	output=$(doorbell_ctrl play-all "$sound" "$vol" "$rep" 2>&1)
	rc=$?
	send_json "{\"status\":\"ok\",\"message\":\"$(json_escape "$output")\",\"rc\":$rc}"
}

do_play_group() {
	group=$(get_field group)
	sound=$(get_field sound)
	vol=$(get_field volume)
	rep=$(get_field repeat)
	[ -z "$group" ] && json_error 400 "Group name is required"
	[ -z "$sound" ] && json_error 400 "Sound is required"
	[ -z "$vol" ] && vol=5
	[ -z "$rep" ] && rep=1
	output=$(doorbell_ctrl play-group "$group" "$sound" "$vol" "$rep" 2>&1)
	rc=$?
	send_json "{\"status\":\"ok\",\"message\":\"$(json_escape "$output")\",\"rc\":$rc}"
}

do_rename() {
	id=$(get_field id)
	name=$(get_field name)
	[ -z "$id" ] && json_error 400 "Chime ID is required"
	[ -z "$name" ] && json_error 400 "Name is required"
	jct "$CONFIG_FILE" set "chime.units.$id.name" "$name" 2>/dev/null
	send_json '{"status":"ok","message":"Chime renamed."}'
}

do_save_event() {
	event=$(get_field event)
	day_sound=$(get_field day_sound)
	day_vol=$(get_field day_volume)
	day_rep=$(get_field day_repeat)
	day_group=$(get_field day_group)
	night_sound=$(get_field night_sound)
	night_vol=$(get_field night_volume)
	night_rep=$(get_field night_repeat)
	night_group=$(get_field night_group)

	[ -z "$event" ] && json_error 400 "Event name is required"

	# Remove old event and rewrite with new per-period structure
	jct "$CONFIG_FILE" del "chime.events.$event" 2>/dev/null

	TMP_FILE=$(mktemp /tmp/doorbell-save.XXXXXX)
	echo '{"chime":{"events":{}}}' >"$TMP_FILE"

	[ -n "$day_sound" ] && jct "$TMP_FILE" set "chime.events.$event.day.sound" "$day_sound" >/dev/null 2>&1
	[ -n "$day_vol" ] && jct "$TMP_FILE" set "chime.events.$event.day.volume" "$day_vol" >/dev/null 2>&1
	[ -n "$day_rep" ] && jct "$TMP_FILE" set "chime.events.$event.day.repeat" "$day_rep" >/dev/null 2>&1
	[ -n "$day_group" ] && jct "$TMP_FILE" set "chime.events.$event.day.group" "$day_group" >/dev/null 2>&1
	[ -n "$night_sound" ] && jct "$TMP_FILE" set "chime.events.$event.night.sound" "$night_sound" >/dev/null 2>&1
	[ -n "$night_vol" ] && jct "$TMP_FILE" set "chime.events.$event.night.volume" "$night_vol" >/dev/null 2>&1
	[ -n "$night_rep" ] && jct "$TMP_FILE" set "chime.events.$event.night.repeat" "$night_rep" >/dev/null 2>&1
	[ -n "$night_group" ] && jct "$TMP_FILE" set "chime.events.$event.night.group" "$night_group" >/dev/null 2>&1

	jct "$CONFIG_FILE" import "$TMP_FILE" >/dev/null 2>&1
	rm -f "$TMP_FILE"
	send_json '{"status":"ok","message":"Event configuration saved"}'
}

do_save_group() {
	group=$(get_field group)
	members=$(get_field members)
	[ -z "$group" ] && json_error 400 "Group name is required"

	TMP_FILE=$(mktemp /tmp/doorbell-save.XXXXXX)

	# Build JSON array of members
	if [ -z "$members" ]; then
		echo "{\"chime\":{\"groups\":{\"$group\":[]}}}" >"$TMP_FILE"
	else
		arr='['
		first=1
		for m in $members; do
			[ $first -eq 0 ] && arr="$arr,"
			arr="$arr\"$m\""
			first=0
		done
		arr="$arr]"
		echo "{\"chime\":{\"groups\":{\"$group\":$arr}}}" >"$TMP_FILE"
	fi

	jct "$CONFIG_FILE" import "$TMP_FILE" >/dev/null 2>&1
	rm -f "$TMP_FILE"
	send_json '{"status":"ok","message":"Group configuration saved"}'
}

# ── Route ─────────────────────────────────────────────────────────

if [ "$REQUEST_METHOD" = "GET" ] || [ -z "$REQUEST_METHOD" ]; then
	handle_get
elif [ "$REQUEST_METHOD" = "POST" ]; then
	read_body
	action=$(get_field action)
	case "$action" in
		pair) do_pair ;;
		rename) do_rename ;;
		unpair) do_unpair ;;
		play) do_play ;;
		play-all) do_play_all ;;
		play-group) do_play_group ;;
		save-event) do_save_event ;;
		save-group) do_save_group ;;
		*) json_error 400 "Unknown action: $action" ;;
	esac
else
	json_error 405 "Method not allowed" "405 Method Not Allowed"
fi
