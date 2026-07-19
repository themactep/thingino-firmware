#!/usr/bin/env python3
"""
Thingino SEI RTSP Overlay Tool
==============================
Pulls a live RTSP stream from a Thingino camera, extracts SEI JSON metadata
from H.264 NAL units in real-time, and burns it as on-screen display (OSD)
text using ffmpeg's drawtext filter.

This is the live-streaming equivalent of sei-overlay.py.

Usage:
    sei-rtsp.py INPUT_URL [options]

    INPUT_URL can be an rtsp:// URL or any ffmpeg-supported live source.

Output modes (pick one, default: --display):
    --display            Show output locally via ffplay (default)
    --rtsp URL           Re-stream with overlay via ffmpeg RTSP server
    --file PATH          Save overlay output to MP4/MKV file

Options:
    --font PATH           TrueType font file (auto-detected if omitted)
    --font-size N         Font size in pixels (default: 28)
    --border-width N      Text outline width in pixels (default: 2)
    --position STRATEGY   How to place text (default: auto)
                          auto  – use SEI per‑element (x,y); fallback top‑left
                          top-left, top-right, bottom-left, bottom-right,
                          top-center, middle-center
    --only-print          Print SEI JSON as it arrives (no overlay)
    --timeout SEC         Stop after N seconds (default: run until Ctrl+C)
    --dry-run             Print commands without executing

Examples:
    # Display locally with SEI overlay
    sei-rtsp.py rtsp://192.168.1.42:554/stream --display

    # Re-stream with overlay on port 8554
    sei-rtsp.py rtsp://192.168.1.42:554/stream --rtsp rtsp://0.0.0.0:8554/overlay

    # Save 60 seconds to file
    sei-rtsp.py rtsp://192.168.1.42:554/stream --file output.mp4 --timeout 60

    # Just print SEI data as it appears
    sei-rtsp.py rtsp://192.168.1.42:554/stream --only-print

Requirements:
    - ffmpeg with drawtext and libfreetype support
    - Python 3.8+
"""

import argparse
import json
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path


# ──────────────────────────────────────────────────────────────────────
#  Constants
# ──────────────────────────────────────────────────────────────────────

THINGINO_SEI_UUID = bytes([
    0xa1, 0xb2, 0xc3, 0xd4, 0xe5, 0xf6, 0x47, 0x80,
    0xab, 0xcd, 0xef, 0x12, 0x34, 0x56, 0x78, 0x90,
])

# Common font paths to try
FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    "/usr/share/fonts/liberation/LiberationSans-Regular.ttf",
    "DejaVu Sans",   # let ffmpeg fontconfig resolve it
]

# SEI types that carry a wall‑clock timestamp → interpolate in real time
INTERPOLATED_TYPES = {"timestamp"}

# Position presets → ffmpeg drawtext x:y expressions (relative to canvas)
POSITION_PRESETS = {
    "top-left":      {"x": "10", "y": "10"},
    "top-center":    {"x": "(w-text_w)/2", "y": "10"},
    "top-right":     {"x": "w-text_w-10", "y": "10"},
    "middle-center": {"x": "(w-text_w)/2", "y": "(h-text_h)/2"},
    "bottom-left":   {"x": "10", "y": "h-text_h-10"},
    "bottom-right":  {"x": "w-text_w-10", "y": "h-text_h-10"},
}


# ──────────────────────────────────────────────────────────────────────
#  Streaming Annex‑B NAL unit parser
# ──────────────────────────────────────────────────────────────────────

