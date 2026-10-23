#!/bin/sh

CERT="${1:-/etc/ssl/certs/timps.crt}"
KEY="${2:-/etc/ssl/private/timps.key}"

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
	mbedtls-certgen -h camera.local -c "$CERT" -k "$KEY" -d 3650
	ret=$?
	chmod 600 "$KEY" 2>/dev/null
else
	echo "WARNING: No TLS tool found, skipping certificate generation."
	exit 1
fi

if [ "$ret" -ne 0 ] || [ ! -s "$CERT" ] || [ ! -s "$KEY" ]; then
	echo "ERROR: certificate generation failed (exit $ret)"
	exit 1
fi

echo "TLS certificates generated:"
echo "  Certificate: $CERT"
echo "  Private Key:  $KEY"
