#!/usr/bin/env bash
# Fetch/refresh all ONVIF WSDL and XSD spec files.
# Run from the repo root or from this directory; files land in docs/onvif/wsdl/.
# Sources:
#   https://www.onvif.org/  (official canonical copies, updated with each spec release)
#   https://raw.githubusercontent.com/onvif/specs/master/  (files not served directly by onvif.org)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WSDL_DIR="$SCRIPT_DIR/wsdl"
mkdir -p "$WSDL_DIR"
cd "$WSDL_DIR"

ok=0; fail=0
fetch() {
    local file="$1" url="$2"
    printf "  %-25s <- %s\n" "$file" "$url"
    if curl -sSf -o "$file" "$url"; then
        ok=$((ok+1))
    else
        echo "  !! FAILED: $url"
        fail=$((fail+1))
    fi
}

echo "=== Core schema ==="
fetch onvif.xsd    "https://www.onvif.org/ver10/schema/onvif.xsd"
fetch common.xsd   "https://www.onvif.org/ver10/schema/common.xsd"

echo "=== Device Management (ver10/device) ==="
fetch devicemgmt.wsdl "https://www.onvif.org/ver10/device/wsdl/devicemgmt.wsdl"

echo "=== Events (ver10/events) ==="
fetch event.wsdl   "https://www.onvif.org/ver10/events/wsdl/event.wsdl"

echo "=== Media1 (ver10/media) ==="
fetch media.wsdl   "https://www.onvif.org/ver10/media/wsdl/media.wsdl"

echo "=== Media2 (ver20/media) — saved as media2.wsdl ==="
fetch media2.wsdl  "https://www.onvif.org/ver20/media/wsdl/media.wsdl"

echo "=== PTZ (ver20/ptz) ==="
fetch ptz.wsdl     "https://www.onvif.org/ver20/ptz/wsdl/ptz.wsdl"

echo "=== Imaging (ver20/imaging) ==="
fetch imaging.wsdl "https://www.onvif.org/ver20/imaging/wsdl/imaging.wsdl"

echo "=== Analytics (ver20/analytics) ==="
fetch analytics.wsdl "https://www.onvif.org/ver20/analytics/wsdl/analytics.wsdl"

echo "=== DeviceIO — not served by onvif.org directly; from GitHub ==="
fetch deviceio.wsdl \
    "https://raw.githubusercontent.com/onvif/specs/master/wsdl/ver10/deviceio.wsdl"

echo ""
echo "Done: $ok fetched, $fail failed."
echo "Files in $WSDL_DIR:"
ls -lh "$WSDL_DIR"/*.wsdl "$WSDL_DIR"/*.xsd 2>/dev/null
