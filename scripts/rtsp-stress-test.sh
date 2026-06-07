#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
	echo -e "${BLUE}[INFO]${NC} $*"
}

print_success() {
	echo -e "${GREEN}[OK]${NC} $*"
}

print_warning() {
	echo -e "${YELLOW}[WARN]${NC} $*"
}

print_error() {
	echo -e "${RED}[ERR]${NC} $*" >&2
}

print_verbose() {
	[ "$VERBOSE" -eq 1 ] || return 0
	echo -e "${YELLOW}[DBG]${NC} $*"
}

usage() {
	cat <<'EOF'
Usage: rtsp-stress-test.sh [OPTIONS]

Host-side RTSP stress test helper for Thingino cameras.
It can:
  - run repeated ffplay sessions over RTSP/UDP or RTSP/TCP
  - optionally apply camera config changes with jct import
  - reboot between scenarios
  - capture per-session client logs and optional server log slices
  - summarize RTP loss and decode/concealment errors

Required host tools:
  ssh, ffplay, ffmpeg, python3, timeout

Required remote tools:
  jct

SSH NOTES:
  - The script uses non-interactive SSH calls.
  - Configure passwordless SSH (key/agent) for --ssh-user on the camera.
  - If SSH prompts for a password, the script will not proceed.

OPTIONS:
  --camera HOST               Camera IP or hostname
  --ssh-user USER            SSH user (default: root)
  --rtsp-user USER           RTSP username (default: thingino)
  --rtsp-pass PASS           RTSP password (default: thingino)
  --channel NAME             RTSP channel path (default: ch0)
  --rtsp-port PORT           RTSP port (default: 554)
  --transport MODE           udp or tcp (default: udp)
  --sessions N               Sessions per scenario (default: 8)
  --duration SECONDS         ffplay duration per session (default: 15)
  --pause SECONDS            Pause between sessions (default: 2)
  --output-dir DIR           Output directory (default: ./rtsp-stress-YYYYmmdd-HHMMSS)
  --server-log PATH          Optional remote prudynt log to slice per session
  --config PATH              Remote prudynt config path (default: /etc/prudynt.json)
  --remote-update PATH       Remote temp json path (default: /tmp/rtsp-stress-update.json)
  --boot-timeout SECONDS     Wait for SSH after reboot (default: 180)
  --stream-timeout SECONDS   Wait for RTSP readiness (default: 60)
  --start-cmd CMD            Optional remote command to run after reboot
  --scenario SPEC            Scenario as label:bitrate:fps:gop:est_bitrate
  --recommended-matrix       Add the standard UDP tuning matrix
  --no-restore               Do not restore original config after modified scenarios
  -v, --verbose              Print probe/retry details
  -h, --help                 Show this help

SCENARIO FORMAT:
  label:bitrate:fps:gop:est_bitrate

Use "-" for any field you want to leave unchanged.
Examples:
  current:-:-:-:-
  lowbit:1500:0:30:1800
  gop60:1700:0:60:2040
  fps20:1700:20:30:2040

NOTES:
  - If no scenario is supplied, the current camera settings are tested once.
  - --recommended-matrix appends a standard set of scenarios:
      current, lowbit1500, bitrate1600, gop60-1700, and fps20-1700
  - Modified scenarios are applied with jct import and followed by a reboot.
  - The script records per-session logs and writes summaries users can share back.
  - If --server-log is omitted, only client-side evidence is collected.

EXAMPLE:
  ./scripts/rtsp-stress-test.sh \
    --camera 192.168.88.160 \
    --server-log /mnt/nfs/prudynt.log \
    --recommended-matrix
EOF
}

require_cmd() {
	local cmd="$1"
	command -v "$cmd" >/dev/null 2>&1 || {
		print_error "Missing required command: $cmd"
		exit 1
	}
}

