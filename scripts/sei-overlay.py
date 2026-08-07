#!/usr/bin/env python3
"""
Thingino SEI Overlay Tool
=========================
Extracts embedded SEI JSON metadata from prudynt-recorded MP4 files
and burns it as on-screen display using ffmpeg's subtitles filter
(via a generated ASS subtitle file).

Usage:
    sei-overlay.py INPUT.mp4 [OUTPUT.mp4] [options]
    sei-overlay.py DIRECTORY/                     # batch‑process all *.mp4

Options:
    --font PATH            TrueType font (default: DejaVuSans)
    --codec CODEC          Output video codec (default: libx264)
    --crf CRF              Quality / CRF value (default: 23)
    --preset PRESET        x264 preset (default: medium)
    --border-width N       Text outline width in pixels (default: 2)
    --no-rotate            Do NOT rotate video; burn OSD in raw coords
    --only-extract         Extract SEI timeline JSON to stdout (no encode)
    --dry-run              Print ffmpeg command without executing

Requirements:
    - ffmpeg with subtitles and libfreetype support
    - Python 3.8+
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path


# ──────────────────────────────────────────────────────────────────────
#  H.264 bitstream parsing
# ──────────────────────────────────────────────────────────────────────

THINGINO_SEI_UUID = bytes([
    0xa1, 0xb2, 0xc3, 0xd4, 0xe5, 0xf6, 0x47, 0x80,
    0xab, 0xcd, 0xef, 0x12, 0x34, 0x56, 0x78, 0x90,
])

def find_nal_units(data: bytes):
    """Yield (offset, nal_type, rbsp) for each Annex‑B NAL unit."""
    i = 0
    length = len(data)
    while i < length - 3:
        if data[i] == 0 and data[i+1] == 0:
            if data[i+2] == 1:
                start_len = 3
            elif i + 3 < length and data[i+2] == 0 and data[i+3] == 1:
                start_len = 4
            else:
                i += 1
                continue
            nal_start = i + start_len
            j = nal_start
            while j < length - 3:
                if data[j] == 0 and data[j+1] == 0:
                    if data[j+2] == 1:
                        break
                    if j + 3 < length and data[j+2] == 0 and data[j+3] == 1:
                        break
                j += 1
            nal_end = j
            nal_bytes = data[nal_start:nal_end]
            if nal_bytes:
                nal_type = nal_bytes[0] & 0x1F
                rbsp = _remove_epb(nal_bytes)
                yield (nal_start, nal_type, rbsp)
            i = nal_end
        else:
            i += 1

def _remove_epb(data: bytes) -> bytes:
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

def parse_sei_rbsp(rbsp: bytes):
    """Parse SEI RBSP. Returns user_data_unregistered payload if Thingino."""
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

def extract_sample_offsets(sizes: list[int]) -> list[tuple[int, int]]:
    offsets = []
    offset = 0
    for sz in sizes:
        offsets.append((offset, offset + sz))
        offset += sz
    return offsets


# ──────────────────────────────────────────────────────────────────────
#  SEI extraction from MP4
# ──────────────────────────────────────────────────────────────────────

def extract_sei_timeline(input_path: str):
    """Extract Thingino SEI payloads with per‑frame PTS."""
    probe_cmd = [
        "ffprobe", "-v", "quiet",
        "-show_entries", "frame=pts_time,pkt_size",
        "-select_streams", "v:0",
        "-of", "json",
        input_path,
    ]
    probe = subprocess.run(probe_cmd, capture_output=True, text=True, check=True)
    probe_data = json.loads(probe.stdout)
    frames = probe_data.get("frames", [])

    pts_times = []
    frame_sizes = []
    for f in frames:
        pts_times.append(float(f.get("pts_time", 0)))
        frame_sizes.append(int(f.get("pkt_size", 0)))

    extract_cmd = [
        "ffmpeg", "-v", "error",
        "-i", input_path,
        "-c:v", "copy",
        "-bsf:v", "h264_mp4toannexb",
        "-f", "h264",
        "pipe:1",
    ]
    extract = subprocess.run(extract_cmd, capture_output=True, check=True)
    raw_bitstream = extract.stdout

    offsets = extract_sample_offsets(frame_sizes)
    sei_by_frame = {}

    for nal_offset, nal_type, rbsp in find_nal_units(raw_bitstream):
        if nal_type != 6:
            continue
        json_bytes = parse_sei_rbsp(rbsp)
        if json_bytes is None:
            continue
        frame_idx = None
        for idx, (start, end) in enumerate(offsets):
            if start <= nal_offset < end:
                frame_idx = idx
                break
        if frame_idx is not None:
            try:
                sei_json = json.loads(json_bytes.decode("utf-8"))
                sei_by_frame[frame_idx] = sei_json
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue

    timeline = []
    last_sei = None
    for i in range(min(len(pts_times), len(frame_sizes))):
        if i in sei_by_frame:
            last_sei = sei_by_frame[i]
        if last_sei is not None and i < len(pts_times):
            timeline.append({
                "frame": i,
                "pts": pts_times[i],
                "sei": last_sei,
            })
    return timeline


# ──────────────────────────────────────────────────────────────────────
#  Grouping
# ──────────────────────────────────────────────────────────────────────

def group_timeline(timeline):
    """Collapse frame‑granular timeline into SEI segments with anchor_pts."""
    if not timeline:
        return []
    groups = []
    current_sei_str = None
    display_start = 0.0
    anchor_pts = 0.0
    first_seen = False
    for entry in timeline:
        sei_str = json.dumps(entry["sei"], sort_keys=True)
        if sei_str != current_sei_str:
            if current_sei_str is not None:
                groups.append({
                    "start": display_start,
                    "end": entry["pts"],
                    "sei": json.loads(current_sei_str),
                    "anchor_pts": anchor_pts,
                })
            current_sei_str = sei_str
            anchor_pts = entry["pts"]
            if not first_seen:
                first_seen = True
            else:
                display_start = entry["pts"]
    if current_sei_str is not None:
        groups.append({
            "start": display_start,
            "end": timeline[-1]["pts"] + 0.1,
            "sei": json.loads(current_sei_str),
            "anchor_pts": anchor_pts,
        })
    return groups


# ──────────────────────────────────────────────────────────────────────
#  Time interpolation helpers
# ──────────────────────────────────────────────────────────────────────

INTERPOLATED_TYPES = {"timestamp"}

def _parse_datetime(text: str):
    return datetime.strptime(text, "%Y-%m-%d %H:%M:%S")


# ──────────────────────────────────────────────────────────────────────
#  ASS subtitle generation
# ──────────────────────────────────────────────────────────────────────

# ASS alignment codes mapping OSD position convention to ASS \an values.
#   x>0,y>0 → top-left        \an7
#   x=0,y>0 → top-center      \an8
#   x<0,y>0 → top-right       \an9
#   x>0,y=0 → middle-left     \an4
#   x=0,y=0 → middle-center   \an5
#   x<0,y=0 → middle-right    \an6
#   x>0,y<0 → bottom-left     \an1
#   x=0,y<0 → bottom-center   \an2
#   x<0,y<0 → bottom-right    \an3
def _ass_alignment(x: int, y: int) -> int:
    if y > 0:
        row = 7  # top
    elif y < 0:
        row = 1  # bottom
    else:
        row = 4  # middle
    if x > 0:
        return row      # left
    elif x < 0:
        return row + 2  # right
    else:
        return row + 1  # center


def _ass_margin(raw: int, canvas_dim: int) -> int:
    """Convert OSD position to ASS margin (pixels from edge).
       For x>0: left margin = raw.  For x<0: right margin = abs(raw)."""
    if raw > 0:
        return raw
    if raw < 0:
        return -raw
    return 0  # centered → margin irrelevant


def _ass_color(hex_str: str) -> str:
    """Convert '#RRGGBBAA' → ASS '&HAABBGGRR' (ABGR order)."""
    h = hex_str.lstrip("#")
    if len(h) == 8:
        rr, gg, bb, aa = h[0:2], h[2:4], h[4:6], h[6:8]
    elif len(h) == 6:
        rr, gg, bb, aa = h[0:2], h[2:4], h[4:6], "FF"
    else:
        return "&H00FFFFFF"
    return f"&H{aa}{bb}{gg}{rr}"


def _pts_to_ass_time(pts: float) -> str:
    """Convert seconds → ASS time 'H:MM:SS.cc'."""
    h = int(pts // 3600)
    m = int((pts % 3600) // 60)
    s = pts % 60
    return f"{h}:{m:02d}:{s:05.2f}"


def generate_ass(groups, timeline, font_name: str, border_width: int,
                stroke_color: str, rotation: int, sw: int, sh: int):
    """Generate an ASS subtitle file as a string."""
    total_end = timeline[-1]["pts"] + 0.1

    # Set PlayRes to match the display canvas so fontsize / margins
    # are in actual pixel units (rotation swaps w↔h).
    if rotation in (90, 270):
        play_x, play_y = sh, sw
    else:
        play_x, play_y = sw, sh

    def find_group(t):
        for g in groups:
            if g["start"] <= t < g["end"]:
                return g
        return groups[-1]

    time_events = []
    t = 0.0
    while t < total_end:
        sub_end = min(t + 1.0, total_end)
        group = find_group(t + 0.001)
        sei = group["sei"]
        anchor_pts = group.get("anchor_pts", group["start"])
        for elem in sei.get("elements", []):
            elem_type = elem.get("t", "")
            text = elem.get("text", "")
            if elem_type in INTERPOLATED_TYPES:
                try:
                    base_dt = _parse_datetime(text)
                    offset = t - anchor_pts
                    new_dt = base_dt + timedelta(seconds=offset)
                    text = new_dt.strftime("%Y-%m-%d %H:%M:%S")
                except ValueError:
                    pass
            time_events.append((t, sub_end, text, elem))
        t = sub_end

    ass = "[Script Info]\n"
    ass += "ScriptType: v4.00+\n"
    ass += f"PlayResX: {play_x}\nPlayResY: {play_y}\n"
    ass += "WrapStyle: 0\n\n"
    ass += "[V4+ Styles]\n"
    ass += ("Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, "
            "OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, "
            "ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, "
            "Alignment, MarginL, MarginR, MarginV, Encoding\n")
    ass += (f"Style: Default,{font_name},{32},&H00FFFFFF,&H00000000,"
            f"{stroke_color},&H00000000,0,0,0,0,100,100,0,0,1,{border_width},0,"
            f"2,10,10,10,1\n\n")
    ass += "[Events]\n"
    ass += "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"

    layer = 0
    for start_pts, end_pts, text, elem in time_events:
        x_raw = elem.get("x", 0)
        y_raw = elem.get("y", 0)

        # Use reasonable defaults — new SEI format doesn't include colors/sizes
        fs = 32
        primary = "&H00FFFFFF"  # white

        alignment = _ass_alignment(x_raw, y_raw)
        margin_l = abs(x_raw) if x_raw > 0 else 0
        margin_r = abs(x_raw) if x_raw < 0 else 0
        margin_v = abs(y_raw) if y_raw != 0 else 0

        start_ass = _pts_to_ass_time(start_pts)
        end_ass = _pts_to_ass_time(end_pts)
        text_escaped = text.replace("\\", "\\\\").replace("\n", "\\N")
        tag = (f"{{\\an{alignment}\\fs{fs}\\c{primary}\\bord{border_width}}}")
        ass += (f"Dialogue: {layer},{start_ass},{end_ass},Default,,"
                f"{margin_l:04d},{margin_r:04d},{margin_v:04d},,"
                f"{tag}{text_escaped}\n")
        layer += 1

    return ass


def generate_srt(groups, timeline):
    """Generate a plain SRT subtitle file (no styling).
    All elements are joined into a single subtitle line since SRT
    has no positioning support."""
    total_end = timeline[-1]["pts"] + 0.1

    def find_group(t):
        for g in groups:
            if g["start"] <= t < g["end"]:
                return g
        return groups[-1]

    # Build per‑second events, combining all elements into one line
    lines = []
    t = 0.0
    seq = 1
    while t < total_end:
        sub_end = min(t + 1.0, total_end)
        group = find_group(t + 0.001)
        sei = group["sei"]
        anchor_pts = group.get("anchor_pts", group["start"])

        parts = []
        for elem in sei.get("elements", []):
            elem_type = elem.get("t", "")
            text = elem.get("text", "")
            if elem_type in INTERPOLATED_TYPES:
                try:
                    base_dt = _parse_datetime(text)
                    offset = t - anchor_pts
                    new_dt = base_dt + timedelta(seconds=offset)
                    text = new_dt.strftime("%Y-%m-%d %H:%M:%S")
                except ValueError:
                    pass
            parts.append(text)

        # SRT timestamp format: HH:MM:SS,mmm
        def _to_srt(sec):
            h = int(sec // 3600)
            m = int((sec % 3600) // 60)
            s = int(sec % 60)
            ms = int((sec - int(sec)) * 1000)
            return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

        lines.append(f"{seq}")
        lines.append(f"{_to_srt(t)} --> {_to_srt(sub_end)}")
        lines.append(" | ".join(parts))
        lines.append("")
        t = sub_end
        seq += 1

    return "\n".join(lines) + "\n"


# ──────────────────────────────────────────────────────────────────────
#  FFmpeg command builder
# ──────────────────────────────────────────────────────────────────────

def get_ffmpeg_transpose(rotation: int) -> str:
    if rotation == 0:
        return ""
    elif rotation == 90:
        return "transpose=1,"
    elif rotation == 180:
        return "transpose=1,transpose=1,"
    elif rotation == 270:
        return "transpose=2,"
    return ""


# ──────────────────────────────────────────────────────────────────────
#  Main
# ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Burn Thingino SEI metadata as OSD onto recorded MP4 files."
    )
    parser.add_argument("input", help="Input MP4 file or directory")
    parser.add_argument("output", nargs="?", default=None,
                        help="Output MP4 file (default: INPUT_overlay.mp4)")
    parser.add_argument("--font", default="DejaVu Sans",
                        help="Font name for ASS subtitles (default: DejaVu Sans)")
    parser.add_argument("--codec", default="libx264",
                        help="Output video codec (default: libx264)")
    parser.add_argument("--crf", type=int, default=23,
                        help="CRF quality (default: 23)")
    parser.add_argument("--preset", default="medium",
                        help="x264 preset (default: medium)")
    parser.add_argument("--no-rotate", action="store_true",
                        help="Do NOT pre‑rotate video; burn OSD in raw stream coords")
    parser.add_argument("--border-width", type=int, default=2,
                        help="Width of the text outline/stroke in pixels (default: 2)")
    parser.add_argument("--only-extract", action="store_true",
                        help="Extract SEI timeline JSON to stdout and exit")
    parser.add_argument("--extract-ass", action="store_true",
                        help="Write a standalone .ass subtitle file (no encode)")
    parser.add_argument("--extract-srt", action="store_true",
                        help="Write a standalone .srt subtitle file (plain text, no encode)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print ffmpeg command without running")
    parser.add_argument("--keep-ass", action="store_true",
                        help="Keep the generated .ass file alongside the output")
    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"Error: input file not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    if input_path.is_dir():
        mp4_files = sorted(input_path.glob("*.mp4"))
        mp4_files = [f for f in mp4_files if "_overlay" not in f.stem]
        if not mp4_files:
            print(f"No MP4 files found in {args.input}", file=sys.stderr)
            sys.exit(0)
        print(f"Batch processing {len(mp4_files)} file(s) ...", file=sys.stderr)
        for mp4 in mp4_files:
            out = mp4.with_name(f"{mp4.stem}_overlay.mp4")
            process_one(str(mp4), str(out), args)
        return

    if not args.output and not (args.extract_ass or args.extract_srt):
        stem = input_path.stem
        args.output = str(input_path.with_name(f"{stem}_overlay.mp4"))
    process_one(str(input_path), args.output, args)


def process_one(input_file: str, output_file: str, args):
    print(f"Extracting SEI metadata from {input_file} ...", file=sys.stderr)
    timeline = extract_sei_timeline(input_file)

    if not timeline:
        print("No Thingino SEI metadata found in this file.", file=sys.stderr)
        subprocess.run(["cp", input_file, output_file], check=True)
        print(f"Copied (no metadata) → {output_file}", file=sys.stderr)
        return

    print(f"Found {len(timeline)} frames with SEI metadata.", file=sys.stderr)

    groups = group_timeline(timeline)

    if args.extract_ass or args.extract_srt:
        first_sei = timeline[0]["sei"]
        rotation = first_sei.get("rotation", 0)
        sw = first_sei.get("sw", 1920)
        sh = first_sei.get("sh", 1080)
        if args.no_rotate:
            rotation = 0
        # ── Write standalone subtitle file, no encode ────────────
        if args.extract_srt:
            srt_content = generate_srt(groups, timeline)
            srt_path = Path(args.output) if args.output else Path(input_file).with_suffix(".srt")
            srt_path.write_text(srt_content)
            print(f"SRT written → {srt_path}", file=sys.stderr)
            return
        else:
            # Use black outline as default (new SEI doesn't carry colors)
            stroke_color = "&HCC000000"
            ass_content = generate_ass(groups, timeline, args.font, args.border_width,
                                        stroke_color, rotation, sw, sh)
            ass_path = Path(args.output) if args.output else Path(input_file).with_suffix(".ass")
            ass_path.write_text(ass_content)
            print(f"ASS written → {ass_path}", file=sys.stderr)
            return

    if args.only_extract:
        json.dump(groups, sys.stdout, indent=2)
        return

    first_sei = timeline[0]["sei"]
    rotation = first_sei.get("rotation", 0)
    sw = first_sei.get("sw", 1920)
    sh = first_sei.get("sh", 1080)
    if args.no_rotate:
        rotation = 0
    print(f"Stream rotation: {rotation}°", file=sys.stderr)

    # ── Generate ASS subtitle file ─────────────────────────────────
    stroke_color = "&HCC000000"
    ass_content = generate_ass(groups, timeline, args.font, args.border_width,
                                stroke_color, rotation, sw, sh)

    ass_path = Path(output_file).with_suffix(".ass")
    ass_path.write_text(ass_content)
    print(f"Generated subtitle file: {ass_path}", file=sys.stderr)

    # ── Build ffmpeg command ───────────────────────────────────────
    transpose = get_ffmpeg_transpose(rotation)
    # Use subtitles filter; escape the path for ffmpeg
    escaped_ass = str(ass_path).replace("\\", "\\\\").replace(":", "\\:")
    if transpose:
        vf = f"{transpose}subtitles='{escaped_ass}'"
    else:
        vf = f"subtitles='{escaped_ass}'"

    cmd = [
        "ffmpeg", "-y",
        "-i", input_file,
        "-vf", vf,
        "-c:v", args.codec,
        "-preset", args.preset,
        "-crf", str(args.crf),
        "-c:a", "copy",
        "-movflags", "+faststart",
        "-map_metadata", "0",
    ]
    if rotation != 0:
        cmd.extend(["-metadata:s:v:0", "rotate=0"])
    cmd.append(output_file)

    print(" ".join(cmd), file=sys.stderr)

    if args.dry_run:
        print("Dry‑run: would execute the above command.", file=sys.stderr)
        return

    print(f"Encoding → {output_file} ...", file=sys.stderr)
    subprocess.run(cmd, check=True)
    print(f"Done: {output_file}", file=sys.stderr)

    if not args.keep_ass:
        ass_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