class StreamingNALParser:
    """
    Feeds raw H.264 Annex‑B byte chunks and calls a callback for each
    complete SEI NAL unit that carries a recognised Thingino UUID.
    Handles NALs that span chunk boundaries.
    """

    def __init__(self, on_sei_json):
        self._buf = bytearray()
        self._on_sei_json = on_sei_json

    def feed(self, chunk: bytes):
        self._buf.extend(chunk)
        # Scan for complete NAL units delimited by 00 00 01 or 00 00 00 01
        while True:
            nal_start, start_len = self._find_start_code()
            if nal_start < 0:
                break
            nal_end = self._find_next_start(nal_start + start_len)
            if nal_end < 0:
                # Incomplete NAL – keep in buffer for next chunk
                break
            nal_bytes = self._buf[nal_start + start_len:nal_end]
            if nal_bytes:
                nal_type = nal_bytes[0] & 0x1F
                if nal_type == 6:  # SEI
                    rbsp = _remove_epb(nal_bytes)
                    json_bytes = _parse_thingino_sei(rbsp)
                    if json_bytes is not None:
                        try:
                            obj = json.loads(json_bytes.decode("utf-8"))
                            self._on_sei_json(obj)
                        except (json.JSONDecodeError, UnicodeDecodeError):
                            pass
            # Discard processed bytes
            del self._buf[:nal_end]

    def _find_start_code(self):
        """Return (offset, length) of next start code, or (-1, 0)."""
        data = self._buf
        for i in range(len(data) - 2):
            if data[i] == 0 and data[i + 1] == 0:
                if data[i + 2] == 1:
                    return (i, 3)
                if i + 3 < len(data) and data[i + 2] == 0 and data[i + 3] == 1:
                    return (i, 4)
        return (-1, 0)

    def _find_next_start(self, offset):
        """Return byte offset of next start code after `offset`, or -1."""
        data = self._buf
        for i in range(offset, len(data) - 2):
            if data[i] == 0 and data[i + 1] == 0:
                if data[i + 2] == 1:
                    return i
                if i + 3 < len(data) and data[i + 2] == 0 and data[i + 3] == 1:
                    return i
        return -1


def _remove_epb(data: bytes) -> bytes:
    """Remove emulation prevention bytes (00 00 03 → 00 00)."""
    result = bytearray()
    zero_count = 0
    for byte in data:
        if zero_count == 2 and byte == 0x03:
            zero_count = 0
            continue
        result.append(byte)
        if byte == 0:
            zero_count += 1
        else:
            zero_count = 0
    return bytes(result)


def _parse_thingino_sei(rbsp: bytes) -> bytes | None:
    """Parse SEI RBSP. Return user_data payload if Thingino UUID matches."""
    pos = 1
    length = len(rbsp)
    while pos < length - 1:
        payload_type = 0
        while pos < length and rbsp[pos] == 0xFF:
            payload_type += 255
            pos += 1
        if pos >= length:
            break
        payload_type += rbsp[pos]
        pos += 1
        payload_size = 0
        while pos < length and rbsp[pos] == 0xFF:
            payload_size += 255
            pos += 1
        if pos >= length:
            break
        payload_size += rbsp[pos]
        pos += 1
        if pos + payload_size > length:
            break
        payload_data = rbsp[pos:pos + payload_size]
        pos += payload_size
        if payload_type == 5 and len(payload_data) >= 16:
            if payload_data[:16] == THINGINO_SEI_UUID:
                return payload_data[16:]
        if payload_type == 0x80:
            break
    return None


# ──────────────────────────────────────────────────────────────────────
#  SEI state manager (thread‑safe)
# ──────────────────────────────────────────────────────────────────────

