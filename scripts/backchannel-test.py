#!/usr/bin/env python3
"""Test Thingino backchannel (talkback) — send a tone to the camera speaker."""

import socket
import struct
import time
import math
import sys
import re

CAMERA = sys.argv[1] if len(sys.argv) > 1 else "192.168.88.36"
PORT = 554
USER = "thingino"
PASS = "thingino"

FREQ = 320          # Hz
DURATION = 1        # seconds
SAMPLE_RATE = 8000  # PCMU is always 8kHz

# ── helpers ──────────────────────────────────────────────────────────────────

def auth_header(user, passwd):
    import base64
    creds = base64.b64encode(f"{user}:{passwd}".encode()).decode()
    return f"Authorization: Basic {creds}\r\n"

def read_response(sock):
    """Read RTSP response until double CRLF (headers)."""
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    text = data.decode(errors="replace")
    # Parse status line
    status = int(text.split()[1]) if len(text.split()) > 1 else -1
    # Parse headers
    headers = {}
    for line in text.split("\r\n"):
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()
    return status, headers, text

def generate_pcmu(freq, duration, sample_rate):
    """Generate μ-law encoded sine wave samples."""
    samples = []
    for i in range(int(duration * sample_rate)):
        t = i / sample_rate
        # 16-bit linear PCM sine
        linear = int(16000 * math.sin(2 * math.pi * freq * t))
        # Clamp to 16-bit
        linear = max(-32768, min(32767, linear))
        # Encode to μ-law (simplified)
        mulaw = linear_to_mulaw(linear)
        samples.append(mulaw)
    return bytes(samples)

def linear_to_mulaw(sample):
    """Convert 16-bit linear PCM to 8-bit μ-law."""
    # μ-law encoding table
    mask = 0x4000 if sample < 0 else 0
    sample = abs(sample)
    if sample > 32635:
        sample = 32635
    sample += 132  # bias
    # Find segment
    segment = 7
    for i in range(7):
        if sample <= (0x3F << (i + 1)):
            segment = 6 - i
            break
    # Quantize
    quant = (sample >> (segment + 3)) & 0x0F
    # Build μ-law byte
    mulaw = (~(mask | (segment << 4) | quant)) & 0xFF
    return mulaw

def send_rtp_packets(sock, host, port, payload, pt=0, seq=0, ssrc=0x12345678):
    """Send PCMU payload as RTP packets (max 172 bytes payload per packet)."""
    MAX_PAYLOAD = 172  # stay under Ethernet MTU
    offset = 0
    timestamp = 0
    while offset < len(payload):
        chunk = payload[offset:offset + MAX_PAYLOAD]
        offset += len(chunk)

        # RTP header (12 bytes)
        hdr = struct.pack("!BBHII",
            0x80,                    # V=2, P=0, X=0, CC=0
            (0x80 if offset >= len(payload) else 0x00) | (pt & 0x7F),  # M + PT
            seq,                      # sequence number
            timestamp,                # timestamp (samples)
            ssrc)                     # SSRC
        seq = (seq + 1) & 0xFFFF
        timestamp += len(chunk)       # PCMU: 1 byte = 1 sample

        sock.sendto(hdr + chunk, (host, port))
        time.sleep(len(chunk) / SAMPLE_RATE)  # real-time pacing

# ── main ─────────────────────────────────────────────────────────────────────

def main():
    print(f"Connecting to {CAMERA}:{PORT}...")
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect((CAMERA, PORT))

    auth = auth_header(USER, PASS)

    # 1. ANNOUNCE
    sdp = (
        "v=0\r\n"
        "o=- 0 0 IN IP4 0.0.0.0\r\n"
        "s=backchannel test\r\n"
        "t=0 0\r\n"
        "m=audio 0 RTP/AVP 0\r\n"
        "a=control:track0\r\n"
        "a=rtpmap:0 PCMU/8000\r\n"
    )
    req = (
        f"ANNOUNCE rtsp://{CAMERA}/backchannel RTSP/1.0\r\n"
        f"CSeq: 1\r\n"
        f"Content-Type: application/sdp\r\n"
        f"Content-Length: {len(sdp)}\r\n"
        f"{auth}"
        f"\r\n"
        f"{sdp}"
    )
    sock.sendall(req.encode())
    status, hdrs, text = read_response(sock)
    print(f"ANNOUNCE: {status}")
    if status != 200:
        print(text)
        sys.exit(1)
    session_id = hdrs.get("session", "")
    print(f"  Session: {session_id}")

    # 2. SETUP
    req = (
        f"SETUP rtsp://{CAMERA}/backchannel/track0 RTSP/1.0\r\n"
        f"CSeq: 2\r\n"
        f"Session: {session_id}\r\n"
        f"Transport: RTP/AVP;unicast;client_port=5004-5005\r\n"
        f"{auth}"
        f"\r\n"
    )
    sock.sendall(req.encode())
    status, hdrs, text = read_response(sock)
    print(f"SETUP: {status}")
    if status != 200:
        print(text)
        sys.exit(1)
    transport = hdrs.get("transport", "")
    m = re.search(r"server_port=(\d+)", transport)
    if not m:
        print(f"Cannot parse server_port from: {transport}")
        sys.exit(1)
    server_port = int(m.group(1))
    print(f"  Server port: {server_port}")

    # 3. RECORD
    req = (
        f"RECORD rtsp://{CAMERA}/backchannel RTSP/1.0\r\n"
        f"CSeq: 3\r\n"
        f"Session: {session_id}\r\n"
        f"{auth}"
        f"\r\n"
    )
    sock.sendall(req.encode())
    status, hdrs, text = read_response(sock)
    print(f"RECORD: {status}")
    if status != 200:
        print(text)
        sys.exit(1)

    print(f"Sending {FREQ}Hz tone for {DURATION}s...")
    pcmu = generate_pcmu(FREQ, DURATION, SAMPLE_RATE)

    udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    # Bind to client_port so server knows our source
    udp_sock.bind(("0.0.0.0", 5004))
    try:
        send_rtp_packets(udp_sock, CAMERA, server_port, pcmu)
    finally:
        udp_sock.close()

    # 4. TEARDOWN
    req = (
        f"TEARDOWN rtsp://{CAMERA}/backchannel RTSP/1.0\r\n"
        f"CSeq: 4\r\n"
        f"Session: {session_id}\r\n"
        f"{auth}"
        f"\r\n"
    )
    sock.sendall(req.encode())
    status, _, _ = read_response(sock)
    print(f"TEARDOWN: {status}")

    sock.close()
    print("Done.")

if __name__ == "__main__":
    main()
