#!/usr/bin/env bash
#=============================================================================
# sei-rtsp-go2rtc.sh — go2rtc-based SEI OSD overlay for Thingino cameras
#=============================================================================
#
# Pulls an RTSP stream from a Thingino camera, extracts SEI JSON metadata
# from H.264 NAL units, and burns it as OSD text via ffmpeg drawtext —
# all served through go2rtc for multi-protocol access (RTSP, WebRTC, MSE).
#
# Architecture:
#                          rtsp://camera/stream
#                     ┌──────────────────────────────┐
#                     │                              │
#              ┌──────▼──────┐              ┌────────▼──────────┐
#              │ ffmpeg pipe │              │  ffmpeg overlay   │
#              │ (raw H.264) │              │  drawtext +       │
#              └──────┬──────┘              │  libx264 → mpegts │
#                     │                     └────────┬──────────┘
#              ┌──────▼──────┐                       │ pipe:1
#              │ sei-extract │  /tmp/sei-osd/        │
#              │ (Go, NAL    │─────────────────────► │ reload=1
#              │  parser)    │  sei_osd_*.txt        │
#              │             │  sei_positions.json   │
#              │             │  sei_meta.json        │
#              └─────────────┘                       │
#                                          ┌─────────▼────────┐
#                                          │     go2rtc       │
#                                          │  /camera_raw     │
#                                          │  /camera_osd     │
#                                          │  Web UI :1984    │
#                                          └──────────────────┘
#
# Usage:
#   ./run.sh [OPTIONS] CAMERA_URL
#
# Options:
#   --rtsp-port PORT       RTSP server port (default: 8554)
#   --api-port PORT        Web UI port (default: 1984)
#   --font PATH            TrueType font path (default: auto-detect)
#   --font-size N          Font size (default: 28)
#   --border-width N       Text outline width (default: 2)
#   --position MODE        auto | top-left | top-right | bottom-left |
#                          bottom-right | top-center | middle-center
#                          auto = use per-element (x,y) from SEI (default)
#   --rotate DEG           Force rotation: 0|90|180|270 (default: 0)
#   --auto-rotate          Use rotation from SEI metadata
#   --max-elements N       Max OSD lines (default: 8)
#   --interval MS          Text update interval in ms (default: 100)
#   --timeout SEC          Stop after N seconds (default: run until Ctrl+C)
#   --no-passthrough       Don't serve the raw camera stream
#   --verbose              Verbose logging
#   --dry-run              Print commands without executing
#
# Output:
#   rtsp://<host>:8554/camera_raw   – passthrough (unless --no-passthrough)
#   rtsp://<host>:8554/camera_osd   – stream with per-element OSD overlay
#   http://<host>:1984              – go2rtc web UI
#
# Requirements:
#   - go2rtc (https://github.com/AlexxIT/go2rtc)
#   - ffmpeg with drawtext + libfreetype + libx264
#   - sei-extract-bin (built from sei-extract/)
#   - jq (for JSON parsing in auto mode)
#=============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEI_EXTRACT="${SCRIPT_DIR}/sei-extract-bin"

# ── Defaults ──────────────────────────────────────────────────────────────────

RTSP_PORT=8554
API_PORT=1984
FONT_PATH=""
FONT_SIZE=28
BORDER_WIDTH=2
POSITION="auto"            # default: per-element SEI positions
ROTATION=0
AUTO_ROTATE=false
MAX_ELEMENTS=8
INTERVAL=100
TIMEOUT=""
VERBOSE=false
DRY_RUN=false
NO_PASSTHROUGH=false
OSD_DIR="/tmp/sei-osd"
CAMERA_URL=""

# ── Font detection ────────────────────────────────────────────────────────────

find_font() {
    local preferred="$1"
    if [[ -n "$preferred" && -f "$preferred" ]]; then
        echo "$preferred"
        return
    fi

    # Host font candidates
    local candidates=(
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
        "/usr/share/fonts/dejavu/DejaVuSans.ttf"
        "/usr/share/fonts/TTF/DejaVuSans.ttf"
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
        "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"
        "/usr/share/fonts/droid/DroidSans.ttf"
    )
    for cand in "${candidates[@]}"; do
        if [[ -f "$cand" ]]; then
            echo "$cand"
            return
        fi
    done

    # Fontconfig fallback (works on host and inside container)
    echo "Droid Sans"
}

