#!/usr/bin/env python3
"""
Probe a Thingino camera for backchannel (talkback) support.

Usage:
    backchannel-probe.py <ip-or-url>

Examples:
    backchannel-probe.py 192.168.88.36
    backchannel-probe.py rtsp://thingino:thingino@192.168.88.36/backchannel
"""

import hashlib
import re
import socket
import sys
from urllib.parse import urlparse


REQUIRE_HEADER = "www.onvif.org/ver20/backchannel"


def recv_response(sock: socket.socket) -> str:
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk

    header, _, rest = data.partition(b"\r\n\r\n")
    match = re.search(br"Content-Length:\s*(\d+)", header, re.I)
    if match:
        need = int(match.group(1)) - len(rest)
        while need > 0:
            chunk = sock.recv(4096)
            if not chunk:
                break
            rest += chunk
            need -= len(chunk)

    return (header + b"\r\n\r\n" + rest).decode("utf-8", "replace")


def parse_digest_challenge(response: str) -> dict[str, str] | None:
    match = re.search(r"WWW-Authenticate:\s*Digest\s+([^\r\n]+)", response, re.I)
    if not match:
        return None
    return {
        key.lower(): value
        for key, value in re.findall(r'(\w+)="?([^",]+)"?', match.group(1))
    }


def build_digest_authorization(
    challenge: dict[str, str], user: str, password: str, method: str, uri: str
) -> str:
    realm = challenge["realm"]
    nonce = challenge["nonce"]
    qop = challenge.get("qop")

    ha1 = hashlib.md5(f"{user}:{realm}:{password}".encode()).hexdigest()
    ha2 = hashlib.md5(f"{method}:{uri}".encode()).hexdigest()

    if qop:
        nc = "00000001"
        cnonce = "abcdef1234567890"
        response = hashlib.md5(
            f"{ha1}:{nonce}:{nc}:{cnonce}:{qop}:{ha2}".encode()
        ).hexdigest()
        return (
            "Authorization: Digest "
            f'username="{user}", realm="{realm}", nonce="{nonce}", uri="{uri}", '
            f'response="{response}", qop={qop}, nc={nc}, cnonce="{cnonce}"\r\n'
        )

    response = hashlib.md5(f"{ha1}:{nonce}:{ha2}".encode()).hexdigest()
    return (
        "Authorization: Digest "
        f'username="{user}", realm="{realm}", nonce="{nonce}", uri="{uri}", '
        f'response="{response}"\r\n'
    )


def describe(host: str, port: int, path: str, user: str, password: str) -> str:
    full_url = f"rtsp://{host}:{port}{path}"
    sock = socket.create_connection((host, port), timeout=10)

    request = (
        f"DESCRIBE {full_url} RTSP/1.0\r\n"
        "CSeq: 1\r\n"
        "Accept: application/sdp\r\n"
        f"Require: {REQUIRE_HEADER}\r\n"
        "User-Agent: backchannel-probe/1.0\r\n"
        "\r\n"
    )
    sock.sendall(request.encode())
    first_response = recv_response(sock)

    challenge = parse_digest_challenge(first_response)
    if not challenge:
        sock.close()
        return first_response

    auth_header = build_digest_authorization(
        challenge, user, password, "DESCRIBE", full_url
    )
    request = (
        f"DESCRIBE {full_url} RTSP/1.0\r\n"
        "CSeq: 2\r\n"
        "Accept: application/sdp\r\n"
        f"Require: {REQUIRE_HEADER}\r\n"
        "User-Agent: backchannel-probe/1.0\r\n"
        f"{auth_header}"
        "\r\n"
    )
    sock.sendall(request.encode())
    second_response = recv_response(sock)
    sock.close()
    return second_response


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

    response = describe(host, port, path, user, password)

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
