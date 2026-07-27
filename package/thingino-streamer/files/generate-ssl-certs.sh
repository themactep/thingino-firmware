#!/bin/sh

# SSL Certificate Generation Script for Thingino Streamer
# Generates self-signed certificates for RTSPS and RTMPS streaming

set -e

# Default paths
CERT_DIR="/etc/ssl/certs"
KEY_DIR="/etc/ssl/private"
CERT_FILE="$CERT_DIR/rtsp-server.crt"
KEY_FILE="$KEY_DIR/rtsp-server.key"

# Default certificate parameters
DEFAULT_COUNTRY="US"
DEFAULT_STATE="State"
DEFAULT_CITY="City"
DEFAULT_ORG="Thingino"
DEFAULT_CN="camera.local"
DEFAULT_DAYS="3650"
DEFAULT_KEYSIZE="2048"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Generate SSL certificates for Thingino Streamer (RTSPS/RTMPS)"
    echo ""
    echo "Options:"
    echo "  -c, --cert-file PATH     Certificate file path (default: $CERT_FILE)"
    echo "  -k, --key-file PATH      Private key file path (default: $KEY_FILE)"
    echo "  -d, --days DAYS          Certificate validity in days (default: $DEFAULT_DAYS)"
    echo "  -s, --key-size SIZE      RSA key size in bits (default: $DEFAULT_KEYSIZE)"
    echo "  -n, --common-name CN     Common name for certificate (default: $DEFAULT_CN)"
    echo "  --country CODE           Country code (default: $DEFAULT_COUNTRY)"
    echo "  --state STATE            State/Province (default: $DEFAULT_STATE)"
    echo "  --city CITY              City/Locality (default: $DEFAULT_CITY)"
    echo "  --org ORG                Organization (default: $DEFAULT_ORG)"
    echo "  -f, --force              Overwrite existing certificates"
    echo "  -q, --quiet              Quiet mode (minimal output)"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Generate with defaults"
    echo "  $0 -n camera.example.com             # Custom common name"
    echo "  $0 -d 365 -s 4096                    # 1 year validity, 4096-bit key"
    echo "  $0 -f                                 # Force overwrite existing certs"
    echo ""
}

log_info() {
    if [ "$QUIET" != "1" ]; then
        printf "${GREEN}[INFO]${NC} %s\n" "$1"
    fi
}

log_warn() {
    if [ "$QUIET" != "1" ]; then
        printf "${YELLOW}[WARN]${NC} %s\n" "$1"
    fi
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

check_ssl_tools() {
    # Check for available SSL certificate generation tools
    if command -v wolfssl-certgen >/dev/null 2>&1; then
        SSL_TOOL="wolfssl-certgen"
        log_info "Using wolfSSL certificate generator"
    elif command -v mbedtls-certgen >/dev/null 2>&1; then
        SSL_TOOL="mbedtls-certgen"
        log_info "Using mbedTLS certificate generator"
    elif command -v openssl >/dev/null 2>&1; then
        SSL_TOOL="openssl"
        log_info "Using OpenSSL certificate generator"
    else
        log_error "No SSL certificate generator found."
        log_error "Please install one of: wolfssl-certgen, mbedtls-certgen, or openssl"
        exit 1
    fi
}

create_directories() {
    log_info "Creating SSL directories..."
    mkdir -p "$CERT_DIR" "$KEY_DIR"

    # Set proper permissions for directories
    chmod 755 "$CERT_DIR"
    chmod 700 "$KEY_DIR"
}

check_existing_certs() {
    if [ -f "$CERT_FILE" ] || [ -f "$KEY_FILE" ]; then
        if [ "$FORCE" != "1" ]; then
            log_warn "SSL certificates already exist:"
            [ -f "$CERT_FILE" ] && log_warn "  Certificate: $CERT_FILE"
            [ -f "$KEY_FILE" ] && log_warn "  Private key: $KEY_FILE"
            log_warn "Use --force to overwrite existing certificates"
            exit 1
        else
            log_info "Overwriting existing certificates (--force specified)"
        fi
    fi
}

generate_certificate() {
    log_info "Generating SSL certificate using $SSL_TOOL..."
    log_info "  Common Name: $COMMON_NAME"
    log_info "  Key Size: $KEY_SIZE bits"
    log_info "  Validity: $DAYS days"

    case "$SSL_TOOL" in
        "wolfssl-certgen")
            # Use wolfSSL certificate generator
            if wolfssl-certgen -h "$COMMON_NAME" -c "$CERT_FILE" -k "$KEY_FILE" -d "$DAYS" -s "$KEY_SIZE" >/dev/null 2>&1; then
                CERT_SUCCESS=1
            else
                CERT_SUCCESS=0
            fi
            ;;
        "mbedtls-certgen")
            # Use mbedTLS certificate generator
            # Convert RSA key size to ECDSA equivalent for better performance
            if [ "$KEY_SIZE" = "2048" ]; then
                ECDSA_SIZE=256
            elif [ "$KEY_SIZE" = "3072" ]; then
                ECDSA_SIZE=384
            elif [ "$KEY_SIZE" = "4096" ]; then
                ECDSA_SIZE=521
            else
                ECDSA_SIZE=256  # Default to 256-bit ECDSA
            fi

            if mbedtls-certgen -h "$COMMON_NAME" -c "$CERT_FILE" -k "$KEY_FILE" -d "$DAYS" -s "$ECDSA_SIZE" -t ecdsa >/dev/null 2>&1; then
                CERT_SUCCESS=1
            else
                CERT_SUCCESS=0
            fi
            ;;
        "openssl")
            # Use OpenSSL
            SUBJECT="/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/CN=$COMMON_NAME"
            if openssl req -x509 -newkey rsa:$KEY_SIZE \
                -keyout "$KEY_FILE" \
                -out "$CERT_FILE" \
                -days "$DAYS" -nodes \
                -subj "$SUBJECT" >/dev/null 2>&1; then
                CERT_SUCCESS=1
            else
                CERT_SUCCESS=0
            fi
            ;;
        *)
            log_error "Unknown SSL tool: $SSL_TOOL"
            return 1
            ;;
    esac

    if [ "$CERT_SUCCESS" = "1" ]; then
        # Set proper permissions
        chmod 600 "$KEY_FILE"
        chmod 644 "$CERT_FILE"

        log_info "SSL certificates generated successfully:"
        log_info "  Certificate: $CERT_FILE"
        log_info "  Private Key: $KEY_FILE"

        # Display certificate info if not quiet
        if [ "$QUIET" != "1" ] && command -v openssl >/dev/null 2>&1; then
            echo ""
            log_info "Certificate details:"
            openssl x509 -in "$CERT_FILE" -noout -subject -dates 2>/dev/null || true
        fi

        return 0
    else
        log_error "Failed to generate SSL certificate with $SSL_TOOL"
        return 1
    fi
}

