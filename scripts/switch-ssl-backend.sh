#!/bin/bash

# Script to switch SSL backend between mbedTLS and wolfSSL for testing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

usage() {
    echo "Usage: $0 [mbedtls|wolfssl]"
    echo ""
    echo "Switch SSL backend for uhttpd testing:"
    echo "  mbedtls  - Use mbedTLS 2.28.10 (current default)"
    echo "  wolfssl  - Use wolfSSL (for testing SSL compatibility)"
    echo ""
    echo "This script modifies the buildroot configuration to test"
    echo "different SSL backends with uhttpd."
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

BACKEND="$1"

case "$BACKEND" in
    mbedtls)
        echo "Switching to mbedTLS backend..."
        CONFIG_CHANGES="
# Enable mbedTLS backend
BR2_PACKAGE_THINGINO_UHTTPD_TLS_MBEDTLS=y
# BR2_PACKAGE_THINGINO_UHTTPD_TLS_WOLFSSL is not set
BR2_PACKAGE_THINGINO_USTREAM_SSL_MBEDTLS=y
# BR2_PACKAGE_THINGINO_USTREAM_SSL_WOLFSSL is not set
BR2_PACKAGE_THINGINO_MBEDTLS=y
BR2_PACKAGE_THINGINO_MBEDTLS_PROGRAMS=y
"
        ;;
    wolfssl)
        echo "Switching to wolfSSL backend..."
        CONFIG_CHANGES="
# Enable wolfSSL backend
# BR2_PACKAGE_THINGINO_UHTTPD_TLS_MBEDTLS is not set
BR2_PACKAGE_THINGINO_UHTTPD_TLS_WOLFSSL=y
# BR2_PACKAGE_THINGINO_USTREAM_SSL_MBEDTLS is not set
BR2_PACKAGE_THINGINO_USTREAM_SSL_WOLFSSL=y
BR2_PACKAGE_THINGINO_WOLFSSL=y
BR2_PACKAGE_THINGINO_WOLFSSL_ALL=y
BR2_PACKAGE_THINGINO_WOLFSSL_TLS13=y
BR2_PACKAGE_THINGINO_WOLFSSL_TLSV12=y
BR2_PACKAGE_THINGINO_WOLFSSL_SNI=y
BR2_PACKAGE_THINGINO_WOLFSSL_ALPN=y
BR2_PACKAGE_THINGINO_WOLFSSL_EXAMPLES=y
"
        ;;
    *)
        echo "Error: Unknown backend '$BACKEND'"
        usage
        ;;
esac

# Find the defconfig file
DEFCONFIG_FILE=""
for config in configs/*_defconfig; do
    if [ -f "$config" ]; then
        DEFCONFIG_FILE="$config"
        break
    fi
done

if [ -z "$DEFCONFIG_FILE" ]; then
    echo "Error: No defconfig file found in configs/"
    exit 1
fi

echo "Using defconfig: $DEFCONFIG_FILE"

# Create backup
BACKUP_FILE="${DEFCONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$DEFCONFIG_FILE" "$BACKUP_FILE"
echo "Created backup: $BACKUP_FILE"

# Apply changes
echo "Applying SSL backend configuration..."

# Remove existing SSL backend configurations
sed -i '/^BR2_PACKAGE_THINGINO_UHTTPD_TLS_MBEDTLS/d' "$DEFCONFIG_FILE"
sed -i '/^BR2_PACKAGE_THINGINO_UHTTPD_TLS_WOLFSSL/d' "$DEFCONFIG_FILE"
sed -i '/^BR2_PACKAGE_THINGINO_USTREAM_SSL_MBEDTLS/d' "$DEFCONFIG_FILE"
sed -i '/^BR2_PACKAGE_THINGINO_USTREAM_SSL_WOLFSSL/d' "$DEFCONFIG_FILE"
sed -i '/^BR2_PACKAGE_THINGINO_MBEDTLS/d' "$DEFCONFIG_FILE"
sed -i '/^BR2_PACKAGE_THINGINO_WOLFSSL/d' "$DEFCONFIG_FILE"

# Add new configuration
echo "$CONFIG_CHANGES" >> "$DEFCONFIG_FILE"

echo ""
echo "SSL backend switched to: $BACKEND"
echo ""
echo "Next steps:"
echo "1. Clean existing SSL packages:"
echo "   make thingino-uhttpd-dirclean thingino-ustream-ssl-dirclean"
if [ "$BACKEND" = "mbedtls" ]; then
    echo "   make thingino-mbedtls-dirclean"
else
    echo "   make thingino-wolfssl-dirclean"
fi
echo ""
echo "2. Rebuild with new SSL backend:"
echo "   make thingino-uhttpd"
echo ""
echo "3. Or do a full rebuild:"
echo "   make"
echo ""
echo "To restore original configuration:"
echo "   cp $BACKUP_FILE $DEFCONFIG_FILE"
