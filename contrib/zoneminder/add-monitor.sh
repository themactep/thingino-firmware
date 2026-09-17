#!/usr/bin/env bash
# Register a Thingino camera as a ZoneMinder monitor through the ZM API, and
# give it a full-frame zone so Modect/Mocord actually produce events (the API
# does not create one).
#
# Usage:
#   ./add-monitor.sh [options] <camera-ip> [stream]
#
# Examples:
#   ./add-monitor.sh 192.168.88.31
#   ./add-monitor.sh --name Porch --function Record 192.168.88.31 ch1
#   ./add-monitor.sh --ptz 192.168.88.34
#
# Options:
#   --name NAME      Monitor name (default: thingino-<ip>-<stream>)
#   --function FN    Monitor/Modect/Record/Mocord/Nodect (default: Modect)
#   --user USER      RTSP user (default: thingino)
#   --pass PASS      RTSP password (default: thingino)
#   --port PORT      RTSP port (default: 554)
#   --path PATH      RTSP path (default: ch0, also the positional stream)
#   --url URL        Full source path; overrides ip/port/path/user/pass
#   --width N        Source width (default: 1920)
#   --height N       Source height (default: 1080)
#   --video-writer N 0=disabled, 1=encode, 2=passthrough (default: 2)
#   --container FMT  Auto/mp4/mkv (default: mp4)
#   --ptz            Enable ONVIF PTZ control (Thingino exposes /onvif/ptz_service)
#   --ptz-profile T  ONVIF media profile token (default: Profile_0)
#   --ptz-address U  ONVIF PTZ service URL; overrides the derived one
#   --zm-url URL     ZoneMinder base URL (default: http://localhost:8080/zm)
#   --zm-user USER   ZoneMinder API user (default: admin)
#   --zm-pass PASS   ZoneMinder API password (default: admin)
#   --no-zone        Do not create the default full-frame zone
#   -h, --help       Show this help
#
# Environment:
#   ZM_URL, ZM_USER, ZM_PASS  same as the corresponding options

set -euo pipefail

ZM_URL="${ZM_URL:-http://localhost:8080/zm}"
ZM_USER="${ZM_USER:-admin}"
ZM_PASS="${ZM_PASS:-admin}"
FUNCTION="Modect"
RTSP_USER="thingino"
RTSP_PASS="thingino"
RTSP_PORT="554"
RTSP_PATH=""
SOURCE_URL=""
WIDTH="1920"
HEIGHT="1080"
VIDEO_WRITER="2"
OUTPUT_CONTAINER="mp4"
PTZ=0
PTZ_PROFILE="Profile_0"
PTZ_ADDRESS=""
ADD_ZONE=1
NAME=""

usage() {
	sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
	case "$1" in
	--name) NAME="$2"; shift 2 ;;
	--function) FUNCTION="$2"; shift 2 ;;
	--user) RTSP_USER="$2"; shift 2 ;;
	--pass) RTSP_PASS="$2"; shift 2 ;;
	--port) RTSP_PORT="$2"; shift 2 ;;
	--path) RTSP_PATH="$2"; shift 2 ;;
	--url) SOURCE_URL="$2"; shift 2 ;;
	--width) WIDTH="$2"; shift 2 ;;
	--height) HEIGHT="$2"; shift 2 ;;
	--video-writer) VIDEO_WRITER="$2"; shift 2 ;;
	--container) OUTPUT_CONTAINER="$2"; shift 2 ;;
	--ptz) PTZ=1; shift ;;
	--ptz-profile) PTZ_PROFILE="$2"; shift 2 ;;
	--ptz-address) PTZ_ADDRESS="$2"; shift 2 ;;
	--zm-url) ZM_URL="$2"; shift 2 ;;
	--zm-user) ZM_USER="$2"; shift 2 ;;
	--zm-pass) ZM_PASS="$2"; shift 2 ;;
	--no-zone) ADD_ZONE=0; shift ;;
	-h | --help) usage; exit 0 ;;
	-*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
	*) break ;;
	esac
done

