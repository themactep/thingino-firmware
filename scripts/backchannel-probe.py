#!/usr/bin/env python3
"""
Probe a Thingino camera for backchannel (talkback) support.

Usage:
    backchannel-probe.py <ip-or-url>

Examples:
    backchannel-probe.py 192.168.88.36
    backchannel-probe.py rtsp://thingino:thingino@192.168.88.36/backchannel
"""

import re
import sys
from urllib.parse import urlparse

from rtsp_probe import describe


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: backchannel-probe.py <ip>\n"
              "       backchannel-probe.py rtsp://user:pass@host/backchannel",
              file=sys.stderr)
        return 2

    arg = sys.argv[1]

    if re.match(r'^\d+\.\d+\.\d+\.\d+$', arg):
        host = arg
        port = 554
        path = "/backchannel"
        user = "thingino"
        password = "thingino"
    elif arg.startswith("rtsp://"):
        parsed = urlparse(arg)
        if not parsed.hostname:
            print("Invalid RTSP URL", file=sys.stderr)
            return 2
        host = parsed.hostname
        port = parsed.port or 554
        path = parsed.path or "/backchannel"
        user = parsed.username or "thingino"
        password = parsed.password or "thingino"
    else:
        print("Expected IP address or rtsp:// URL", file=sys.stderr)
        return 2

    response = describe(host, port, path, user, password, "backchannel-probe/1.0")

    # ── Parse SDP for backchannel info ────────────────────────────────
    lines = response.splitlines()
    status_line = lines[0] if lines else ""
    sdp_start = next((i for i, l in enumerate(lines) if l.startswith("v=")), -1)
    sdp_lines = lines[sdp_start:] if sdp_start >= 0 else []

    # Extract backchannel-relevant media sections
    backchannel_sections = []
    current_section = None  # (media_line, control, direction, rtpmaps)
    for line in sdp_lines:
        if line.startswith("m="):
            if current_section:
                backchannel_sections.append(current_section)
            current_section = [line, "", "", []]
        elif line.startswith("a=control:") and current_section:
            current_section[1] = line
        elif line.startswith("a=recvonly") and current_section:
            current_section[2] = "recvonly"
        elif line.startswith("a=sendonly") and current_section:
            current_section[2] = "sendonly"
        elif line.startswith("a=sendrecv") and current_section:
            current_section[2] = "sendrecv"
        elif line.startswith("a=rtpmap:") and current_section:
            current_section[3].append(line)
    if current_section:
        backchannel_sections.append(current_section)

    # ── Output ────────────────────────────────────────────────────────
    print(f"Host: {host}:{port}")
    print(f"Status: {status_line}")

    if not backchannel_sections:
        print("\nNo backchannel tracks found.")
        return 1

    for i, (media, control, direction, rtpmaps) in enumerate(backchannel_sections):
        tag = f"Backchannel #{i+1}" if direction else f"Track #{i+1}"
        if direction == "recvonly":
            tag += " (RECV — server receives audio)"
        elif direction == "sendonly":
            tag += " (SEND — server sends audio)"
        elif direction == "sendrecv":
            tag += " (SENDRECV — bidirectional)"
        else:
            tag += " (no direction attribute)"

        print(f"\n{tag}:")
        print(f"  {media}")
        if control:
            print(f"  {control}")
        for rtp in rtpmaps:
            print(f"  {rtp}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
