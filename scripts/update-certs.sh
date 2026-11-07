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

# Refuse empty, partial or non-PEM downloads.
certs=$(grep -c -- '^-----BEGIN CERTIFICATE-----' "$TMP" || true)
if [ "$certs" -lt 50 ] || [ "$(tail -n 1 "$TMP")" != "-----END CERTIFICATE-----" ]; then
	echo "Refusing to install $TMP: not a CA bundle." >&2
	exit 1
fi

install -m 0644 "$TMP" "$DEST"
echo "Updated $DEST."
