#!/bin/sh
# Exercise package/thingino-send2/files/send2train against a local collector.
#
# What is covered: the opt-in gate, the pseudonymous contributor token, the
# daily and spacing limits, Retry-After and backoff handling, frame validation,
# dry-run mode, and the exact request the camera puts on the wire.
#
# Needs python3 (collector, stubs) and curl. Run it from anywhere:
#
#     sh contrib/send2train-test/run-tests.sh
set -u

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SEND2TRAIN="$REPO_ROOT/package/thingino-send2/files/send2train"
HELPER_DIR="$REPO_ROOT/package/thingino-send2/files"
COLLECTOR="$REPO_ROOT/contrib/train-collector/collector.py"
BIN_DIR="$REPO_ROOT/contrib/send2train-test/bin"
RECORDER="$REPO_ROOT/contrib/send2train-test/recorder.py"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/send2train-test.XXXXXX")
FIXTURE_JPEG="$WORK/frame.jpg"
CONFIG="$WORK/send2.json"
STATE="$WORK/state"
TOKEN_FILE="$WORK/token"
LOCK="$WORK/lock"
rc=0
collector_pid=""
recorder_pid=""

# Invoked from the EXIT trap below; shellcheck cannot see through the string.
# shellcheck disable=SC2329
cleanup() {
	[ -n "$collector_pid" ] && kill "$collector_pid" 2>/dev/null
	[ -n "$recorder_pid" ] && kill "$recorder_pid" 2>/dev/null
	rm -rf "$WORK"
}
trap cleanup EXIT

pass() { echo "PASS: $*"; }
fail() {
	echo "FAIL: $*"
	rc=1
}

# expect <description> <command...>
expect() {
	_description=$1
	shift
	if "$@"; then
		pass "$_description"
	else
		fail "$_description"
	fi
}

# 1x1 JFIF JPEG: the client only checks the magic, the collector parses it.
python3 - "$FIXTURE_JPEG" <<'PY'
import base64
import sys

BASE64 = (
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof"
    "Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB"
    "AAAAAAAAAAAAAAAAAAAAAP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8Af//Z"
)
with open(sys.argv[1], "wb") as handle:
    handle.write(base64.b64decode(BASE64))
PY

write_config() {
	# endpoint enabled daily_limit min_interval
	cat >"$CONFIG" <<EOF
{
  "train": {
    "endpoint": "$1",
    "enabled": $2,
    "daily_limit": ${3:-12},
    "min_interval": ${4:-0},
    "send_photo": true
  }
}
EOF
}

run_train() {
	PATH="$BIN_DIR:$PATH" \
		FIXTURE_JPEG="$FIXTURE_JPEG" \
		SEND2TRAIN_HELPER_DIR="$HELPER_DIR" \
		SEND2TRAIN_CONFIG="$CONFIG" \
		SEND2TRAIN_TOKEN_FILE="$TOKEN_FILE" \
		SEND2TRAIN_STATE="$STATE" \
		SEND2TRAIN_LOCK="$LOCK" \
		SEND2TRAIN_ALLOW_HTTP=1 \
		sh "$SEND2TRAIN" "$@"
}

count_frames() {
	find "$1/frames" -name '*.jpg' 2>/dev/null | wc -l | tr -d ' '
}

fresh_state() {
	rm -f "$STATE" "$TOKEN_FILE"
	rm -rf "$LOCK"
}

state_value() {
	sed -n "s/^$1=//p" "$STATE" 2>/dev/null | head -n 1
}

start_collector() {
	# data_dir per_unit_day
	_collector_data=$1
	_collector_day=${2:-100}
	_collector_port_file="$WORK/collector.port"
	rm -f "$_collector_port_file"
	TRAIN_BIND=127.0.0.1:0 \
		TRAIN_DATA_DIR="$_collector_data" \
		TRAIN_PER_UNIT_DAY="$_collector_day" \
		TRAIN_PER_UNIT_INTERVAL=0 \
		TRAIN_PER_IP_DAY=1000 \
		TRAIN_GLOBAL_DAY=10000 \
		TRAIN_MIN_DIMENSION=1 \
		TRAIN_MAX_BYTES=1048576 \
		TRAIN_IP_PEPPER=test-pepper \
		TRAIN_LOG_SILENT=1 \
		TRAIN_PORT_FILE="$_collector_port_file" \
		python3 "$COLLECTOR" 2>/dev/null &
	collector_pid=$!

	_i=0
	while [ "$_i" -lt 100 ]; do
		[ -s "$_collector_port_file" ] && return 0
		sleep 0.1
		_i=$((_i + 1))
	done
	return 1
}

