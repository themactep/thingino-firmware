#!/bin/sh
# Generate self-signed TLS certificates for timps HTTPS/RTSPS.
# Uses openssl if available, falls back to mbedtls-certgen.

CERT_DIR=/etc/ssl/certs
KEY_DIR=/etc/ssl/private

mkdir -p "$CERT_DIR" "$KEY_DIR"

if [ -f "$CERT_DIR/httpd.crt" ] && [ -f "$KEY_DIR/httpd.key" ]; then
	echo "TLS certificates already exist, skipping generation."
	exit 0
fi

if command -v openssl >/dev/null 2>&1; then
	echo "Generating self-signed certificate with openssl..."
	openssl req -x509 -newkey rsa:2048 \
		-keyout "$KEY_DIR/httpd.key" \
		-out "$CERT_DIR/httpd.crt" \
		-days 3650 -nodes \
		-subj "/C=US/ST=State/L=City/O=Thingino/CN=camera.local" \
		2>/dev/null
	chmod 600 "$KEY_DIR/httpd.key"
	chmod 644 "$CERT_DIR/httpd.crt"
elif command -v mbedtls-certgen >/dev/null 2>&1; then
	echo "Generating self-signed certificate with mbedtls-certgen..."
	mbedtls-certgen server "$CERT_DIR/httpd.crt" "$KEY_DIR/httpd.key" \
		--cn camera.local --days 3650
else
	echo "WARNING: No TLS tool found, skipping certificate generation."
	exit 1
fi

echo "TLS certificates generated:"
echo "  Certificate: $CERT_DIR/httpd.crt"
echo "  Private Key:  $KEY_DIR/httpd.key"
