"""Shared RTSP DESCRIBE helpers for the backchannel probe scripts."""

import hashlib
import re
import socket

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


def describe(
    host: str,
    port: int,
    path: str,
    user: str,
    password: str,
    user_agent: str,
) -> str:
    full_url = f"rtsp://{host}:{port}{path}"
    sock = socket.create_connection((host, port), timeout=10)

    request = (
        f"DESCRIBE {full_url} RTSP/1.0\r\n"
        "CSeq: 1\r\n"
        "Accept: application/sdp\r\n"
        f"Require: {REQUIRE_HEADER}\r\n"
        f"User-Agent: {user_agent}\r\n"
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
        f"User-Agent: {user_agent}\r\n"
        f"{auth_header}"
        "\r\n"
    )
    sock.sendall(request.encode())
    second_response = recv_response(sock)
    sock.close()
    return second_response