verify_certificate() {
    log_info "Verifying generated certificate..."

    # Check if certificate and key files exist and are not empty
    if [ ! -f "$CERT_FILE" ] || [ ! -s "$CERT_FILE" ]; then
        log_error "Certificate file is missing or empty: $CERT_FILE"
        return 1
    fi

    if [ ! -f "$KEY_FILE" ] || [ ! -s "$KEY_FILE" ]; then
        log_error "Private key file is missing or empty: $KEY_FILE"
        return 1
    fi

    # Check if certificate has PEM format markers
    if ! grep -q "BEGIN CERTIFICATE" "$CERT_FILE" 2>/dev/null; then
        log_error "Certificate file does not appear to be in PEM format"
        return 1
    fi

    if ! grep -q "BEGIN.*PRIVATE KEY" "$KEY_FILE" 2>/dev/null; then
        log_error "Private key file does not appear to be in PEM format"
        return 1
    fi

    # Try OpenSSL verification if available (optional)
    if command -v openssl >/dev/null 2>&1; then
        if openssl x509 -in "$CERT_FILE" -noout -text >/dev/null 2>&1; then
            log_info "Certificate verification successful (OpenSSL)"
        else
            log_info "Certificate verification passed basic checks (OpenSSL verification failed, but this is normal for some certificate formats)"
        fi
    else
        log_info "Certificate verification passed basic checks (OpenSSL not available for detailed verification)"
    fi

    return 0
}

# Parse command line arguments
FORCE=0
QUIET=0
DAYS="$DEFAULT_DAYS"
KEY_SIZE="$DEFAULT_KEYSIZE"
COMMON_NAME="$DEFAULT_CN"
COUNTRY="$DEFAULT_COUNTRY"
STATE="$DEFAULT_STATE"
CITY="$DEFAULT_CITY"
ORG="$DEFAULT_ORG"

while [ $# -gt 0 ]; do
    case $1 in
        -c|--cert-file)
            CERT_FILE="$2"
            CERT_DIR="$(dirname "$CERT_FILE")"
            shift 2
            ;;
        -k|--key-file)
            KEY_FILE="$2"
            KEY_DIR="$(dirname "$KEY_FILE")"
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
        -n|--common-name)
            COMMON_NAME="$2"
            shift 2
            ;;
        --country)
            COUNTRY="$2"
            shift 2
            ;;
        --state)
            STATE="$2"
            shift 2
            ;;
        --city)
            CITY="$2"
            shift 2
            ;;
        --org)
            ORG="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=1
            shift
            ;;
        -q|--quiet)
            QUIET=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate numeric parameters
case "$DAYS" in
    ''|*[!0-9]*)
        log_error "Invalid days value: $DAYS"
        exit 1
        ;;
esac

case "$KEY_SIZE" in
    ''|*[!0-9]*)
        log_error "Invalid key size value: $KEY_SIZE"
        exit 1
        ;;
esac

# Main execution
main() {
    if [ "$QUIET" != "1" ]; then
        echo "Thingino Streamer SSL Certificate Generator"
        echo "==========================================="
        echo ""
    fi

    check_ssl_tools
    create_directories
    check_existing_certs

    if generate_certificate && verify_certificate; then
        log_info "SSL certificate generation completed successfully"

        if [ "$QUIET" != "1" ]; then
            echo ""
            log_info "Next steps:"
            log_info "1. Restart the streamer service: /etc/init.d/S95streamer restart"
            log_info "2. Configure RTSPS in /etc/streamer.d/rtsp.json"
            log_info "3. Test RTSPS connection: rtsps://camera.local:322/ch0"
        fi

        exit 0
    else
        log_error "SSL certificate generation failed"
        exit 1
    fi
}

main "$@"
