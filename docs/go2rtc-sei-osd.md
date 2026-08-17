# go2rtc SEI OSD Overlay

Real-time on-screen display overlay for Thingino camera RTSP streams, using
go2rtc as the streaming proxy and a companion Go binary (`sei-extract`) to
parse SEI metadata from H.264 NAL units.

This is the go2rtc equivalent of `scripts/sei-rtsp.py` — it extracts Thingino
SEI JSON metadata (injected by prudynt into the H.264 stream), burns it as
text overlay via ffmpeg's `drawtext` filter, and serves the result through
go2rtc for multi-protocol access (RTSP, WebRTC, MSE).

## Architecture

```
Thingino Camera (rtsp://.../stream)
         │
         ├──────────────────────────────────────────┐
         │                                          │
   ┌─────▼───────┐                           ┌──────▼──────┐
   │ ffmpeg pipe │                           │   go2rtc    │
   │ raw H.264   │                           │  container  │
   └─────┬───────┘                           │  (podman/   │
         │                                   │   docker)   │
   ┌─────▼───────┐                           │             │
   │ sei-extract │  text files    ┌─────────▶│ exec:ffmpeg │
   │ (Go, NAL    │───────────────▶│ reload=1 │  drawtext   │
   │  parser)    │  /tmp/sei-osd/ │          │  overlay    │
   └─────────────┘                └──────────┴──────┬──────┘
                                                    │
                              rtsp://host:8554/camera_raw  (passthrough)
                              rtsp://host:8554/camera_osd  (OSD overlay)
                              http://host:1984             (Web UI)
```

1. **`sei-extract`** — A Go program that reads raw H.264 Annex-B from a piped
   ffmpeg process, parses NAL units, extracts Thingino SEI user-data payloads
   (UUID `a1b2c3d4...`), and writes per-element text files plus position
   metadata to `/tmp/sei-osd/`.

2. **go2rtc** — Runs the `alexxit/go2rtc` container image (includes ffmpeg
   with `drawtext` + `libfreetype`). The `exec:` source runs an ffmpeg command
   that applies the overlay filter chain (one `drawtext` per SEI element,
   with `reload=1` to re-read text files every frame) and outputs mpegts.

3. **`run.sh`** — Orchestrator that starts the SEI extractor, waits for
   position metadata, builds the correct per-element filter graph, generates
   the go2rtc config, and launches the container.

## Quick Start

### Prerequisites

- **podman** or **docker** (for go2rtc container)
- **ffmpeg** (host, for the SEI extractor pipe)
- **jq** (for JSON parsing of SEI positions)
- **Go 1.21+** (to build `sei-extract`, one-time)

### Build

```bash
cd scripts/sei-rtsp-go2rtc/sei-extract
go build -o ../sei-extract-bin .
```

### Run

```bash
cd scripts/sei-rtsp-go2rtc
./run.sh rtsp://camera-ip:554/stream
```

With authentication:

```bash
./run.sh rtsp://user:password@192.168.1.42:554/ch0
```

## Options

```
--rtsp-port PORT       RTSP server port (default: 8554)
--api-port PORT        Web UI port (default: 1984)
--font PATH            TrueType font path or fontconfig name
                       (default: auto-detect on host, Droid Sans in container)
--font-size N          Font size in pixels (default: 28)
--border-width N       Text outline width in pixels (default: 2)
--position MODE        auto | top-left | top-right | bottom-left |
                       bottom-right | top-center | middle-center
                       auto = per-element (x,y) from SEI metadata (default)
--rotate DEG           Force rotation: 0|90|180|270 (default: 0)
--auto-rotate          Use rotation value from SEI metadata
--max-elements N       Maximum OSD text lines (default: 8)
--interval MS          Text update interval in ms (default: 100)
--timeout SEC          Stop after N seconds (default: run until Ctrl+C)
--no-passthrough       Don't serve the raw camera stream
--verbose, -v          Verbose logging
--dry-run              Print configuration without executing
```

## Output

