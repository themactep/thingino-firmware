# SEI RTSP Overlay Tool (`sei-rtsp.py`)

Real-time on-screen display (OSD) overlay for live Thingino RTSP streams.
Extracts embedded SEI JSON metadata from H.264 NAL units as frames arrive
and burns the text directly onto the video using ffmpeg's `drawtext` filter.

This is the live-streaming counterpart of [`sei-overlay.py`](sei-overlay.py),
which does the same for pre-recorded MP4 files.

## Requirements

- **ffmpeg** with `drawtext` and `libfreetype` support
- **Python 3.8+**
- A Thingino camera streaming via **prudynt** (the default streamer), which
  injects SEI NAL units carrying JSON metadata into the H.264 bitstream

## Quick start

```bash
# Display the stream locally with SEI overlay
./sei-rtsp.py rtsp://192.168.1.42:554/stream --display

# Re-stream with overlay on a local RTSP server
./sei-rtsp.py rtsp://192.168.1.42:554/stream --rtsp rtsp://0.0.0.0:8554/overlay

# Save 60 seconds to an MP4 file
./sei-rtsp.py rtsp://192.168.1.42:554/stream --file output.mp4 --timeout 60

# Just print SEI JSON as it arrives (no video overlay)
./sei-rtsp.py rtsp://192.168.1.42:554/stream --only-print
```

## Options

| Option | Default | Description |
|---|---|---|
| `--display` | *(default)* | Show output locally via `ffplay` |
| `--rtsp URL` | – | Re-stream with overlay to an RTSP URL (ffmpeg acts as server) |
| `--file PATH` | – | Save overlay output to a video file |
| `--font PATH` | auto-detected | TrueType font file or fontconfig name |
| `--font-size N` | 28 | Font size in pixels |
| `--border-width N` | 2 | Text outline width in pixels |
| `--position STRATEGY` | `auto` | Text placement (see below) |
| `--no-rotate` | – | Do not pre-rotate; burn OSD in raw stream coordinates |
| `--only-print` | – | Print SEI JSON to stdout (no overlay, no video output) |
| `--timeout SEC` | – | Stop after N seconds (default: run until Ctrl+C) |
| `--dry-run` | – | Print the ffmpeg commands without executing anything |

## Position strategies

| Value | Behavior |
|---|---|
| `auto` | Use per-element `(x,y)` from the SEI payload. Falls back to `top-left` if all positions are (0,0). |
| `top-left` | Stack all elements at the top-left corner, 10px from edges |
| `top-center` | Stack at top-center |
| `top-right` | Stack at top-right |
| `middle-center` | Stack at dead center |
| `bottom-left` | Stack at bottom-left |
| `bottom-right` | Stack at bottom-right |

When stacking, each subsequent element is shifted down by one `text_h`
(the height of the current text glyph), so multi-element SEI payloads
display as readable stacked lines.

## Architecture

```
 ┌──────────────────────────────────────────────────────┐
 │                INPUT: rtsp://camera:554/stream        │
 └───────┬──────────────────────────────┬───────────────┘
         │                              │
         ▼                              ▼
 ┌──────────────────┐      ┌──────────────────────────┐
 │ ffmpeg (copy)    │      │ ffmpeg / ffplay (overlay)│
 │ -c:v copy        │      │ -vf drawtext=...         │
 │ -bsf:v           │      │   textfile=<tmp>:        │
 │   h264_mp4toannexb│     │   reload=1:              │
 │ -f h264 pipe:1   │      │   fontfile=...:          │
 └────────┬─────────┘      │   fontsize=...:          │
          │                │   x=...:y=...            │
          ▼                └──────────┬───────────────┘
 ┌──────────────────┐                │
 │ StreamingNALParser│               │
 │ (Annex‑B parser) │               │
 └────────┬─────────┘               │
          │                         │
          ▼                         │
 ┌──────────────────┐               │
 │ SEIState         │               │
 │ (thread‑safe)    │               │
 └────────┬─────────┘               │
          │                         │
          ▼                         │
 ┌──────────────────┐               │
 │ OSDFileManager   │───────────────┘
 │ 8× temp files    │   writes text
 │ (100ms refresh)  │
 └──────────────────┘
```

