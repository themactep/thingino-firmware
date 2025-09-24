#!/bin/sh
#
# mbedTLS Certificate Generator for Thingino
#
# This script provides multiple fallback methods for SSL certificate generation:
# 1. Native mbedTLS certificate generator (if available)
# 2. OpenSSL compatibility layer (if available)
# 3. Fallback to HTTP-only mode
#
# Usage: mbedtls-certgen -h hostname -c cert_file -k key_file [-d days] [-s key_size] [-t type]
#

# Default values
DAYS=3650
KEY_SIZE=256
KEY_TYPE="ecdsa"
HOSTNAME=""
CERT_FILE=""
KEY_FILE=""

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--hostname)
            HOSTNAME="$2"
            shift 2
            ;;
        -c|--cert)
            CERT_FILE="$2"
            shift 2
            ;;
        -k|--key)
            KEY_FILE="$2"
            shift 2
            ;;
        -d|--days)
            DAYS="$2"
            shift 2
            ;;
        -s|--key-size)
            KEY_SIZE="$2"
            shift 2
            ;;
        -t|--type)
            KEY_TYPE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 -h hostname -c cert_file -k key_file [-d days] [-s key_size] [-t type]"
            echo "  -h, --hostname   Hostname for certificate CN"
            echo "  -c, --cert       Output certificate file"
            echo "  -k, --key        Output private key file"
            echo "  -d, --days       Certificate validity in days (default: $DAYS)"
            echo "  -s, --key-size   Key size - ECDSA: 256,384,521 RSA: 2048,3072,4096 (default: $KEY_SIZE)"
            echo "  -t, --type       Key type: ecdsa or rsa (default: $KEY_TYPE)"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$HOSTNAME" ] || [ -z "$CERT_FILE" ] || [ -z "$KEY_FILE" ]; then
    echo "ERROR: Missing required arguments"
    echo "Usage: $0 -h hostname -c cert_file -k key_file [-d days] [-s key_size] [-t type]"
    exit 1
fi

# Function to generate certificate using OpenSSL compatibility layer
generate_with_openssl_compat() {
    if command -v openssl >/dev/null 2>&1; then
        echo "Generating certificate using OpenSSL compatibility layer..."
        
        if [ "$KEY_TYPE" = "ecdsa" ]; then
            # Generate ECDSA private key
            case "$KEY_SIZE" in
                256) CURVE="prime256v1" ;;
                384) CURVE="secp384r1" ;;
                521) CURVE="secp521r1" ;;
                *) 
                    echo "Unsupported ECDSA key size: $KEY_SIZE"
                    return 1
                    ;;
            esac
            
            if openssl ecparam -genkey -name "$CURVE" -out "$KEY_FILE" 2>/dev/null; then
                # Generate self-signed certificate
                if openssl req -new -x509 -key "$KEY_FILE" -out "$CERT_FILE" \
                    -days "$DAYS" -subj "/C=US/ST=CA/L=San Francisco/O=Thingino/OU=Camera/CN=$HOSTNAME" \
                    -sha256 2>/dev/null; then
                    echo "ECDSA certificate generated successfully"
                    return 0
                fi
            fi
        else
            # Generate RSA private key
            if openssl genrsa -out "$KEY_FILE" "$KEY_SIZE" 2>/dev/null; then
                # Generate self-signed certificate
                if openssl req -new -x509 -key "$KEY_FILE" -out "$CERT_FILE" \
                    -days "$DAYS" -subj "/C=US/ST=CA/L=San Francisco/O=Thingino/OU=Camera/CN=$HOSTNAME" \
                    -sha256 2>/dev/null; then
                    echo "RSA certificate generated successfully"
                    return 0
                fi
            fi
        fi
    fi
    return 1
}

# Try different methods in order of preference
echo "Generating SSL certificate for hostname: $HOSTNAME"

# Method 1: Native mbedTLS certificate generator (if available)
if [ -x /usr/bin/mbedtls-certgen-native ]; then
    echo "Trying native mbedTLS certificate generator..."
    if /usr/bin/mbedtls-certgen-native -h "$HOSTNAME" -c "$CERT_FILE" -k "$KEY_FILE" -d "$DAYS" -s "$KEY_SIZE" -t "$KEY_TYPE" 2>/dev/null; then
        echo "Certificate generated with native mbedTLS"
        exit 0
    else
        echo "Native mbedTLS certificate generator failed"
    fi
fi

# Method 2: OpenSSL compatibility layer (if available)
if command -v openssl >/dev/null 2>&1; then
    echo "Trying OpenSSL compatibility layer..."
    if generate_with_openssl_compat; then
        exit 0
    fi
fi

# No working certificate generation methods available
echo "ERROR: No working certificate generation methods available"
echo "Available options:"
echo "  - Rebuild firmware with mbedTLS certificate generation support"
echo "  - Use HTTP-only mode (uhttpd will fall back automatically)"
echo ""
echo "Certificate generation requires:"
echo "  - mbedTLS with certificate writing support"
echo "  - OR OpenSSL compatibility layer"
echo ""
echo "For now, access the web interface via: http://$HOSTNAME/"

exit 1