| Stream | URL | Description |
|--------|-----|-------------|
| Raw | `rtsp://host:8554/camera_raw` | Passthrough, no overlay |
| OSD | `rtsp://host:8554/camera_osd` | Video with SEI text overlay |
| Web UI | `http://host:1984` | go2rtc dashboard |

WebRTC is also available at port `8555` for browser preview.

## Position Modes

### `auto` (default)

Each SEI element is placed at its original coordinates from the camera.
`sei-extract` captures per-element `(x, y)` on the first SEI payload and
converts them to ffmpeg `drawtext` expressions:

| SEI convention | drawtext expression |
|---|---|
| `x>0, y>0` (top-left) | `x=10, y=10` |
| `x=0, y>0` (top-center) | `x=(w-text_w)/2, y=10` |
| `x<0, y>0` (top-right) | `x=w-text_w-10, y=10` |
| `x=0, y=0` (center) | `x=(w-text_w)/2, y=(h-text_h)/2` |
| `x>0, y<0` (bottom-left) | `x=10, y=h-text_h-10` |
| `x<0, y<0` (bottom-right) | `x=w-text_w-10, y=h-text_h-10` |

### Preset modes

`top-left`, `top-right`, `bottom-left`, `bottom-right`, `top-center`,
`middle-center` — all elements stacked at the chosen corner/center.

## How SEI Timestamp Interpolation Works

SEI payloads arrive periodically (typically every few seconds). Elements
marked with `"t":"timestamp"` carry a wall-clock value that would appear
frozen between SEI frames. The `sei-extract` program anchors the timestamp
at arrival time and linearly advances it in real time, so the on-screen
clock ticks smoothly every 100ms update interval.

## Files Written

`sei-extract` writes to `/tmp/sei-osd/` (configurable via the script, not
the CLI flag):

| File | Purpose |
|------|---------|
| `sei_osd_0.txt` … `sei_osd_N.txt` | Per-element OSD text, re-read by drawtext every frame |
| `sei_positions.json` | Per-element `(x, y)` and drawtext expressions |
| `sei_meta.json` | Rotation and canvas size (`rotation`, `sw`, `sh`) |

## Native Binary Mode

If `go2rtc` is installed locally (not via container), `run.sh` uses it
directly:

```bash
# Install go2rtc binary, then:
./run.sh rtsp://camera:554/stream
```

The host's ffmpeg is used for the `exec:` overlay process in this mode,
so any font available on the host works natively.

## Troubleshooting

**"No SEI data after 15s"**
The camera stream doesn't contain Thingino SEI NAL units. Ensure the camera
is running prudynt (the default Thingino streamer) — it injects SEI metadata
into the H.264 stream.

**go2rtc container fails to start**
Ensure podman or docker is installed and the user has permissions:

```bash
podman run --rm docker.io/alexxit/go2rtc:latest go2rtc --version
```

**Font not found in container**
The container image includes Droid Sans. If you need a custom font, use
`--font /path/to/font.ttf` — the script bind-mounts the font's directory
into the container.

**Blank overlay / no text appearing**
Check that `sei-extract` is running and writing text files:

```bash
watch cat /tmp/sei-osd/sei_osd_0.txt
```

**go2rtc Web UI shows stream errors**
Check the go2rtc logs (printed to the terminal). Common issues:
- Camera RTSP URL includes credentials with special characters — try
  percent-encoding the password.
- Network connectivity between the container and the camera — the container
  uses `--net=host` so it shares the host network stack.

## Comparison with `sei-rtsp.py`

| | `sei-rtsp.py` | `sei-rtsp-go2rtc` |
|---|---|---|
| SEI parsing | Python | Go (static binary) |
| Streaming engine | ffmpeg RTSP muxer | go2rtc (RTSP + WebRTC + MSE) |
| Web UI | None | go2rtc dashboard |
| Browser preview | None | WebRTC |
| Multi-client | Single RTSP | Same stream to many clients |
| Position mode | `auto` (per-element SEI coords) | `auto` (same) + presets |
| Dependencies | Python 3.8+, ffmpeg | Go (build only), podman/docker, ffmpeg, jq |
