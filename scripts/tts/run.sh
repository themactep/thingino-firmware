#!/bin/bash
# Thingino TTS Runner — auto-activates venv and runs generate.py
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_PYTHON="$SCRIPT_DIR/.venv/bin/python"
GENERATE="$SCRIPT_DIR/generate.py"

set -euo pipefail

# Suppress noisy loguru debug output
export LOGURU_LEVEL=WARNING

exec "$VENV_PYTHON" "$GENERATE" "$@"