class SEIState:
    """
    Holds the latest SEI data and provides wall‑clock‑interpolated text
    for OSD rendering. Thread‑safe for producer (NAL parser) / consumer
    (text‑file updater).
    """

    def __init__(self):
        self._lock = threading.Lock()
        self._last_sei = None         # most recent SEI JSON dict
        self._anchor_wall = 0.0       # monotonic time when we first saw this SEI
        self._anchor_text: dict[str, str] = {}  # base text per interpolated element
        self._rotation = 0
        self._sw = 1920
        self._sh = 1080

    def update(self, sei: dict):
        """Called from parser thread with a new SEI payload."""
        with self._lock:
            self._last_sei = sei
            self._rotation = sei.get("rotation", self._rotation)
            self._sw = sei.get("sw", self._sw)
            self._sh = sei.get("sh", self._sh)
            # Record anchors for interpolated elements
            self._anchor_wall = time.monotonic()
            self._anchor_text = {}
            for elem in sei.get("elements", []):
                if elem.get("t") in INTERPOLATED_TYPES:
                    key = _elem_key(elem)
                    self._anchor_text[key] = elem.get("text", "")

    def get_display_lines(self, position_mode: str) -> list[dict]:
        """
        Return a list of dicts with keys: text, x_expr, y_expr
        representing OSD lines with ffmpeg drawtext positioning expressions.
        """
        with self._lock:
            sei = self._last_sei
            if sei is None:
                return []

            elements = sei.get("elements", [])
            lines = []
            elapsed = time.monotonic() - self._anchor_wall

            for elem in elements:
                text = elem.get("text", "")
                elem_type = elem.get("t", "")
                if elem_type in INTERPOLATED_TYPES:
                    key = _elem_key(elem)
                    base = self._anchor_text.get(key, text)
                    try:
                        base_dt = datetime.strptime(base, "%Y-%m-%d %H:%M:%S")
                        new_dt = base_dt + timedelta(seconds=elapsed)
                        text = new_dt.strftime("%Y-%m-%d %H:%M:%S")
                    except ValueError:
                        text = base

                x_raw = elem.get("x", 0)
                y_raw = elem.get("y", 0)

                if position_mode == "auto" and (x_raw != 0 or y_raw != 0):
                    x_expr, y_expr = _sei_pos_to_drawtext(x_raw, y_raw)
                else:
                    preset = POSITION_PRESETS.get(
                        position_mode if position_mode != "auto" else "top-left",
                        POSITION_PRESETS["top-left"],
                    )
                    # Offset each subsequent line downward
                    x_expr = preset["x"]
                    base_y = preset["y"]
                    if lines:
                        y_expr = f"{base_y}+{len(lines)}*text_h"
                    else:
                        y_expr = base_y

                lines.append({"text": text, "x_expr": x_expr, "y_expr": y_expr})

            return lines

    def get_rotation(self) -> int:
        with self._lock:
            return self._rotation

    def has_data(self) -> bool:
        with self._lock:
            return self._last_sei is not None


def _elem_key(elem: dict) -> str:
    return f"{elem.get('t','')}:{elem.get('x',0)}:{elem.get('y',0)}"


def _sei_pos_to_drawtext(x: int, y: int) -> tuple[str, str]:
    """
    Convert SEI (x, y) conventions to ffmpeg drawtext x/y expressions.
    SEI convention:
      x>0,y>0 → top-left        x=0,y>0 → top-center     x<0,y>0 → top-right
      x>0,y=0 → middle-left     x=0,y=0 → center          x<0,y=0 → middle-right
      x>0,y<0 → bottom-left     x=0,y<0 → bottom-center   x<0,y<0 → bottom-right
    """
    # X expression
    if x > 0:
        x_expr = str(x)
    elif x < 0:
        x_expr = f"w-text_w-{abs(x)}"
    else:
        x_expr = "(w-text_w)/2"

    # Y expression
    if y > 0:
        y_expr = str(y)
    elif y < 0:
        y_expr = f"h-text_h-{abs(y)}"
    else:
        y_expr = "(h-text_h)/2"

    return x_expr, y_expr


# ──────────────────────────────────────────────────────────────────────
#  Text‑file manager (writes OSD text for drawtext reload=1)
# ──────────────────────────────────────────────────────────────────────

class OSDFileManager:
    """
    Manages one or more temp files that ffmpeg's drawtext filter reads
    with reload=1. Each file holds the text for one OSD element.
    Multi‑element SEI payloads use multiple files (up to a limit).
    """

    MAX_ELEMENTS = 8

    def __init__(self, state: SEIState, position_mode: str, tmp_dir: str):
        self._state = state
        self._position_mode = position_mode
        self._tmp_dir = tmp_dir
        self._files: list[Path] = []
        self._running = False
        self._thread: threading.Thread | None = None
        self._interval = 0.1  # update every 100ms

    @property
    def textfiles(self) -> list[Path]:
        return self._files

    def start(self):
        self._running = True
        # Pre‑create MAX_ELEMENTS temp files
        for i in range(self.MAX_ELEMENTS):
            tf = Path(self._tmp_dir) / f"sei_osd_{i}.txt"
            tf.write_text("")
            self._files.append(tf)
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False
        if self._thread:
            self._thread.join(timeout=2)

    def _run(self):
        while self._running:
            lines = self._state.get_display_lines(self._position_mode)
            for i in range(self.MAX_ELEMENTS):
                if i < len(lines):
                    text = lines[i]["text"]
                else:
                    text = ""
                try:
                    self._files[i].write_text(text)
                except OSError:
                    pass
            time.sleep(self._interval)