sanitize_label() {
	local label="$1"
	label="${label// /-}"
	label="${label//[^A-Za-z0-9._-]/_}"
	printf '%s\n' "$label"
}

CAMERA_HOST=""
SSH_USER="root"
RTSP_USER="thingino"
RTSP_PASS="thingino"
CHANNEL="ch0"
RTSP_PORT="554"
TRANSPORT="udp"
SESSIONS=8
SESSION_DURATION=15
SESSION_PAUSE=2
SERVER_LOG=""
REMOTE_CONFIG="/etc/prudynt.json"
REMOTE_UPDATE_PATH="/tmp/rtsp-stress-update.json"
BOOT_TIMEOUT=180
STREAM_TIMEOUT=60
START_CMD=""
RESTORE_CONFIG=1
RECOMMENDED_MATRIX=0
VERBOSE=0
SCENARIOS=()
OUTPUT_DIR="./rtsp-stress-$(date +%Y%m%d-%H%M%S)"

while [ $# -gt 0 ]; do
	case "$1" in
		--camera)
			CAMERA_HOST="${2:-}"
			shift 2
			;;
		--ssh-user)
			SSH_USER="${2:-}"
			shift 2
			;;
		--rtsp-user)
			RTSP_USER="${2:-}"
			shift 2
			;;
		--rtsp-pass)
			RTSP_PASS="${2:-}"
			shift 2
			;;
		--channel)
			CHANNEL="${2:-}"
			shift 2
			;;
		--rtsp-port)
			RTSP_PORT="${2:-}"
			shift 2
			;;
		--transport)
			TRANSPORT="${2:-}"
			shift 2
			;;
		--sessions)
			SESSIONS="${2:-}"
			shift 2
			;;
		--duration)
			SESSION_DURATION="${2:-}"
			shift 2
			;;
		--pause)
			SESSION_PAUSE="${2:-}"
			shift 2
			;;
		--output-dir)
			OUTPUT_DIR="${2:-}"
			shift 2
			;;
		--server-log)
			SERVER_LOG="${2:-}"
			shift 2
			;;
		--config)
			REMOTE_CONFIG="${2:-}"
			shift 2
			;;
		--remote-update)
			REMOTE_UPDATE_PATH="${2:-}"
			shift 2
			;;
		--boot-timeout)
			BOOT_TIMEOUT="${2:-}"
			shift 2
			;;
		--stream-timeout)
			STREAM_TIMEOUT="${2:-}"
			shift 2
			;;
		--start-cmd)
			START_CMD="${2:-}"
			shift 2
			;;
		--scenario)
			SCENARIOS+=("${2:-}")
			shift 2
			;;
		--recommended-matrix)
			RECOMMENDED_MATRIX=1
			shift
			;;
		--no-restore)
			RESTORE_CONFIG=0
			shift
			;;
		-v|--verbose)
			VERBOSE=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			print_error "Unknown argument: $1"
			usage
			exit 1
			;;
	esac
done

[ -n "$CAMERA_HOST" ] || {
	print_error "--camera is required"
	usage
	exit 1
}

case "$TRANSPORT" in
	udp|tcp) ;;
	*)
		print_error "--transport must be udp or tcp"
		exit 1
		;;
esac

require_cmd ssh
require_cmd ffplay
require_cmd ffmpeg
require_cmd python3
require_cmd timeout

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

if [ "${#SCENARIOS[@]}" -eq 0 ]; then
	SCENARIOS=("current:-:-:-:-")
fi

if [ "$RECOMMENDED_MATRIX" -eq 1 ]; then
	SCENARIOS+=(
		"current:-:-:-:-"
		"lowbit1500:1500:0:30:1800"
		"bitrate1600:1600:0:30:1920"
		"gop60-1700:1700:0:60:2040"
		"fps20-1700:1700:20:30:2040"
	)
fi

