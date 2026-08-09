#!/usr/bin/env bash
# Spin up a mediamtx container to proxy or relay a Thingino camera RTSP stream.
#
# Usage:
#   ./scripts/mediamtx.sh [CAMERA_IP] [STREAM]
#
#   CAMERA_IP  – camera IP address (default: 192.168.88.31)
#   STREAM     – RTSP path (default: ch0), also accepts full rtsp:// URL
#
# Examples:
#   ./scripts/mediamtx.sh                      # proxy 192.168.88.31/ch0
#   ./scripts/mediamtx.sh 192.168.88.30 ch1    # proxy ch1 sub stream
#
# Environment:
#   CAMERA_USER, CAMERA_PASS  – RTSP credentials (default: thingino / thingino)
#   MEDIAMTX_API_PORT         – API + metrics port (default: 9997)
#   MEDIAMTX_RTSP_PORT        – RTSP listen port (default: 8554)
#   MEDIAMTX_WEBRTC_PORT      – WebRTC port (default: 8889)

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
API_PORT="${MEDIAMTX_API_PORT:-9997}"
RTSP_PORT="${MEDIAMTX_RTSP_PORT:-8554}"
WEBRTC_PORT="${MEDIAMTX_WEBRTC_PORT:-8889}"

if [[ "$STREAM" =~ ^rtsp:// ]]; then
    RTSP_URL="$STREAM"
else
    RTSP_URL="rtsp://${CAMERA_USER}:${CAMERA_PASS}@${CAMERA_IP}/${STREAM}"
fi

CONFIG_DIR="$(mktemp -d)"
trap 'rm -rf "$CONFIG_DIR"' EXIT

LISTEN_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")"

cat > "$CONFIG_DIR/mediamtx.yml" <<EOF
api: yes
apiAddress: :${API_PORT}

rtspAddress: :${RTSP_PORT}
webrtcAddress: :${WEBRTC_PORT}

paths:
  thingino:
    source: ${RTSP_URL}
    sourceOnDemand: yes
EOF

echo "=== mediamtx ==="
echo "  Camera:   $RTSP_URL"
echo "  RTSP out: rtsp://${LISTEN_IP}:${RTSP_PORT}/thingino"
echo "  WebRTC:   http://${LISTEN_IP}:${WEBRTC_PORT}/thingino"
echo "  API:      http://${LISTEN_IP}:${API_PORT}"
echo ""

ENGINE="podman"
if ! command -v podman &>/dev/null; then
    ENGINE="docker"
fi

exec "$ENGINE" run --rm -it \
    --network host \
    -v "$CONFIG_DIR/mediamtx.yml:/mediamtx.yml:ro" \
    docker.io/bluenviron/mediamtx:latest \
    mediamtx /mediamtx.yml