# ──────────────────────────────────────────────────────────────────────
#  Font detection
# ──────────────────────────────────────────────────────────────────────

def find_font(preferred: str | None = None) -> str:
    if preferred:
        if os.path.isfile(preferred):
            return preferred
        # Might be a fontconfig name – just pass through
        return preferred

    for cand in FONT_CANDIDATES:
        if os.path.isfile(cand):
            return cand

    # Last resort: let fontconfig resolve it
    return "DejaVu Sans"


# ──────────────────────────────────────────────────────────────────────
#  ffmpeg command builders
# ──────────────────────────────────────────────────────────────────────

def build_sei_extract_cmd(input_url: str) -> list[str]:
    """ffmpeg command that outputs raw H.264 Annex‑B to stdout."""
    return [
        "ffmpeg", "-v", "error",
        "-rtsp_transport", "tcp",
        "-i", input_url,
        "-an", "-sn", "-dn",
        "-c:v", "copy",
        "-bsf:v", "h264_mp4toannexb",
        "-f", "h264",
        "pipe:1",
    ]


def build_drawtext_filters(textfiles: list[Path], state: SEIState,
                           font_path: str, font_size: int,
                           border_width: int, position_mode: str) -> str:
    """
    Build a ffmpeg filtergraph string with one drawtext filter per OSD
    element file. The textfile + reload=1 combo makes ffmpeg re‑read the
    file on every frame.
    """
    filters = []
    # We need the state to get x/y expressions – sample once at build time
    lines = state.get_display_lines(position_mode)

    for i, tf in enumerate(textfiles):
        if i >= len(lines):
            break
        escaped_path = str(tf).replace("\\", "\\\\").replace(":", "\\:")
        x_expr = lines[i].get("x_expr", "10")
        y_expr = lines[i].get("y_expr", "10")

        dt = (
            f"drawtext="
            f"textfile='{escaped_path}':"
            f"reload=1:"
            f"fontfile={font_path}:"
            f"fontsize={font_size}:"
            f"fontcolor=white:"
            f"bordercolor=black:"
            f"borderw={border_width}:"
            f"x={x_expr}:"
            f"y={y_expr}"
        )
        filters.append(dt)

    return ",".join(filters) if filters else "null"


def build_rotation_filter(rotation: int) -> str:
    """Return transpose filter for the given rotation, or empty string."""
    if rotation == 90:
        return "transpose=1"
    elif rotation == 180:
        return "transpose=1,transpose=1"
    elif rotation == 270:
        return "transpose=2"
    return ""


def build_output_cmd(input_url: str, vf: str, rotation: int,
                     output_mode: str, output_target: str,
                     timeout: float | None) -> list[str]:
    """Build the ffmpeg command for overlay + output."""
    cmd = [
        "ffmpeg", "-v", "info",
        "-i", input_url,
    ]
    if timeout:
        cmd.extend(["-t", str(timeout)])

    cmd.extend(["-vf", vf])
    cmd.extend(["-c:v", "libx264", "-preset", "ultrafast", "-crf", "23"])
    cmd.extend(["-c:a", "copy"])

    if rotation != 0:
        cmd.extend(["-metadata:s:v:0", "rotate=0"])

    if output_mode == "rtsp":
        cmd.extend(["-f", "rtsp", output_target])
    elif output_mode == "display":
        # ffplay doesn't take -vf from cmdline the same way; use ffplay directly
        # We'll handle this separately in main.
        pass
    elif output_mode == "file":
        cmd.extend(["-movflags", "+faststart", output_target])

    return cmd


