#!/bin/bash
# Regenerate the reduced offline vendor set at files/www/a/vendor-lite/.
#
# This is the always-installed set that lets the full web UI render in AP mode
# with no uplink: purged Bootstrap CSS and a tree-shaken Bootstrap JS containing
# only the components the UI uses. Chart.js, the Montserrat webfont and the icon
# font are intentionally excluded (the rewriter drops their links).
#
# Requires: node + npm (npx fetches purgecss/esbuild on demand).
# Usage: package/thingino-webui/scripts/optimize-offline-vendor.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="$PKG_DIR/files/www/a/vendor-lite"
BS_VER="5.3.8"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
npm init -y >/dev/null 2>&1
npm i --no-audit --no-fund "bootstrap@$BS_VER" @popperjs/core >/dev/null 2>&1

# Tree-shaken JS: only the components the UI references via data-bs-* / main.js.
# Popper is pulled in by dropdown and tooltip.
cat >entry.js <<'EOF'
import Modal from 'bootstrap/js/dist/modal';
import Offcanvas from 'bootstrap/js/dist/offcanvas';
import Tooltip from 'bootstrap/js/dist/tooltip';
import Dropdown from 'bootstrap/js/dist/dropdown';
import Collapse from 'bootstrap/js/dist/collapse';
import Tab from 'bootstrap/js/dist/tab';
import Alert from 'bootstrap/js/dist/alert';
import Button from 'bootstrap/js/dist/button';
window.bootstrap = { Modal, Offcanvas, Tooltip, Dropdown, Collapse, Tab, Alert, Button };
EOF
npx --yes esbuild entry.js --bundle --minify --format=iife \
	--outfile="$OUT/bootstrap.bundle.min.js"

# Purge the pristine Bootstrap CSS against every package web root. The UI is
# assembled from thingino-webui plus the streamer/plugin packages (preview.html
# comes from the streamer), so scanning only thingino-webui drops classes the
# other pages use. Do not purge the already-purged repo copy: it is missing
# those classes too.
REPO_ROOT="$(cd "$PKG_DIR/../.." && pwd)"
(cd "$REPO_ROOT" && npx --yes purgecss \
	--css "$TMP/node_modules/bootstrap/dist/css/bootstrap.min.css" \
	--content 'package/*/files/www/**/*.html' 'package/*/files/www/**/*.js' \
	--output "$OUT/bootstrap.min.css")

# Icons are intentionally not bundled: the icon-font subset (optimize-icons.sh)
# only carries the glyphs thingino-webui uses, so streamer/preview pages showed
# missing glyphs (tofu). apply_offline_assets.py drops the stylesheet and hides
# the icon elements instead.
rm -f "$OUT/bootstrap-icons.min.css" "$OUT/fonts/bootstrap-icons.woff2"
rmdir "$OUT/fonts" 2>/dev/null || true

echo "vendor-lite regenerated:"
du -ab "$OUT" | sort -n | tail -6
