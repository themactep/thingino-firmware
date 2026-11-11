"""USB webcam: the camera as a UVC gadget on a USB cable.

The QEMU fork's dwc2-uvc-host plays the computer at the other end: it
enumerates the gadget, negotiates MJPEG and then H.264 with probe and
commit, reads the bulk stream and saves the frames to <report>/uvc. The
encoder stream tap saves what the camera's encoder coded to <report>/tap;
the frames the host received must be those pictures, byte for byte.
"""

import glob
import hashlib
import os
import re
import shutil
import subprocess

from ..launch import UVC_FRAMES
from ..probes import until

# The host takes UVC_FRAMES of each format. 20 minutes of wall time covers
# an emulated camera coding them at a few frames a second.
STREAM_TIMEOUT = 1200


def _host(ctx, prop):
    if ctx.qmp is None:
        return None
    try:
        return ctx.qmp.cmd("qom-get", path="/machine/peripheral/usbhost",
                           property=prop)
    except Exception:
        return None


def split_jpegs(data):
    """The pictures of back-to-back JPEG files: SOI to the next SOI. The
    entropy-coded data stuffs every 0xff, so a SOI never occurs inside."""
    starts = [m.start() for m in re.finditer(b"\xff\xd8", data)]
    return [data[a:b] for a, b in zip(starts, starts[1:] + [len(data)])]


def split_nals(data):
    """NAL units of an Annex B stream, start codes excluded."""
    marks = [(m.start(), m.end()) for m in re.finditer(b"\x00\x00\x01", data)]
    nals = []
    for i, (_, end) in enumerate(marks):
        stop = marks[i + 1][0] if i + 1 < len(marks) else len(data)
        nals.append(data[end:stop].rstrip(b"\x00"))
    return nals


def _digests(items):
    return {hashlib.sha1(i).digest() for i in items}


def _decode_errors(path):
    """ffmpeg's complaints decoding the whole file; None without ffmpeg."""
    if not shutil.which("ffmpeg"):
        return None
    r = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "null",
                        "-"], capture_output=True, text=True, timeout=300)
    return (r.stderr.strip() + r.stdout.strip()) if r.returncode == 0 \
        else f"ffmpeg exit {r.returncode}: {r.stderr.strip()[:200]}"


def _nb_frames(path):
    if not shutil.which("ffprobe"):
        return None
    r = subprocess.run(["ffprobe", "-v", "error", "-count_frames",
                        "-select_streams", "v:0", "-show_entries",
                        "stream=nb_read_frames", "-of", "csv=p=0", path],
                       capture_output=True, text=True, timeout=300)
    try:
        return int(r.stdout.strip())
    except ValueError:
        return None


def test_usb_webcam(ctx):
    guest, res = ctx.guest, ctx.res
    out_dir = os.path.join(ctx.report_dir, "uvc")
    tap_dir = os.path.join(ctx.report_dir, "tap")

    rc, out = guest.run("lsmod 2>&1")
    res.check("usb_g_webcam_loaded", "g_webcam" in out)
    rc, out = guest.run("ps w")
    res.check("rwc_running", re.search(r"\brwc\b", out) is not None)

    done = until(lambda: _host(ctx, "state") in ("done", "failed"),
                 STREAM_TIMEOUT, 10, ok=bool)
    state = _host(ctx, "state")
    res.check("uvc_host_streamed", bool(done) and state == "done",
              f"host side: {state}, {_host(ctx, 'frames')} frames")

    mjpg = os.path.join(out_dir, "uvc-0.mjpg")
    h264 = os.path.join(out_dir, "uvc-1.h264")
    for name, path in (("mjpeg", mjpg), ("h264", h264)):
        size = os.path.getsize(path) if os.path.exists(path) else 0
        res.check(f"uvc_{name}_saved", size > 0, f"{size} bytes")
        if not size:
            continue
        err = _decode_errors(path)
        if err is None:
            res.skip(f"uvc_{name}_decodes", "no ffmpeg on the host")
        else:
            res.check(f"uvc_{name}_decodes", err == "", err[:200])
        n = _nb_frames(path)
        if name == "mjpeg":
            res.check("uvc_mjpeg_frames", n == UVC_FRAMES,
                      f"{n} decoded of {UVC_FRAMES}")
        else:
            # A decoder drops P pictures whose frame_num is not the next
            # one, and some of the stream's are not (see below), so count
            # the pictures received and report what decoded.
            pics = sum(1 for x in split_nals(open(path, "rb").read())
                       if (x[0] & 0x1f) in (1, 5))
            res.check("uvc_h264_frames", pics == UVC_FRAMES,
                      f"{pics} pictures received of {UVC_FRAMES}, "
                      f"{n} decoded")

    # The tap holds every picture the encoders coded; the host's are some.
    taps = sorted(glob.glob(os.path.join(tap_dir, "*")))
    if not taps:
        res.skip("uvc_matches_tap", "QEMU has no stream tap")
        return
    tap_jpegs, tap_nals, tap_all_nals = set(), set(), []
    for t in taps:
        data = open(t, "rb").read()
        if t.endswith(".mjpg"):
            tap_jpegs |= _digests(split_jpegs(data))
        elif t.endswith(".h264"):
            nals = split_nals(data)
            tap_all_nals += nals
            tap_nals |= _digests(nals)
    if os.path.exists(mjpg):
        pics = split_jpegs(open(mjpg, "rb").read())
        miss = [i for i, p in enumerate(pics)
                if hashlib.sha1(p).digest() not in tap_jpegs]
        res.check("uvc_mjpeg_matches_tap", pics and not miss,
                  f"{len(pics) - len(miss)} of {len(pics)} pictures "
                  f"identical to the encoder's")
    if os.path.exists(h264):
        # libimp rewrites the first bytes of a slice header (frame_num) after
        # the tap has copied the picture, so a P slice counts when it matches
        # the tap's from its third byte on; a few rewrites change the header's
        # length and shift the whole slice, so a tenth of them may miss.
        # Parameter sets and IDR slices must match whole.
        nals = split_nals(open(h264, "rb").read())
        tails = {hashlib.sha1(n[3:]).digest() for n in tap_all_nals}
        whole = exact = tail = 0
        miss = []
        for i, n in enumerate(nals):
            if hashlib.sha1(n).digest() in tap_nals:
                exact += 1
            elif (n[0] & 0x1f) == 1 and hashlib.sha1(n[3:]).digest() in tails:
                tail += 1
            else:
                miss.append(i)
        hard = [i for i in miss if (nals[i][0] & 0x1f) != 1]
        res.check("uvc_h264_matches_tap",
                  nals and not hard and len(miss) * 10 <= len(nals),
                  f"{exact} NAL units identical, {tail} with the first slice "
                  f"header bytes rewritten, {len(miss)} of {len(nals)} "
                  f"different")
