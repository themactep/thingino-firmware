#!/usr/bin/env bash
# Refresh the static CA bundle shipped in the rootfs overlay from the
# Mozilla root store extract maintained by the curl project.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="$REPO_ROOT/overlay/etc/ssl/certs/ca-certificates.crt"
URL="https://curl.se/ca/cacert.pem"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

curl -fsSL "$URL" -o "$TMP"

# Check
openssl crl2pkcs7 -nocrl -certfile "$TMP" 2>/dev/null | openssl pkcs7 -print_certs -noout >/dev/null

install -m 0644 "$TMP" "$DEST"
echo "Updated $DEST."