# ── Build rotation prefix ─────────────────────────────────────────────────────

build_rotation_prefix() {
    case "$1" in
        90)  echo -n "transpose=1," ;;
        180) echo -n "transpose=1,transpose=1," ;;
        270) echo -n "transpose=2," ;;
        *)   echo -n "" ;;
    esac
}

# ── Build filter for preset position mode ─────────────────────────────────────

build_preset_filtergraph() {
    local font="$1" size="$2" border="$3" position="$4" max_elem="$5" osddir="$6"
    local x_base y_base
    local esc_font="${font//:/\\:}"

    case "$position" in
        top-left)      x_base="10";               y_base="10" ;;
        top-center)    x_base="(w-text_w)/2";     y_base="10" ;;
        top-right)     x_base="w-text_w-10";      y_base="10" ;;
        middle-center) x_base="(w-text_w)/2";     y_base="(h-text_h)/2" ;;
        bottom-left)   x_base="10";               y_base="h-text_h-10" ;;
        bottom-right)  x_base="w-text_w-10";      y_base="h-text_h-10" ;;
        *)
            echo "ERROR: unknown position: $position" >&2
            exit 1
            ;;
    esac

    local filters=()
    for ((i=0; i<max_elem; i++)); do
        local tf="${osddir}/sei_osd_${i}.txt"
        local esc_tf="${tf//:/\\:}"
        local y="$y_base"
        if (( i > 0 )); then
            y="${y_base}+${i}*text_h"
        fi
        filters+=("drawtext=textfile='${esc_tf}':reload=1:fontfile=${esc_font}:fontsize=${size}:fontcolor=white:bordercolor=black:borderw=${border}:x=${x_base}:y=${y}")
    done

    local IFS=","
    echo "${filters[*]}"
}

# ── Build filter for auto mode (per-element SEI positions) ────────────────────

build_auto_filtergraph() {
    local font="$1" size="$2" border="$3" pos_file="$4" osddir="$5"
    local esc_font="${font//:/\\:}"

    if [[ ! -f "$pos_file" ]]; then
        echo "ERROR: positions file not found: $pos_file" >&2
        exit 1
    fi

    local filters=()
    local count=$(jq '. | length' "$pos_file")

    for ((idx=0; idx<count; idx++)); do
        local x_expr y_expr
        x_expr=$(jq -r ".[$idx].x_expr" "$pos_file")
        y_expr=$(jq -r ".[$idx].y_expr" "$pos_file")

        local tf="${osddir}/sei_osd_${idx}.txt"
        local esc_tf="${tf//:/\\:}"

        filters+=("drawtext=textfile='${esc_tf}':reload=1:fontfile=${esc_font}:fontsize=${size}:fontcolor=white:bordercolor=black:borderw=${border}:x=${x_expr}:y=${y_expr}")
    done

    # If we have fewer elements than max, pad with hidden drawtext filters
    # (this ensures the filter chain is stable; empty elements show nothing)
    for ((i=count; i<MAX_ELEMENTS; i++)); do
        local tf="${osddir}/sei_osd_${i}.txt"
        local esc_tf="${tf//:/\\:}"
        filters+=("drawtext=textfile='${esc_tf}':reload=1:fontfile=${esc_font}:fontsize=${size}:fontcolor=white@0:bordercolor=black@0:borderw=${border}:x=0:y=0")
    done

    local IFS=","
    echo "${filters[*]}"
}

# ── Build ffmpeg exec command for go2rtc ──────────────────────────────────────

build_exec_cmd() {
    local camera_url="$1" vf="$2"
    echo "exec:ffmpeg -hide_banner -loglevel error -fflags +discardcorrupt -rtsp_transport tcp -i ${camera_url} -vf ${vf} -c:v libx264 -preset ultrafast -tune zerolatency -crf 23 -c:a copy -f mpegts pipe:1"
}

