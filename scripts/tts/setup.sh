#!/bin/bash
# Thingino TTS — one-time setup script
# Downloads Kokoro-82M model + voices from HuggingFace and creates the Python venv.
# Run once on a new machine (or after a fresh clone). Safe to re-run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL_DIR="$SCRIPT_DIR/models"
VENV_DIR="$SCRIPT_DIR/.venv"

echo "=== Thingino TTS Setup ==="
echo ""

# ── Python venv ──────────────────────────────────────────────────────────
if [ -d "$VENV_DIR" ]; then
    echo "[1/3] Python venv already exists, skipping."
else
    echo "[1/3] Creating Python venv..."
    python3 -m venv "$VENV_DIR"
    echo "       Installing dependencies..."
    "$VENV_DIR/bin/pip" install --quiet -r "$SCRIPT_DIR/requirements.txt"
    echo "       Done."
fi

# ── Model download ────────────────────────────────────────────────────────
echo "[2/3] Checking Kokoro model..."
mkdir -p "$MODEL_DIR/voices"

if [ -f "$MODEL_DIR/kokoro-v1_0.pth" ] && [ -f "$MODEL_DIR/config.json" ]; then
    echo "       Model already downloaded, skipping."
else
    echo "       Downloading Kokoro-82M model (~170 MB)..."
    "$VENV_DIR/bin/python3" -c "
from huggingface_hub import hf_hub_download
print('         config.json...')
hf_hub_download('hexgrad/Kokoro-82M', 'config.json', local_dir='$MODEL_DIR')
print('         kokoro-v1_0.pth...')
hf_hub_download('hexgrad/Kokoro-82M', 'kokoro-v1_0.pth', local_dir='$MODEL_DIR')
    "
    echo "       Done."
fi

# ── Voices ────────────────────────────────────────────────────────────────
echo "[3/3] Checking voices..."
VOICES=(
    af_heart   # warm, natural (default)
    af_bella   # bright, clear
    af_nicole  # soft
    af_sarah   # gentle
    af_sky     # airy
)

MISSING=()
for voice in "${VOICES[@]}"; do
    if [ ! -f "$MODEL_DIR/voices/${voice}.pt" ]; then
        MISSING+=("$voice")
    fi
done

if [ ${#MISSING[@]} -eq 0 ]; then
    echo "       All ${#VOICES[@]} voices already downloaded, skipping."
else
    echo "       Downloading ${#MISSING[@]} voice(s)..."
    for voice in "${MISSING[@]}"; do
        echo "         $voice..."
        "$VENV_DIR/bin/python3" -c "
from huggingface_hub import hf_hub_download
hf_hub_download('hexgrad/Kokoro-82M', 'voices/${voice}.pt', local_dir='$MODEL_DIR')
        "
    done
    echo "       Done."
fi

# ── Verify ────────────────────────────────────────────────────────────────
echo ""
echo "=== Setup complete ==="
echo ""
"$VENV_DIR/bin/python3" "$SCRIPT_DIR/generate.py" --list-voices 2>/dev/null
echo ""
echo "Try it: ./scripts/tts/run.sh 'Hello world'"
