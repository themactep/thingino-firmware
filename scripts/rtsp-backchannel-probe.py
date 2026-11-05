#!/usr/bin/env python3
"""
Probe an RTSP endpoint for ONVIF backchannel-only media tracks.

This script sends RTSP DESCRIBE with:
    Require: www.onvif.org/ver20/backchannel

Some cameras only expose talkback/backchannel media sections when that ONVIF
Require header is present. A normal ffprobe/RTSP DESCRIBE may show only the
playback streams, while this script reveals the extra SDP media sections.

Usage:
    rtsp-backchannel-probe.py rtsp://user:pass@host[:port]/path

Example:
    rtsp-backchannel-probe.py rtsp://thingino:thingino@192.168.88.106/ch0

How to read the output:
    - Extra 'm=audio' sections that only appear here are hidden ONVIF tracks.
    - 'a=sendonly' means the server advertises a stream in one direction.
    - 'a=recvonly' is the classic sign that the server is willing to receive
      media from the client, which is the usual talkback/backchannel indicator.
    - 'a=control:trackN' identifies the RTSP control track for SETUP.
"""

import sys
from urllib.parse import urlparse

from rtsp_probe import describe as describe_endpoint


def usage() -> None:
    print(
        "Usage: rtsp-backchannel-probe.py rtsp://user:pass@host[:port]/path",
        file=sys.stderr,
    )


def describe(url: str) -> str:
    parsed = urlparse(url)
    if parsed.scheme != "rtsp" or not parsed.hostname or parsed.username is None:
        usage()
        raise SystemExit(2)

    user = parsed.username
    password = parsed.password or ""
    host = parsed.hostname
    port = parsed.port or 554
    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"

    return describe_endpoint(
        host, port, path, user, password, "rtsp-backchannel-probe/1.0"
    )


def main() -> int:
    if len(sys.argv) != 2:
        usage()
        return 2

    response = describe(sys.argv[1])
    for line in response.splitlines():
        if line.startswith(
            ("RTSP/", "Content-", "m=", "a=control:", "a=recvonly", "a=sendonly", "a=sendrecv")
        ):
            print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