### Pipeline stages

1. **SEI extraction** — A background `ffmpeg` process pulls the RTSP stream,
   copies the video bitstream without decoding, converts it to Annex‑B format,
   and pipes raw H.264 bytes to Python.

2. **NAL parsing** — `StreamingNALParser` scans the byte stream for NAL unit
   start codes (`00 00 01` / `00 00 00 01`). When a type‑6 (SEI) NAL is found
   with the Thingino UUID, the embedded JSON payload is extracted and passed
   to `SEIState`. The parser handles NALs that span pipe‑read boundaries.

3. **State management** — `SEIState` holds the most recent SEI data and
   provides wall‑clock‑interpolated display text. It is thread‑safe: the
   parser thread writes to it, and the OSD file writer reads from it.

4. **OSD file writing** — `OSDFileManager` runs a thread that polls `SEIState`
   every 100ms and writes the current display text to a set of temporary files
   (one per SEI element, up to 8).

5. **Video overlay** — A second `ffmpeg` (or `ffplay`) process reads the same
   RTSP stream, applies one `drawtext` filter per element, each with
   `textfile=<tmp>` and `reload=1`. ffmpeg re‑reads the text file on every
   frame, so the overlay updates within ~100ms of SEI changes.

### Why two ffmpeg processes?

- The SEI extraction path needs **raw, undecoded** H.264 to access NAL units.
- The overlay path needs **decoded** frames to burn text onto.
- These are fundamentally different processing pipelines. Using two processes
  is simpler than building a complex single‑process filter graph, and the
  bandwidth overhead is minimal (the video bitstream is copied, not re‑encoded,
  in the SEI extraction path).

## Timestamp interpolation

SEI elements with `"t": "timestamp"` carry a base wall‑clock time string
(`YYYY-MM-DD HH:MM:SS`). The tool interpolates this based on elapsed wall
clock time since the SEI was received, so the displayed timestamp advances
smoothly in real time even though SEI NAL units only arrive periodically
(typically once per GOP).

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Invalid arguments or runtime error |

## Comparison with `sei-overlay.py`

| Feature | `sei-overlay.py` | `sei-rtsp.py` |
|---|---|---|
| Input | MP4 file | Live RTSP stream |
| SEI source | Pre‑recorded bitstream | Streaming bitstream (pipe) |
| Parser | File‑based NAL scan | Streaming Annex‑B parser |
| Timestamp anchor | PTS from ffprobe | Wall clock (`time.monotonic`) |
| Overlay method | ASS subtitles via `subtitles` filter | `drawtext` with `textfile` + `reload=1` |
| Output | MP4 file | ffplay, RTSP server, MP4 file |
| Batch processing | Yes (directories) | No (single live stream) |

## Troubleshooting

**"no SEI metadata received after 15s"**

The tool didn't find any Thingino‑formatted SEI NAL units in the stream.
Possible causes:
- The camera is not running **prudynt** (the default Thingino streamer).
  Check with `BR2_PACKAGE_PRUDYNT=y` in the camera's defconfig.
- The stream URL is incorrect or the camera is unreachable.
- The camera is using a very long GOP (SEI is typically sent once per GOP).

**ffplay window shows no overlay text**

- Ensure the font is installed. Use `--font /path/to/font.ttf` to specify one explicitly.
- Try `--position top-left` to rule out positioning issues.
- Run with `--only-print` first to verify SEI data is arriving.

**"ffmpeg: drawtext: cannot load font"**

The auto‑detected font isn't available. Install a TrueType font or pass one
explicitly:

```bash
./sei-rtsp.py rtsp://... --font /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf --display
```

## See also

- [`sei-overlay.py`](sei-overlay.py) — Offline SEI overlay for MP4 files
- [Thingino firmware documentation](https://github.com/themactep/thingino-firmware)
- [prudynt streamer](https://github.com/gtxaspec/prudynt)
