#!/bin/sh
# Generate self-signed TLS certificates for timps HTTPS/RTSPS.
# Uses openssl if available, falls back to mbedtls-certgen.
#
# Usage: generate-timps-tls-certs.sh [cert_path] [key_path]
# Defaults match timps.conf (http.tls_cert / http.tls_key).

CERT="${1:-/etc/ssl/certs/httpd.crt}"
KEY="${2:-/etc/ssl/private/httpd.key}"

mkdir -p "$(dirname "$CERT")" "$(dirname "$KEY")"

if [ -s "$CERT" ] && [ -s "$KEY" ]; then
	echo "TLS certificates already exist, skipping generation."
	exit 0
fi

if command -v openssl >/dev/null 2>&1; then
	echo "Generating self-signed certificate with openssl..."
	openssl req -x509 -newkey rsa:2048 \
		-keyout "$KEY" \
		-out "$CERT" \
		-days 3650 -nodes \
		-subj "/C=US/ST=State/L=City/O=Thingino/CN=camera.local" \
		2>/dev/null
	ret=$?
	chmod 600 "$KEY" 2>/dev/null
	chmod 644 "$CERT" 2>/dev/null
elif command -v mbedtls-certgen >/dev/null 2>&1; then
	echo "Generating self-signed certificate with mbedtls-certgen..."
	# mbedtls-certgen's flags, not openssl's: -h hostname -c cert -k key
	# (no positional "server" arg, no --cn/--days long options).
	mbedtls-certgen -h camera.local -c "$CERT" -k "$KEY" -d 3650
	ret=$?
	chmod 600 "$KEY" 2>/dev/null
else
	echo "WARNING: No TLS tool found, skipping certificate generation."
	exit 1
fi

# Neither branch above may have written both files (wrong flags, disk full,
# etc.) - checking $ret alone isn't enough since a tool can exit 0 without
# producing a usable pair, so also verify the outputs are actually there.
if [ "$ret" -ne 0 ] || [ ! -s "$CERT" ] || [ ! -s "$KEY" ]; then
	echo "ERROR: certificate generation failed (exit $ret)"
	exit 1
fi

echo "TLS certificates generated:"
echo "  Certificate: $CERT"
echo "  Private Key:  $KEY"