# ── Parse arguments ───────────────────────────────────────────────────────────

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --rtsp-port)      RTSP_PORT="$2"; shift 2 ;;
            --api-port)       API_PORT="$2"; shift 2 ;;
            --font)           FONT_PATH="$2"; USER_FONT_PATH="$2"; shift 2 ;;
            --font-size)      FONT_SIZE="$2"; shift 2 ;;
            --border-width)   BORDER_WIDTH="$2"; shift 2 ;;
            --position)       POSITION="$2"; shift 2 ;;
            --rotate)         ROTATION="$2"; shift 2 ;;
            --auto-rotate)    AUTO_ROTATE=true; shift ;;
            --max-elements)   MAX_ELEMENTS="$2"; shift 2 ;;
            --interval)       INTERVAL="$2"; shift 2 ;;
            --timeout)        TIMEOUT="$2"; shift 2 ;;
            --no-passthrough) NO_PASSTHROUGH=true; shift ;;
            --verbose|-v)     VERBOSE=true; shift ;;
            --dry-run)        DRY_RUN=true; shift ;;
            --help|-h)
                sed -n '/^#====/,/^set -/p' "$0" | sed 's/^#//; s/^ //' | head -65
                exit 0
                ;;
            *)
                if [[ -z "$CAMERA_URL" ]]; then
                    CAMERA_URL="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$CAMERA_URL" ]]; then
        echo "ERROR: CAMERA_URL required" >&2
        echo "Usage: $0 [OPTIONS] CAMERA_URL" >&2
        echo "  e.g.  $0 rtsp://192.168.1.42:554/stream" >&2
        exit 1
    fi
}

# ── Container engine detection ────────────────────────────────────────────────

detect_container_engine() {
    if command -v podman >/dev/null 2>&1; then
        echo "podman"
    elif command -v docker >/dev/null 2>&1; then
        echo "docker"
    else
        echo ""
    fi
}

# ── Validate dependencies ─────────────────────────────────────────────────────

check_deps() {
    local missing=()

    # go2rtc can be local binary OR run via container
    if ! command -v go2rtc >/dev/null 2>&1; then
        CONTAINER_ENGINE="$(detect_container_engine)"
        if [[ -z "$CONTAINER_ENGINE" ]]; then
            missing+=("go2rtc (or podman/docker)")
        fi
    fi

    command -v ffmpeg >/dev/null 2>&1 || missing+=("ffmpeg")
    command -v jq >/dev/null 2>&1 || missing+=("jq")

    if [[ ! -x "$SEI_EXTRACT" ]]; then
        echo "Building sei-extract..." >&2
        if ! command -v go >/dev/null 2>&1; then
            echo "ERROR: Go is required to build sei-extract. Install it first:" >&2
            echo "  https://go.dev/dl/" >&2
            exit 1
        fi
        (cd "${SCRIPT_DIR}/sei-extract" && go build -o ../sei-extract-bin .) || {
            echo "ERROR: sei-extract build failed" >&2
            exit 1
        }
        echo "sei-extract built successfully." >&2
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: missing dependencies: ${missing[*]}" >&2
        echo "Install them:" >&2
        echo "  go2rtc: https://github.com/AlexxIT/go2rtc/releases" >&2
        echo "     or:  podman run ... alexxit/go2rtc:ffmpeg" >&2
        echo "  ffmpeg: apt install ffmpeg" >&2
        echo "  jq:     apt install jq" >&2
        exit 1
    fi
}

# ── Config writer (callable multiple times) ──────────────────────────────────

write_go2rtc_config() {
    local exec_cmd
    exec_cmd="$(build_exec_cmd "$CAMERA_URL" "$vf")"

    local streams_yaml=""
    if [[ "$NO_PASSTHROUGH" != true ]]; then
        streams_yaml+="  camera_raw:
    - \"${CAMERA_URL}\"

"
    fi
    streams_yaml+="  camera_osd:
    - \"${exec_cmd}\""

    cat > "$CONFIG_FILE" <<YAML
# Auto-generated by sei-rtsp-go2rtc.sh
api:
  listen: ":${API_PORT}"
  origin: "*"

rtsp:
  listen: ":${RTSP_PORT}"

webrtc:
  listen: ":8555"
  candidates:
    - "stun:stun.l.google.com:19302"

log:
  level: info

streams:
${streams_yaml}
YAML
}

# ── Cleanup ───────────────────────────────────────────────────────────────────

