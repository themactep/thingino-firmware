#!/usr/bin/env bash
# Spin up a go2rtc container pointed at a Thingino camera RTSP stream.
#
# Usage:
#   ./scripts/go2rtc.sh [CAMERA_IP] [STREAM]
#
#   CAMERA_IP  – camera IP address (default: 192.168.88.31)
#   STREAM     – RTSP path (default: ch0), also accepts full rtsp:// URL
#
# Examples:
#   ./scripts/go2rtc.sh                      # connect to 192.168.88.31/ch0
#   ./scripts/go2rtc.sh 192.168.88.30        # connect to 192.168.88.30/ch0
#   ./scripts/go2rtc.sh 192.168.88.31 ch1    # connect to ch1 (sub stream)
#
# Environment:
#   CAMERA_USER, CAMERA_PASS  – RTSP credentials (default: thingino / thingino)
#   GO2RTC_PORT               – HTTP API + Web UI port (default: 1984)

set -euo pipefail

if [[ "${1:-}" =~ ^(--help|-h)$ ]]; then
    echo "Usage: $0 [CAMERA_IP] [STREAM]"
    echo ""
    echo "  CAMERA_IP  camera IP (default: 192.168.88.31)"
    echo "  STREAM     RTSP path or full URL (default: ch0)"
    exit 0
fi

CAMERA_IP="${1:-192.168.88.31}"
STREAM="${2:-ch0}"
CAMERA_USER="${CAMERA_USER:-thingino}"
CAMERA_PASS="${CAMERA_PASS:-thingino}"
GO2RTC_PORT="${GO2RTC_PORT:-1984}"

# If STREAM looks like a full URL, use it directly; otherwise build one
if [[ "$STREAM" =~ ^rtsp:// ]]; then
    RTSP_URL="$STREAM"
else
    RTSP_URL="rtsp://${CAMERA_USER}:${CAMERA_PASS}@${CAMERA_IP}/${STREAM}"
fi

CONFIG_DIR="$(mktemp -d)"
trap 'rm -rf "$CONFIG_DIR"' EXIT

LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")"

cat > "$CONFIG_DIR/go2rtc.yaml" <<EOF
log:
  format: text
  level: "debug"

api:
  listen: ":${GO2RTC_PORT}"

streams:
  thingino: ffmpeg:${RTSP_URL}#video=h264#audio=aac

webrtc:
  listen: ":8555"
  candidates:
    - ${LOCAL_IP}:8555
EOF

echo "=== go2rtc ==="
echo "  Camera:  $RTSP_URL"
echo "  Web UI:  http://localhost:${GO2RTC_PORT}"
echo "  Stream:  http://localhost:${GO2RTC_PORT}/api/stream.mjpeg?src=thingino"
echo "  WebRTC:  http://localhost:${GO2RTC_PORT}/webrtc.html?src=thingino"
echo ""

ENGINE="podman"
if ! command -v podman &>/dev/null; then
    ENGINE="docker"
fi

exec "$ENGINE" run --rm -it \
    --network host \
    -v "$CONFIG_DIR/go2rtc.yaml:/config/go2rtc.yaml:ro" \
    docker.io/alexxit/go2rtc:latest \
    go2rtc -config /config/go2rtc.yaml
