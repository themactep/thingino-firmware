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
	chmod 600 "$KEY"
	chmod 644 "$CERT"
elif command -v mbedtls-certgen >/dev/null 2>&1; then
	echo "Generating self-signed certificate with mbedtls-certgen..."
	mbedtls-certgen server "$CERT" "$KEY" \
		--cn camera.local --days 3650
	chmod 600 "$KEY" 2>/dev/null
else
	echo "WARNING: No TLS tool found, skipping certificate generation."
	exit 1
fi

echo "TLS certificates generated:"
echo "  Certificate: $CERT"
echo "  Private Key:  $KEY"