cleanup() {
    echo ""
    echo "Shutting down..."

    if [[ -n "${SEI_PID:-}" ]] && kill -0 "$SEI_PID" 2>/dev/null; then
        kill "$SEI_PID" 2>/dev/null || true
        wait "$SEI_PID" 2>/dev/null || true
    fi

    if [[ -n "${SEI_FFMPEG_PID:-}" ]] && kill -0 "$SEI_FFMPEG_PID" 2>/dev/null; then
        kill "$SEI_FFMPEG_PID" 2>/dev/null || true
        wait "$SEI_FFMPEG_PID" 2>/dev/null || true
    fi

    if [[ -n "${GO2RTC_CONTAINER:-}" ]]; then
        echo "  Stopping go2rtc container..."
        "$CONTAINER_ENGINE" stop "$GO2RTC_CONTAINER" 2>/dev/null || true
        "$CONTAINER_ENGINE" rm -f "$GO2RTC_CONTAINER" 2>/dev/null || true
    elif [[ -n "${GO2RTC_PID:-}" ]] && kill -0 "$GO2RTC_PID" 2>/dev/null; then
        kill "$GO2RTC_PID" 2>/dev/null || true
        wait "$GO2RTC_PID" 2>/dev/null || true
    fi

    rm -rf "$OSD_DIR"
    rm -f "$CONFIG_FILE"
    echo "Done."
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"
    check_deps

    FONT_PATH="$(find_font "$FONT_PATH")"

    # ── Validate position mode ─────────────────────────────────────────────
    local valid_positions="auto top-left top-center top-right middle-center bottom-left bottom-right"
    if ! echo "$valid_positions" | grep -qw "$POSITION"; then
        echo "ERROR: invalid position '$POSITION'. Valid: $valid_positions" >&2
        exit 1
    fi

    # ── Dry-run ────────────────────────────────────────────────────────────
    if [[ "$DRY_RUN" == true ]]; then
        echo "=== Configuration ==="
        echo "  CAMERA_URL:    $CAMERA_URL"
        echo "  Font:          $FONT_PATH"
        echo "  Font size:     $FONT_SIZE"
        echo "  Border width:  $BORDER_WIDTH"
        echo "  Position:      $POSITION"
        echo "  Rotation:      $ROTATION  (auto-rotate: $AUTO_ROTATE)"
        echo "  Max elements:  $MAX_ELEMENTS"
        echo "  OSD dir:       $OSD_DIR"
        echo "  RTSP port:     $RTSP_PORT"
        echo "  API port:      $API_PORT"
        echo "  Passthrough:   $([[ "$NO_PASSTHROUGH" == true ]] && echo no || echo yes)"
        echo ""
        echo "=== SEI extractor ==="
        echo "ffmpeg -v error -i '$CAMERA_URL' -an -sn -dn -c:v copy \\"
        echo "  -bsf:v h264_mp4toannexb -f h264 pipe:1 |"
        echo "  $SEI_EXTRACT --dir '$OSD_DIR' --max-elements $MAX_ELEMENTS \\"
        echo "    --interval $INTERVAL --verbose"
        echo ""
        if [[ "$POSITION" == "auto" ]]; then
            echo "=== Filter: auto (per-element SEI positions) ==="
            echo "  (positions read from $OSD_DIR/sei_positions.json after first SEI)"
        else
            echo "=== Filter: preset '$POSITION' ==="
            local vf_dry
            vf_dry="$(build_rotation_prefix "$ROTATION")$(build_preset_filtergraph "$FONT_PATH" "$FONT_SIZE" "$BORDER_WIDTH" "$POSITION" "$MAX_ELEMENTS" "$OSD_DIR")"
            echo "  $vf_dry"
        fi
        echo ""
        echo "=== go2rtc streams ==="
        if [[ "$NO_PASSTHROUGH" != true ]]; then
            echo "  /camera_raw  → $CAMERA_URL"
        fi
        echo "  /camera_osd  → exec:ffmpeg ... -vf <filter> ... -f mpegts pipe:1"
        echo ""
        echo "  Output: rtsp://<host>:${RTSP_PORT}/camera_osd"
        echo "  Web UI: http://<host>:${API_PORT}"
        exit 0
    fi

    echo "Camera:    $CAMERA_URL"
    echo "Font:      $FONT_PATH"
    echo "Position:  $POSITION"
    echo "Rotation:  $ROTATION (auto=$AUTO_ROTATE)"

    # ── Start SEI extractor ────────────────────────────────────────────────
    echo ""
    echo "=== Starting SEI extractor ==="
    mkdir -p "$OSD_DIR"

    local sei_verbose_flag=""
    if [[ "$VERBOSE" == true ]]; then
        sei_verbose_flag="--verbose"
    fi

    ffmpeg -v error \
        -i "$CAMERA_URL" \
        -an -sn -dn \
        -c:v copy \
        -bsf:v h264_mp4toannexb \
        -f h264 \
        pipe:1 2>/dev/null \
        | "$SEI_EXTRACT" \
            --dir "$OSD_DIR" \
            --max-elements "$MAX_ELEMENTS" \
            --interval "$INTERVAL" \
            $sei_verbose_flag &
    SEI_FFMPEG_PID=$!
    SEI_PID=$!

    # ── Wait for first SEI and position data ───────────────────────────────
    echo "Waiting for SEI metadata..."
    local waited=0
    local pos_file="${OSD_DIR}/sei_positions.json"
    local meta_file="${OSD_DIR}/sei_meta.json"

    while true; do
        if [[ "$POSITION" == "auto" ]]; then
            # In auto mode, wait for positions file
            if [[ -f "$pos_file" ]] && [[ -s "$pos_file" ]]; then
                break
            fi
        else
            # In preset mode, just wait for any text file
            if [[ -f "${OSD_DIR}/sei_osd_0.txt" ]] && [[ -s "${OSD_DIR}/sei_osd_0.txt" ]]; then
                break
            fi
        fi
        sleep 0.1
        waited=$((waited + 1))
        if (( waited > 150 )); then
            echo "WARNING: No SEI data after 15s. Is this a Thingino prudynt stream?"
            break
        fi
        if [[ -n "${SEI_PID:-}" ]] && ! kill -0 "$SEI_PID" 2>/dev/null; then
            echo "ERROR: sei-extract died"
            cleanup
            exit 1
        fi
    done

    if [[ "$POSITION" == "auto" ]] && [[ -f "$pos_file" ]]; then
        local num_elements
        num_elements=$(jq '. | length' "$pos_file" 2>/dev/null || echo "0")
        echo "SEI data flowing: ${num_elements} elements with per-element positions"
        for ((ei=0; ei<num_elements; ei++)); do
            local x y x_expr y_expr
            x=$(jq -r ".[$ei].x" "$pos_file")
            y=$(jq -r ".[$ei].y" "$pos_file")
            x_expr=$(jq -r ".[$ei].x_expr" "$pos_file")
            y_expr=$(jq -r ".[$ei].y_expr" "$pos_file")
            echo "  elem[$ei]: SEI($x,$y) → drawtext(x=$x_expr, y=$y_expr)"
        done
    elif [[ -f "${OSD_DIR}/sei_osd_0.txt" ]]; then
        echo "SEI data flowing."
    fi

    # ── Auto-rotate from SEI metadata ────────────────────────────────────
    if [[ "$AUTO_ROTATE" == true ]] && [[ -f "$meta_file" ]]; then
        local sei_rot
        sei_rot=$(jq -r '.rotation // 0' "$meta_file" 2>/dev/null || echo "0")
        if [[ "$sei_rot" != "0" ]] && [[ "$sei_rot" != "null" ]]; then
            echo "Auto-rotate: SEI reports ${sei_rot}°"
            ROTATION="$sei_rot"
        fi
    fi

    # ── Build filter graph ─────────────────────────────────────────────────
    local vf
    local rot_prefix
    rot_prefix="$(build_rotation_prefix "$ROTATION")"

    if [[ "$POSITION" == "auto" ]]; then
        vf="${rot_prefix}$(build_auto_filtergraph "$FONT_PATH" "$FONT_SIZE" "$BORDER_WIDTH" "$pos_file" "$OSD_DIR")"
    else
        vf="${rot_prefix}$(build_preset_filtergraph "$FONT_PATH" "$FONT_SIZE" "$BORDER_WIDTH" "$POSITION" "$MAX_ELEMENTS" "$OSD_DIR")"
    fi

    if [[ "$VERBOSE" == true ]]; then
        echo "Filter: $vf"
    fi

    # ── Generate go2rtc config ─────────────────────────────────────────────
    CONFIG_FILE="$(mktemp /tmp/sei-rtsp-go2rtc.XXXXXX.yaml)"
    write_go2rtc_config

    if [[ "$VERBOSE" == true ]]; then
        echo "Config: $CONFIG_FILE"
        cat "$CONFIG_FILE"
    fi

    # ── Start go2rtc ──────────────────────────────────────────────────────
    echo ""
    echo "=== Starting go2rtc ==="

    trap cleanup EXIT INT TERM

    if command -v go2rtc >/dev/null 2>&1; then
        # ── Native binary ──────────────────────────────────────────────────
        echo "Using local go2rtc binary"
        local timeout_cmd=()
        if [[ -n "$TIMEOUT" ]]; then
            timeout_cmd=(timeout "$TIMEOUT")
        fi
        "${timeout_cmd[@]}" go2rtc -c "$CONFIG_FILE" &
        GO2RTC_PID=$!
        local wait_pid="$GO2RTC_PID"
    else
        # ── Container (podman/docker) ──────────────────────────────────────
        CONTAINER_ENGINE="$(detect_container_engine)"
        GO2RTC_CONTAINER="thingino-sei-go2rtc"

        # Remove any previous container with the same name
        "$CONTAINER_ENGINE" rm -f "$GO2RTC_CONTAINER" 2>/dev/null || true

        # Pull image if needed
        local go2rtc_image="docker.io/alexxit/go2rtc:latest"
        echo "Using $CONTAINER_ENGINE image: $go2rtc_image"

        # Container has Droid Sans built-in. Use it by default.
        # Only use host font if user explicitly passed --font.
        local font_mounts=()
        local user_font="${USER_FONT_PATH:-}"
        if [[ -n "$user_font" && -f "$user_font" ]]; then
            # User-specified font file: bind-mount its directory
            FONT_PATH="$user_font"
            local font_dir
            font_dir="$(dirname "$FONT_PATH")"
            font_mounts+=(-v "${font_dir}:${font_dir}:ro")
        elif [[ -n "$user_font" ]]; then
            # User-specified fontconfig name — trust them
            FONT_PATH="$user_font"
        else
            # Default: use container's built-in Droid Sans (file path avoids
            # space-in-fontconfig-name issues with go2rtc exec: parsing)
            echo "Font: using container built-in Droid Sans"
            FONT_PATH="/usr/share/fonts/droid/DroidSans.ttf"
        fi

        # Rebuild filter + config with container-appropriate font
        if [[ "$POSITION" == "auto" ]]; then
            vf="${rot_prefix}$(build_auto_filtergraph "$FONT_PATH" "$FONT_SIZE" "$BORDER_WIDTH" "$pos_file" "$OSD_DIR")"
        else
            vf="${rot_prefix}$(build_preset_filtergraph "$FONT_PATH" "$FONT_SIZE" "$BORDER_WIDTH" "$POSITION" "$MAX_ELEMENTS" "$OSD_DIR")"
        fi
        write_go2rtc_config

        if [[ "$VERBOSE" == true ]]; then
            echo "Config (container): $CONFIG_FILE"
            cat "$CONFIG_FILE"
        fi

        # Build container args
        local container_args=(
            run
            --rm
            --name "$GO2RTC_CONTAINER"
            --net=host
            -v "${CONFIG_FILE}:/config/go2rtc.yaml:ro"
            -v "${OSD_DIR}:${OSD_DIR}"
            "${font_mounts[@]}"
            "$go2rtc_image"
        )

        if [[ -n "$TIMEOUT" ]]; then
            # For timeout with container, run in background and kill after timeout
            "$CONTAINER_ENGINE" "${container_args[@]}" &
            GO2RTC_PID=$!
            (
                sleep "$TIMEOUT"
                "$CONTAINER_ENGINE" stop "$GO2RTC_CONTAINER" 2>/dev/null || true
            ) &
        else
            "$CONTAINER_ENGINE" "${container_args[@]}" &
            GO2RTC_PID=$!
        fi
        local wait_pid="$GO2RTC_PID"
    fi

    local host_ip
    host_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    echo ""
    echo "============================================"
    if [[ "$NO_PASSTHROUGH" != true ]]; then
        echo "  RTSP (raw):  rtsp://${host_ip}:${RTSP_PORT}/camera_raw"
    fi
    echo "  RTSP (OSD):  rtsp://${host_ip}:${RTSP_PORT}/camera_osd"
    echo "  Web UI:      http://${host_ip}:${API_PORT}"
    echo "  Press Ctrl+C to stop"
    echo "============================================"
    echo ""

    wait "$wait_pid" 2>/dev/null || true
    cleanup
    trap - EXIT INT TERM
}

main "$@"