SSH_DEST="${SSH_USER}@${CAMERA_HOST}"
SSH_SOCKET_DIR="${TMPDIR:-/tmp}/rtsp-stress-ssh"
mkdir -p "$SSH_SOCKET_DIR"
SSH_OPTS=(
	-o ConnectTimeout=5
	-o ServerAliveInterval=5
	-o ServerAliveCountMax=3
	-o BatchMode=yes
	-o NumberOfPasswordPrompts=0
	-o StrictHostKeyChecking=accept-new
	-o ControlMaster=auto
	-o ControlPersist=600
	-o ControlPath="${SSH_SOCKET_DIR}/%C"
)

close_ssh_master() {
	ssh "${SSH_OPTS[@]}" -O exit "$SSH_DEST" >/dev/null 2>&1 || true
}

trap close_ssh_master EXIT

remote_ssh() {
	ssh "${SSH_OPTS[@]}" "$SSH_DEST" "$@"
}

RTSP_URL="rtsp://${RTSP_USER}:${RTSP_PASS}@${CAMERA_HOST}:${RTSP_PORT}/${CHANNEL}"
OVERALL_SUMMARY="${OUTPUT_DIR}/overall-summary.txt"
METADATA_FILE="${OUTPUT_DIR}/metadata.txt"
FAILED_SCENARIOS=0
MODIFIED_CONFIG=0
SSH_AUTH_ERROR=0
SSH_LAST_ERROR=""
SSH_AUTH_DETAIL=""

ssh_auth_error_match() {
	local text="$1"
	printf '%s\n' "$text" | grep -Eiq \
		'permission denied|password:|keyboard-interactive|no supported authentication methods|authentication failed'
}

wait_for_ssh() {
	local deadline=$((SECONDS + BOOT_TIMEOUT))
	local attempt=1
	local ssh_err=""
	SSH_AUTH_ERROR=0
	SSH_LAST_ERROR=""
	SSH_AUTH_DETAIL=""
	while [ "$SECONDS" -lt "$deadline" ]; do
		if ssh_err="$(remote_ssh "echo up" 2>&1)"; then
			print_verbose "SSH probe succeeded on attempt ${attempt}"
			return 0
		fi
		SSH_LAST_ERROR="${ssh_err%%$'\n'*}"
		if ssh_auth_error_match "$ssh_err"; then
			SSH_AUTH_ERROR=1
			SSH_AUTH_DETAIL="${ssh_err%%$'\n'*}"
			print_verbose "SSH probe failed due to authentication policy: ${SSH_AUTH_DETAIL}"
			return 1
		fi
		print_verbose "SSH probe attempt ${attempt} failed; retrying in 5s"
		attempt=$((attempt + 1))
		sleep 5
	done
	# One final auth-only probe helps distinguish "network timeout" vs "auth denied".
	ssh_err="$(ssh "${SSH_OPTS[@]}" -o PreferredAuthentications=publickey -o PasswordAuthentication=no "$SSH_DEST" "echo up" 2>&1 || true)"
	if ssh_auth_error_match "$ssh_err"; then
		SSH_AUTH_ERROR=1
		SSH_AUTH_DETAIL="${ssh_err%%$'\n'*}"
		print_verbose "Final SSH auth probe failed: ${SSH_AUTH_DETAIL}"
		return 1
	fi
	print_verbose "SSH probe timed out after ${BOOT_TIMEOUT}s"
	if [ -n "$SSH_LAST_ERROR" ]; then
		print_verbose "Last SSH error: ${SSH_LAST_ERROR}"
	fi
	return 1
}