CAMERA_IP="${1:-}"
STREAM="${2:-${RTSP_PATH:-ch0}}"
[ -n "$CAMERA_IP" ] || { usage >&2; exit 1; }
[ -n "$RTSP_PATH" ] || RTSP_PATH="/$STREAM"
case "$RTSP_PATH" in /*) ;; *) RTSP_PATH="/$RTSP_PATH" ;; esac
[ -n "$SOURCE_URL" ] || SOURCE_URL="rtsp://${RTSP_USER}:${RTSP_PASS}@${CAMERA_IP}:${RTSP_PORT}${RTSP_PATH}"
[ -n "$NAME" ] || NAME="thingino-${CAMERA_IP}-${STREAM}"
[ -n "$PTZ_ADDRESS" ] || PTZ_ADDRESS="http://${RTSP_USER}:${RTSP_PASS}@${CAMERA_IP}/onvif/ptz_service"

command -v curl >/dev/null || { echo "ERROR: curl is required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 is required" >&2; exit 1; }

json_field() {
	python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for key in sys.argv[1:]:
    if isinstance(data, dict) and key in data:
        data = data[key]
    else:
        sys.exit(0)
print(data if data is not None else "")
' "$@"
}

# The packaged API has no rewrite rules unless the image fixed them; accept
# either the pretty base or the index.php PATH_INFO fallback.
api=""
for cand in "$ZM_URL/api" "$ZM_URL/api/index.php"; do
	code=$(curl -s -o /dev/null -w '%{http_code}' "$cand/host/getVersion.json" || true)
	if [ "$code" = "200" ]; then
		api="$cand"
		break
	fi
done
[ -n "$api" ] || { echo "ERROR: ZoneMinder API not reachable at $ZM_URL" >&2; exit 1; }

token=$(curl -s -X POST "$api/host/login.json" \
	--data-urlencode "user=$ZM_USER" --data-urlencode "pass=$ZM_PASS" 2>/dev/null |
	json_field access_token || true)
if [ -n "$token" ]; then
	auth="?token=$token"
else
	auth=""
fi

existing=$(curl -s "$api/monitors.json$auth" | python3 -c '
import json, sys
name = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
for entry in data.get("monitors", []):
    m = entry.get("Monitor", entry) if isinstance(entry, dict) else {}
    if m.get("Name") == name:
        print(m.get("Id", ""))
        break
' "$NAME")

if [ -n "$existing" ]; then
	echo "Monitor already exists: $NAME (Id $existing)"
	exit 0
fi

echo "Creating monitor: $NAME ($FUNCTION) -> $SOURCE_URL"
ptz_args=()
if [ "$PTZ" -eq 1 ]; then
	echo "Enabling ONVIF PTZ: $PTZ_ADDRESS (profile $PTZ_PROFILE)"
	ptz_args=(
		--data-urlencode "Monitor[Controllable]=1"
		--data-urlencode "Monitor[ControlId]=18"
		--data-urlencode "Monitor[ControlDevice]=$PTZ_PROFILE"
		--data-urlencode "Monitor[ControlAddress]=$PTZ_ADDRESS"
		--data-urlencode "Monitor[AutoStopTimeout]=1.00"
	)
fi
curl -s -X POST "$api/monitors.json$auth" \
	--data-urlencode "Monitor[Name]=$NAME" \
	--data-urlencode "Monitor[Type]=Ffmpeg" \
	--data-urlencode "Monitor[Function]=$FUNCTION" \
	--data-urlencode "Monitor[Enabled]=1" \
	--data-urlencode "Monitor[Path]=$SOURCE_URL" \
	--data-urlencode "Monitor[Method]=rtpRtsp" \
	--data-urlencode "Monitor[Width]=$WIDTH" \
	--data-urlencode "Monitor[Height]=$HEIGHT" \
	--data-urlencode "Monitor[Colours]=1" \
	--data-urlencode "Monitor[VideoWriter]=$VIDEO_WRITER" \
	--data-urlencode "Monitor[OutputCodec]=0" \
	--data-urlencode "Monitor[OutputContainer]=$OUTPUT_CONTAINER" \
	"${ptz_args[@]}" >/dev/null
monitor_id=$(curl -s "$api/monitors.json$auth" | python3 -c '
import json, sys
path = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
for entry in data.get("monitors", []):
    m = entry.get("Monitor", entry) if isinstance(entry, dict) else {}
    if m.get("Path") == path:
        print(m.get("Id", ""))
        break
' "$SOURCE_URL")

[ -n "$monitor_id" ] || { echo "ERROR: monitor was not created" >&2; exit 1; }
echo "Monitor Id: $monitor_id"

if [ "$ADD_ZONE" -eq 1 ]; then
	area=$((WIDTH * HEIGHT))
	coords="0,0 $((WIDTH - 1)),0 $((WIDTH - 1)),$((HEIGHT - 1)) 0,$((HEIGHT - 1))"
	min_alarm=$((area / 100))
	min_blob=$((area / 1000))
	echo "Creating full-frame zone for monitor $monitor_id"
	curl -s -X POST "$api/zones.json$auth" \
		--data-urlencode "Zone[MonitorId]=$monitor_id" \
		--data-urlencode "Zone[Name]=All" \
		--data-urlencode "Zone[Type]=Active" \
		--data-urlencode "Zone[Units]=Pixels" \
		--data-urlencode "Zone[NumCoords]=4" \
		--data-urlencode "Zone[Coords]=$coords" \
		--data-urlencode "Zone[Area]=$area" \
		--data-urlencode "Zone[AlarmRGB]=16711680" \
		--data-urlencode "Zone[CheckMethod]=Blobs" \
		--data-urlencode "Zone[MinPixelThreshold]=25" \
		--data-urlencode "Zone[MaxPixelThreshold]=0" \
		--data-urlencode "Zone[MinAlarmPixels]=$min_alarm" \
		--data-urlencode "Zone[MaxAlarmPixels]=$area" \
		--data-urlencode "Zone[MinFilterPixels]=$min_alarm" \
		--data-urlencode "Zone[MaxFilterPixels]=$area" \
		--data-urlencode "Zone[MinBlobPixels]=$min_blob" \
		--data-urlencode "Zone[MaxBlobPixels]=0" \
		--data-urlencode "Zone[MinBlobs]=1" \
		--data-urlencode "Zone[MaxBlobs]=0" >/dev/null
fi

echo "Done. Live view: $ZM_URL/index.php?view=watch&mid=$monitor_id"