stop_collector() {
	[ -n "$collector_pid" ] && kill "$collector_pid" 2>/dev/null
	wait "$collector_pid" 2>/dev/null
	collector_pid=""
}

start_recorder() {
	_recorder_record="$WORK/request.json"
	_recorder_port_file="$WORK/recorder.port"
	rm -f "$_recorder_record" "$_recorder_port_file"
	python3 "$RECORDER" "$_recorder_record" "$_recorder_port_file" 2>/dev/null &
	recorder_pid=$!

	_i=0
	while [ "$_i" -lt 100 ]; do
		[ -s "$_recorder_port_file" ] && return 0
		sleep 0.1
		_i=$((_i + 1))
	done
	return 1
}

echo "== opt-in gate"
data="$WORK/data-optin"
mkdir -p "$data"
if ! start_collector "$data"; then
	fail "collector did not start"
	exit 1
fi
port=$(cat "$WORK/collector.port")
endpoint="http://127.0.0.1:$port/v1/samples"
fresh_state
write_config "$endpoint" false
if run_train -v >"$WORK/out" 2>&1; then
	fail "disabled target accepted the call"
else
	pass "disabled target refuses"
fi
if grep -q "not enabled" "$WORK/out"; then
	pass "disabled target explains why"
else
	fail "disabled target produced: $(cat "$WORK/out")"
fi
expect "no frame uploaded while disabled" [ "$(count_frames "$data")" -eq 0 ]
if [ -f "$TOKEN_FILE" ]; then
	fail "token created while disabled"
else
	pass "no pseudonym created before opt-in"
fi

echo "== accepted upload"
fresh_state
write_config "$endpoint" true 12 0
if run_train -v >"$WORK/out" 2>&1; then
	pass "opt-in upload accepted"
else
	fail "opt-in upload failed: $(cat "$WORK/out")"
fi
expect "frame stored by collector" [ "$(count_frames "$data")" -eq 1 ]
token=$(cat "$TOKEN_FILE" 2>/dev/null)
case "$token" in
	*[!0-9a-f]* | "") fail "contributor token is not 32 hex characters" ;;
	*) [ "${#token}" -eq 32 ] && pass "contributor token is a 128-bit hex pseudonym" ;;
esac
expect "token file is owner-only" [ "$(stat -c%a "$TOKEN_FILE" 2>/dev/null)" = "600" ]

echo "== daily limit"
fresh_state
write_config "$endpoint" true 1 0
run_train >/dev/null 2>&1
before=$(count_frames "$data")
if run_train >"$WORK/out" 2>&1; then
	pass "over-quota call is not an error"
else
	fail "over-quota call failed"
fi
expect "over-quota frame is not uploaded" [ "$(count_frames "$data")" -eq "$before" ]
expect "daily counter stops at the limit" [ "$(state_value count)" = "1" ]

echo "== spacing"
fresh_state
write_config "$endpoint" true 12 600
run_train >/dev/null 2>&1
before=$(count_frames "$data")
run_train >"$WORK/out" 2>&1
expect "second frame inside the spacing window is skipped" \
	[ "$(count_frames "$data")" -eq "$before" ]

echo "== collector rate limit"
stop_collector
data429="$WORK/data-429"
mkdir -p "$data429"
start_collector "$data429" 0
port429=$(cat "$WORK/collector.port")
fresh_state
write_config "http://127.0.0.1:$port429/v1/samples" true 12 0
if run_train -v >"$WORK/out" 2>&1; then
	pass "rate-limited upload is not fatal to the motion path"
else
	fail "rate-limited upload returned failure"
fi
blocked=$(state_value blocked_until)
now=$(date +%s)
if [ -n "$blocked" ] && [ "$blocked" -gt "$now" ]; then
	pass "Retry-After is stored as a backoff window"
else
	fail "no backoff window after 429 (blocked_until='$blocked')"
