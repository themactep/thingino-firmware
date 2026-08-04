#!/bin/bash
# Regenerate optimized Bootstrap CSS and JS for Thingino WebUI.
# Requires: node, npm (with npx), sass (Dart Sass)
# Usage: ./scripts/optimize-bootstrap.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WWW_DIR="$REPO_ROOT/package/thingino-webui/files/www"
VENDOR_DIR="$WWW_DIR/a/vendor"
BUILD_DIR="$(mktemp -d)"
trap "rm -rf $BUILD_DIR" EXIT

echo "=== Installing Bootstrap ==="
cd "$BUILD_DIR"
npm install bootstrap@5.3.8 --save 2>/dev/null

BOOTSTRAP_DIR="$BUILD_DIR/node_modules/bootstrap"

# ── CSS: Purge unused styles ──────────────────────────────────────────────
echo "=== Purging Bootstrap CSS ==="

cat > "$BUILD_DIR/purgecss.config.mjs" << 'PCEOF'
export default {
  content: process.env.WWW_DIR + '/**/*.{html,js}',
  css: [process.env.BOOTSTRAP_DIR + '/dist/css/bootstrap.min.css'],
  safelist: {
    standard: [
      /^modal/, /^show/, /^fade/, /^collapsing/, /^offcanvas/,
      /^tooltip/, /^popover/, /^dropdown/, /^was-validated/,
      /^is-invalid/, /^is-valid/, /^alert-/,
      /^bs-/, /^tab-pane/, /^active/,
    ],
    greedy: [/^tooltip/, /^popover/, /^toast/],
  },
};
PCEOF

WWW_DIR="$WWW_DIR" BOOTSTRAP_DIR="$BOOTSTRAP_DIR" \
  npx purgecss --config "$BUILD_DIR/purgecss.config.mjs" --output "$VENDOR_DIR/bootstrap.min.css" 2>&1

echo "  $(wc -c < "$BOOTSTRAP_DIR/dist/css/bootstrap.min.css") → $(wc -c < "$VENDOR_DIR/bootstrap.min.css") bytes"

# ── JS: Copy the standard bundle (custom bundling is fragile) ──────────
echo "=== Installing Bootstrap JS (standard bundle) ==="
cp "$BOOTSTRAP_DIR/dist/js/bootstrap.bundle.min.js" "$VENDOR_DIR/bootstrap.bundle.min.js"
echo "  $(wc -c < "$BOOTSTRAP_DIR/dist/js/bootstrap.bundle.min.js") bytes (unchanged)"

# ── Final stats ────────────────────────────────────────────────────────────
echo ""
echo "=== Vendor directory ==="
du -sh "$VENDOR_DIR"
du -sh "$VENDOR_DIR"/*
