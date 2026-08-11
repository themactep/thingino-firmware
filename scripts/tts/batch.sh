#!/bin/bash
# Batch TTS generation — one phrase per line from stdin or file
# Usage:
#   echo "Hello world" | scripts/tts/batch.sh
#   scripts/tts/batch.sh phrases.txt

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

set -euo pipefail

if [ -n "$1" ] && [ -f "$1" ]; then
    "$SCRIPT_DIR/run.sh" --stdin < "$1"
else
    "$SCRIPT_DIR/run.sh" --stdin
fi