fi
stop_collector

echo "== unreachable collector"
fresh_state
write_config "http://127.0.0.1:1/v1/samples" true 12 0
if run_train >"$WORK/out" 2>&1; then
	fail "unreachable collector reported success"
else
	pass "unreachable collector is an error"
fi
expect "failure counter incremented" [ "$(state_value failures)" = "1" ]
blocked=$(state_value blocked_until)
now=$(date +%s)
if [ -n "$blocked" ] && [ "$blocked" -gt "$now" ]; then
	pass "exponential backoff armed after a failed upload"
else
	fail "no backoff after a failed upload"
fi

echo "== frame validation"
mkdir -p "$WORK/data-frames"
start_collector "$WORK/data-frames"
port=$(cat "$WORK/collector.port")
fresh_state
write_config "http://127.0.0.1:$port/v1/samples" true 12 0
printf 'not a jpeg' >"$WORK/notajpeg.jpg"
if run_train -f "$WORK/notajpeg.jpg" >"$WORK/out" 2>&1; then
	fail "non-JPEG frame accepted"
else
	pass "non-JPEG frame rejected"
fi
expect "caller-supplied frame is not deleted" [ -f "$WORK/notajpeg.jpg" ]
dd if=/dev/zero of="$WORK/huge.jpg" bs=1024 count=1100 2>/dev/null
if run_train -f "$WORK/huge.jpg" >"$WORK/out" 2>&1; then
	fail "oversized frame accepted"
else
	pass "oversized frame rejected"
fi

echo "== dry run"
fresh_state
write_config "http://127.0.0.1:$port/v1/samples" true 12 0
before=$(count_frames "$WORK/data-frames")
if run_train -n >"$WORK/out" 2>&1; then
	pass "dry run succeeds"
else
	fail "dry run failed: $(cat "$WORK/out")"
fi
expect "dry run uploads nothing" [ "$(count_frames "$WORK/data-frames")" -eq "$before" ]
expect "dry run does not spend quota" [ "$(state_value count)" != "1" ]
stop_collector

echo "== what the camera sends"
if ! start_recorder; then
	fail "recorder did not start"
	exit 1
fi
recorder_port=$(cat "$WORK/recorder.port")
fresh_state
write_config "http://127.0.0.1:$recorder_port/v1/samples" true 12 0
run_train >/dev/null 2>&1
recorded_token=$(cat "$TOKEN_FILE" 2>/dev/null)
host_name=$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)
if python3 - "$WORK/request.json" "$recorded_token" "$host_name" <<'PY'; then
import json
import sys

record = json.load(open(sys.argv[1], encoding="utf-8"))
token, hostname = sys.argv[2], sys.argv[3]
headers = record["headers"]

allowed = {
    "host",
    "user-agent",
    "accept",
    "content-length",
    "content-type",
    "x-thingino-train",
    "x-thingino-token",
}
extra = sorted(set(headers) - allowed)
if extra:
    raise SystemExit(f"unexpected headers: {extra}")
if headers.get("x-thingino-train") != "1":
    raise SystemExit("missing schema header")
if headers.get("x-thingino-token") != token:
    raise SystemExit("token header missing or unstable")
if 'name="frame"' not in record["body"]:
    raise SystemExit("frame part missing")

blob = json.dumps(record)
if hostname and hostname in blob:
    raise SystemExit("hostname leaked into the request")
if "/tmp/" in blob:
    raise SystemExit("local filesystem path leaked into the request")
if 'filename="frame.jpg"' not in record["body"]:
    raise SystemExit("upload carries a local filename")
PY
	pass "request carries only the schema header, the token, and one frame"
else
	fail "request contents are not anonymous"
fi

# The same camera must keep the same pseudonym across uploads, otherwise the
# collector's per-unit limits would not hold.
first_token=$(cat "$TOKEN_FILE")
rm -f "$STATE"
run_train >/dev/null 2>&1
expect "pseudonym is stable across uploads" [ "$(cat "$TOKEN_FILE")" = "$first_token" ]
kill "$recorder_pid" 2>/dev/null
recorder_pid=""

echo
if [ "$rc" -eq 0 ]; then
	echo "All send2train tests passed."
else
	echo "send2train tests failed."
fi
exit "$rc"