wait_for_stream() {
	local deadline=$((SECONDS + STREAM_TIMEOUT))
	local attempt=1
	local probe_log=""
	while [ "$SECONDS" -lt "$deadline" ]; do
		if probe_log="$(timeout 5s ffmpeg -hide_banner -loglevel error -rtsp_transport "$TRANSPORT" \
			-i "$RTSP_URL" -t 2 -f null - 2>&1 >/dev/null)"; then
			print_verbose "RTSP probe succeeded on attempt ${attempt}"
			return 0
		fi
		if [ "$VERBOSE" -eq 1 ]; then
			local first_line
			first_line="$(printf '%s\n' "$probe_log" | head -n1)"
			if [ -n "$first_line" ]; then
				print_verbose "RTSP probe attempt ${attempt} failed: ${first_line}"
			else
				print_verbose "RTSP probe attempt ${attempt} failed with no ffmpeg error text"
			fi
		fi
		attempt=$((attempt + 1))
		sleep 2
	done
	print_verbose "RTSP probe timed out after ${STREAM_TIMEOUT}s"
	return 1
}

read_remote_key() {
	local key="$1"
	remote_ssh "jct $(printf '%q' "$REMOTE_CONFIG") get $(printf '%q' "$key")" | tr -d '\r'
}

build_update_json() {
	local output_file="$1"
	local bitrate="$2"
	local fps="$3"
	local gop="$4"
	local est="$5"

	python3 - <<'PY' "$output_file" "$bitrate" "$fps" "$gop" "$est"
import json
import sys

output, bitrate, fps, gop, est = sys.argv[1:]
data = {}

def maybe_int(value):
    return None if value == "-" else int(value)

stream = {}
rtsp = {}

bitrate_value = maybe_int(bitrate)
fps_value = maybe_int(fps)
gop_value = maybe_int(gop)
est_value = maybe_int(est)

if bitrate_value is not None:
    stream["bitrate"] = bitrate_value
if fps_value is not None:
    stream["fps"] = fps_value
if gop_value is not None:
    stream["gop"] = gop_value
if est_value is not None:
    rtsp["est_bitrate"] = est_value

if stream:
    data["stream0"] = stream
if rtsp:
    data["rtsp"] = rtsp

with open(output, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
}

send_json_to_remote() {
	local json_file="$1"
	local content
	content="$(cat "$json_file")"
	remote_ssh "cat > $(printf '%q' "$REMOTE_UPDATE_PATH") <<'JSON'
$content
JSON"
}

apply_json_update() {
	local json_file="$1"
	if [ ! -s "$json_file" ]; then
		return 0
	fi
	send_json_to_remote "$json_file"
	remote_ssh "jct $(printf '%q' "$REMOTE_CONFIG") import $(printf '%q' "$REMOTE_UPDATE_PATH") >/dev/null"
}

reboot_and_wait() {
	print_info "Rebooting camera ${CAMERA_HOST}"
	close_ssh_master
	remote_ssh "reboot -f" >/dev/null 2>&1 || true
	sleep 5
	wait_for_ssh || {
		if [ "$SSH_AUTH_ERROR" -eq 1 ]; then
			print_error "SSH authentication failed (password prompt or denied). Configure passwordless SSH for ${SSH_DEST}"
			return 1
		fi
		print_error "Camera did not return to SSH within ${BOOT_TIMEOUT}s"
		return 1
	}

	if [ -n "$START_CMD" ]; then
		print_info "Running post-reboot start command"
		remote_ssh "sh -lc $(printf '%q' "$START_CMD")"
	fi

	wait_for_stream || {
		print_error "RTSP stream did not become ready within ${STREAM_TIMEOUT}s"
		return 1
	}

	return 0
}

get_server_log_size() {
	if [ -z "$SERVER_LOG" ]; then
		echo 0
		return 0
	fi

	if ! remote_ssh "test -f $(printf '%q' "$SERVER_LOG")" >/dev/null 2>&1; then
		echo 0
		return 0
	fi

	remote_ssh "wc -c < $(printf '%q' "$SERVER_LOG")" 2>/dev/null | tr -d '[:space:]'
}

write_server_log_slice() {
	local start_bytes="$1"
	local end_bytes="$2"
	local output_file="$3"

	if [ -z "$SERVER_LOG" ] || [ "$end_bytes" -le "$start_bytes" ]; then
		return 0
	fi

	remote_ssh "python3 - <<'PY' '$start_bytes' '$end_bytes' $(printf '%q' "$SERVER_LOG")
from pathlib import Path
import sys

start = int(sys.argv[1])
end = int(sys.argv[2])
path = Path(sys.argv[3])

with path.open('rb') as fh:
    fh.seek(start)
    data = fh.read(max(0, end - start))

sys.stdout.buffer.write(data)
PY" > "$output_file" 2>&1 || true
}

summarize_client_log() {
	local log_file="$1"
	python3 - <<'PY' "$log_file"
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(errors='replace').replace('\r', '\n')
missed = sum(int(m.group(1)) for m in re.finditer(r'RTP: missed (\d+) packets', text))
decode = len(re.findall(r'error while decoding', text))
conceal = len(re.findall(r'concealing \d+ ', text))
maxdelay = len(re.findall(r'max delay reached', text))
print(missed, decode, conceal, maxdelay)
PY
}

capture_original_config() {
	ORIG_BITRATE="$(read_remote_key stream0.bitrate)"
	ORIG_FPS="$(read_remote_key stream0.fps)"
	ORIG_GOP="$(read_remote_key stream0.gop)"
	ORIG_EST="$(read_remote_key rtsp.est_bitrate)"
}

write_metadata() {
	cat > "$METADATA_FILE" <<EOF
camera=${CAMERA_HOST}
ssh_user=${SSH_USER}
rtsp_url=${RTSP_URL}
transport=${TRANSPORT}
sessions=${SESSIONS}
duration=${SESSION_DURATION}
pause=${SESSION_PAUSE}
remote_config=${REMOTE_CONFIG}
server_log=${SERVER_LOG:-<none>}
start_cmd=${START_CMD:-<none>}
original_stream0.bitrate=${ORIG_BITRATE}
original_stream0.fps=${ORIG_FPS}
original_stream0.gop=${ORIG_GOP}
original_rtsp.est_bitrate=${ORIG_EST}
EOF
}

run_scenario() {
	local scenario="$1"
	local scenario_dir label bitrate fps gop est
	IFS=':' read -r label bitrate fps gop est <<< "$scenario"

	label="$(sanitize_label "${label:-scenario}")"
	bitrate="${bitrate:--}"
	fps="${fps:--}"
	gop="${gop:--}"
	est="${est:--}"
	scenario_dir="${OUTPUT_DIR}/${label}"
	mkdir -p "$scenario_dir"

	print_info "Running scenario ${label}"
	{
		echo "scenario=${label}"
		echo "bitrate=${bitrate}"
		echo "fps=${fps}"
		echo "gop=${gop}"
		echo "est_bitrate=${est}"
	} > "${scenario_dir}/scenario.txt"

	local changed=0
	if [ "$bitrate" != "-" ] || [ "$fps" != "-" ] || [ "$gop" != "-" ] || [ "$est" != "-" ]; then
		changed=1
		MODIFIED_CONFIG=1
		build_update_json "${scenario_dir}/update.json" "$bitrate" "$fps" "$gop" "$est"
		apply_json_update "${scenario_dir}/update.json"
		reboot_and_wait || return 1
	else
		wait_for_stream || return 1
	fi

	local total_missed=0
	local total_decode=0
	local total_conceal=0
	local total_maxdelay=0
	local session

	for session in $(seq 1 "$SESSIONS"); do
		echo "=== ${label} session $(printf '%02d' "$session") ===" | tee -a "${scenario_dir}/summary.txt"
		local start_bytes end_bytes client_log server_log_file rc stats
		client_log="${scenario_dir}/client-${session}.log"
		server_log_file="${scenario_dir}/server-${session}.log"

		start_bytes="$(get_server_log_size || echo 0)"
		set +e
		timeout "${SESSION_DURATION}s" ffplay -nodisp -an -hide_banner -loglevel info \
			-rtsp_transport "$TRANSPORT" "$RTSP_URL" >"$client_log" 2>&1
		rc=$?
		set -e
		end_bytes="$(get_server_log_size || echo 0)"
		write_server_log_slice "$start_bytes" "$end_bytes" "$server_log_file"

		stats="$(summarize_client_log "$client_log")"
		read -r missed decode conceal maxdelay <<< "$stats"
		total_missed=$((total_missed + missed))
		total_decode=$((total_decode + decode))
		total_conceal=$((total_conceal + conceal))
		total_maxdelay=$((total_maxdelay + maxdelay))

		printf 'session=%d rc=%d missed_sum=%d decode=%d conceal=%d maxdelay=%d\n' \
			"$session" "$rc" "$missed" "$decode" "$conceal" "$maxdelay" >> "${scenario_dir}/summary.txt"

		sleep "$SESSION_PAUSE"
	done

	printf 'RESULT label=%s changed=%d missed=%d decode=%d conceal=%d maxdelay=%d dir=%s\n' \
		"$label" "$changed" "$total_missed" "$total_decode" "$total_conceal" "$total_maxdelay" "$scenario_dir" \
		| tee -a "$OVERALL_SUMMARY"
}

restore_original_config() {
	local restore_json="${OUTPUT_DIR}/restore-original.json"
	build_update_json "$restore_json" "$ORIG_BITRATE" "$ORIG_FPS" "$ORIG_GOP" "$ORIG_EST"
	apply_json_update "$restore_json"
	reboot_and_wait
}

print_info "Connecting to ${CAMERA_HOST}"
if [ "$VERBOSE" -eq 1 ]; then
	print_verbose "SSH target: ${SSH_DEST} (timeout ${BOOT_TIMEOUT}s)"
fi
wait_for_ssh || {
	if [ "$SSH_AUTH_ERROR" -eq 1 ]; then
		print_error "SSH authentication failed (password prompt or denied). Configure passwordless SSH for ${SSH_DEST}"
		[ -n "$SSH_AUTH_DETAIL" ] && print_error "SSH error detail: ${SSH_AUTH_DETAIL}"
		exit 1
	fi
	print_error "Unable to reach camera over SSH"
	exit 1
}

remote_ssh "command -v jct >/dev/null 2>&1" || {
	print_error "Remote host is missing jct"
	exit 1
}

capture_original_config
write_metadata

{
	echo "Run root: ${OUTPUT_DIR}"
	echo "camera=${CAMERA_HOST}"
	echo "transport=${TRANSPORT}"
	echo "sessions=${SESSIONS}"
	echo "duration=${SESSION_DURATION}"
	echo "original bitrate=${ORIG_BITRATE} fps=${ORIG_FPS} gop=${ORIG_GOP} est_bitrate=${ORIG_EST}"
} > "$OVERALL_SUMMARY"

for scenario in "${SCENARIOS[@]}"; do
	if ! run_scenario "$scenario"; then
		print_warning "Scenario failed: $scenario"
		FAILED_SCENARIOS=$((FAILED_SCENARIOS + 1))
	fi
done

if [ "$MODIFIED_CONFIG" -eq 1 ] && [ "$RESTORE_CONFIG" -eq 1 ]; then
	print_info "Restoring original camera config"
	if restore_original_config; then
		print_success "Original camera config restored"
	else
		print_warning "Failed to verify restored camera config after reboot"
		FAILED_SCENARIOS=$((FAILED_SCENARIOS + 1))
	fi
fi

if [ "$FAILED_SCENARIOS" -gt 0 ]; then
	print_warning "Completed with ${FAILED_SCENARIOS} failed scenario(s). Results are in ${OUTPUT_DIR}"
	exit 1
fi

print_success "Completed successfully. Results are in ${OUTPUT_DIR}"