# ──────────────────────────────────────────────────────────────────────
#  Process management helpers
# ──────────────────────────────────────────────────────────────────────

def terminate_process(proc: subprocess.Popen, name: str):
    """Gracefully terminate a subprocess."""
    if proc is None or proc.poll() is not None:
        return
    print(f"  Stopping {name} ...", file=sys.stderr)
    proc.send_signal(signal.SIGTERM)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        print(f"  Killing {name} ...", file=sys.stderr)
        proc.kill()
        proc.wait()


# ──────────────────────────────────────────────────────────────────────
#  Main
# ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Real‑time SEI overlay for live Thingino RTSP streams.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Examples:\n"
               "  sei-rtsp.py rtsp://cam:554/stream --display\n"
               "  sei-rtsp.py rtsp://cam:554/stream --rtsp rtsp://0.0.0.0:8554/out\n"
               "  sei-rtsp.py rtsp://cam:554/stream --file out.mp4 --timeout 60\n"
               "  sei-rtsp.py rtsp://cam:554/stream --only-print",
    )
    parser.add_argument("input", help="Input RTSP URL (or any ffmpeg‑supported live source)")
    parser.add_argument("--display", action="store_true",
                        help="Show output locally via ffplay (default if no output specified)")
    parser.add_argument("--rtsp", metavar="URL",
                        help="Re‑stream with overlay to an RTSP URL")
    parser.add_argument("--file", metavar="PATH",
                        help="Save overlay output to a video file")
    parser.add_argument("--font", default=None,
                        help="TrueType font file or fontconfig name")
    parser.add_argument("--font-size", type=int, default=28,
                        help="Font size in pixels (default: 28)")
    parser.add_argument("--border-width", type=int, default=2,
                        help="Text outline width in pixels (default: 2)")
    parser.add_argument("--position", default="auto",
                        choices=["auto", "top-left", "top-center", "top-right",
                                 "middle-center", "bottom-left", "bottom-right"],
                        help="Text placement strategy (default: auto)")
    parser.add_argument("--no-rotate", action="store_true",
                        help="Do NOT pre‑rotate; burn OSD in raw stream coords")
    parser.add_argument("--only-print", action="store_true",
                        help="Print SEI JSON to stdout as it arrives (no overlay)")
    parser.add_argument("--timeout", type=float, default=None,
                        help="Stop after N seconds (default: run until Ctrl+C)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print commands without executing")
    args = parser.parse_args()

    # ── Sanity check ───────────────────────────────────────────────
    output_modes = sum([bool(args.display), bool(args.rtsp), bool(args.file)])
    if output_modes == 0:
        args.display = True   # default
    elif output_modes > 1:
        print("Error: choose exactly one of --display, --rtsp, --file.", file=sys.stderr)
        sys.exit(1)

    if args.only_print:
        # Override – no output mode needed
        pass

    # ── Font ────────────────────────────────────────────────────────
    font_path = find_font(args.font)
    print(f"Using font: {font_path}", file=sys.stderr)

    # ── Shared state ────────────────────────────────────────────────
    state = SEIState()

    # ── Print‑only mode ─────────────────────────────────────────────
    if args.only_print:
        def print_sei(sei):
            print(json.dumps(sei), flush=True)
        parser_obj = StreamingNALParser(on_sei_json=print_sei)
        cmd = build_sei_extract_cmd(args.input)
        print(f"Running: {' '.join(cmd)}", file=sys.stderr)
        if args.dry_run:
            print("Dry‑run: would execute the above command.", file=sys.stderr)
            return
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        try:
            while True:
                chunk = proc.stdout.read(65536)
                if not chunk:
                    break
                parser_obj.feed(chunk)
        except KeyboardInterrupt:
            pass
        finally:
            terminate_process(proc, "SEI extractor")
        return

    # ── Start SEI extraction thread ─────────────────────────────────
    def on_sei(sei):
        state.update(sei)

    parser_obj = StreamingNALParser(on_sei_json=on_sei)
    extract_cmd = build_sei_extract_cmd(args.input)
    print(f"SEI extract: {' '.join(extract_cmd)}", file=sys.stderr)

    extract_proc = None
    ex_thread = None

    if not args.dry_run:
        extract_proc = subprocess.Popen(
            extract_cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
        )

        def extract_thread():
            try:
                while extract_proc.poll() is None:
                    chunk = extract_proc.stdout.read(65536)
                    if not chunk:
                        break
                    parser_obj.feed(chunk)
            except Exception:
                pass

        ex_thread = threading.Thread(target=extract_thread, daemon=True)
        ex_thread.start()

    # ── Wait for first SEI ──────────────────────────────────────────
    if not args.dry_run:
        print("Waiting for SEI metadata ...", file=sys.stderr)
        waited = 0
        while not state.has_data():
            time.sleep(0.1)
            waited += 0.1
            if waited > 15:
                print("Warning: no SEI metadata received after 15s. "
                      "Is this a Thingino prudynt stream?", file=sys.stderr)
                break

        if state.has_data():
            print(f"Got SEI: rotation={state.get_rotation()}° "
                  f"canvas={state._sw}x{state._sh}", file=sys.stderr)
    else:
        print("Dry‑run: would wait for SEI metadata.", file=sys.stderr)

    # ── Start OSD text file updater thread ──────────────────────────
    tmp_dir = tempfile.mkdtemp(prefix="sei_rtsp_")
    rotation = 0 if args.no_rotate else state.get_rotation()

    osd_mgr = OSDFileManager(state, args.position, tmp_dir)
    osd_mgr.start()

    # Build filtergraph
    rot_filter = build_rotation_filter(rotation)
    dt_filters = build_drawtext_filters(
        osd_mgr.textfiles, state, font_path,
        args.font_size, args.border_width, args.position,
    )

    if rot_filter and dt_filters != "null":
        vf = f"{rot_filter},{dt_filters}"
    elif rot_filter:
        vf = rot_filter
    else:
        vf = dt_filters

    # ── Choose output mode and build command ────────────────────────
    if args.display:
        # ffplay can't do RTSP output, but it can apply filters via -vf.
        # We use ffplay for local preview.
        cmd = [
            "ffplay", "-v", "info", "-hide_banner",
            "-vf", vf,
            "-window_title", "SEI RTSP Overlay",
        ]
        if args.timeout:
            cmd.extend(["-t", str(args.timeout)])
        cmd.append(args.input)

    elif args.rtsp:
        cmd = build_output_cmd(
            args.input, vf, rotation, "rtsp", args.rtsp, args.timeout
        )
        if rotation != 0:
            cmd.extend(["-metadata:s:v:0", "rotate=0"])

    elif args.file:
        cmd = build_output_cmd(
            args.input, vf, rotation, "file", args.file, args.timeout
        )

    print(f"Overlay: {' '.join(cmd)}", file=sys.stderr)

    if args.dry_run:
        print("Dry‑run: would execute the above command.", file=sys.stderr)
    else:
        output_proc = subprocess.Popen(cmd)
        try:
            output_proc.wait()
        except KeyboardInterrupt:
            print("\nInterrupted.", file=sys.stderr)
            terminate_process(output_proc, "overlay ffmpeg")
        finally:
            if output_proc.poll() is None:
                terminate_process(output_proc, "overlay ffmpeg")

    # ── Cleanup ─────────────────────────────────────────────────────
    osd_mgr.stop()
    if not args.dry_run and extract_proc is not None:
        terminate_process(extract_proc, "SEI extractor")
        if ex_thread is not None:
            ex_thread.join(timeout=3)
    # Clean temp files
    for tf in osd_mgr.textfiles:
        try:
            tf.unlink(missing_ok=True)
        except OSError:
            pass
    try:
        os.rmdir(tmp_dir)
    except OSError:
        pass

    print("Done.", file=sys.stderr)


if __name__ == "__main__":
    main()
