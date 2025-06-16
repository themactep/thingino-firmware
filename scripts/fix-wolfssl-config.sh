#!/bin/bash

# Script to fix the build configuration to use wolfSSL instead of mbedTLS

set -e

echo "Fixing build configuration to use wolfSSL..."

# Find the output directory
OUTPUT_DIR=""
for dir in /home/me/output/*/; do
    if [ -d "$dir" ] && [ -f "$dir/.config" ]; then
        OUTPUT_DIR="$dir"
        break
    fi
done

if [ -z "$OUTPUT_DIR" ]; then
    echo "Error: Could not find output directory with .config file"
    exit 1
fi

CONFIG_FILE="$OUTPUT_DIR/.config"
echo "Using config file: $CONFIG_FILE"

# Backup the original config
cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"

# Remove mbedTLS options
echo "Removing mbedTLS configuration options..."
sed -i '/^BR2_PACKAGE_THINGINO_UHTTPD_TLS_MBEDTLS/d' "$CONFIG_FILE"
sed -i '/^BR2_PACKAGE_THINGINO_USTREAM_SSL_MBEDTLS/d' "$CONFIG_FILE"
sed -i '/^BR2_PACKAGE_THINGINO_MBEDTLS/d' "$CONFIG_FILE"
sed -i '/^BR2_PACKAGE_MBEDTLS/d' "$CONFIG_FILE"

# Add wolfSSL options
echo "Adding wolfSSL configuration options..."
cat >> "$CONFIG_FILE" << 'EOF'

# wolfSSL SSL backend configuration (simplified - no more choices)
BR2_PACKAGE_THINGINO_USTREAM_SSL_WOLFSSL=y
BR2_PACKAGE_THINGINO_WOLFSSL=y
BR2_PACKAGE_THINGINO_WOLFSSL_ALL=y
BR2_PACKAGE_THINGINO_WOLFSSL_EXAMPLES=y
BR2_PACKAGE_THINGINO_WOLFSSL_KEYGEN=y
BR2_PACKAGE_THINGINO_WOLFSSL_CERTGEN=y
BR2_PACKAGE_THINGINO_WOLFSSL_ECC=y
BR2_PACKAGE_THINGINO_WOLFSSL_ECCSHAMIR=y
BR2_PACKAGE_THINGINO_WOLFSSL_CERTEXT=y
BR2_PACKAGE_THINGINO_WOLFSSL_ECC=y
BR2_PACKAGE_THINGINO_WOLFSSL_ECCSHAMIR=y
BR2_PACKAGE_THINGINO_WOLFSSL_ASN=y
BR2_PACKAGE_THINGINO_WOLFSSL_TLS13=y
BR2_PACKAGE_THINGINO_WOLFSSL_TLSV12=y
BR2_PACKAGE_THINGINO_WOLFSSL_SNI=y
BR2_PACKAGE_THINGINO_WOLFSSL_ALPN=y
BR2_PACKAGE_THINGINO_WOLFSSL_WOLFCLU=y
BR2_PACKAGE_THINGINO_WOLFSSL_OPENSSLEXTRA=y
BR2_PACKAGE_THINGINO_WOLFSSL_OPENSSLALL=y
BR2_PACKAGE_CA_CERTIFICATES=y

# SSH support (was missing due to mbedTLS dependency)
BR2_PACKAGE_DROPBEAR=y
BR2_PACKAGE_DROPBEAR_SMALL=y
BR2_PACKAGE_DROPBEAR_DISABLE_REVERSEDNS=y
EOF

echo "Configuration updated successfully!"
echo ""
echo "Next steps:"
echo "1. Run: make olddefconfig"
echo "2. Clean SSL packages: make thingino-ustream-ssl-dirclean thingino-uhttpd-dirclean"
echo "3. Rebuild: make thingino-wolfssl thingino-ustream-ssl thingino-uhttpd"
echo ""
echo "Or do a full clean build: make clean && make"
