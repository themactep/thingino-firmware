# Thingino TTS Pipeline

Standardized text-to-speech audio generation using [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) —
a high-quality 82M-parameter neural TTS model. Produces repeatable output with a pinned voice
configuration so every future generation sounds identical.

## Quickstart

```bash
# First time only: download model + voices, create venv
./scripts/tts/setup.sh

# Single phrase → output/hello_world.wav
./scripts/tts/run.sh "Hello world"

# Custom output path
./scripts/tts/run.sh "Hello world" -o demo.wav

# Batch from file (one phrase per line)
./scripts/tts/batch.sh phrases.txt

# Batch from stdin
echo "Line one" | ./scripts/tts/batch.sh
```

## Commands

```
run.sh [text]              Generate audio from text argument
run.sh --stdin             Read text from stdin
run.sh --list-voices       List available voices with descriptions
run.sh -v <voice>          Override voice from config.yaml
run.sh -s <speed>          Override speed (0.5 = slower, 1.5 = faster)
run.sh -o <path>           Custom output path
```

## Configuration

All settings are in [`config.yaml`](config.yaml). Changing values there pins the defaults
for every future generation:

| Setting | Default | Description |
|---------|---------|-------------|
| `voice` | `af_heart` | Female American English (warm, natural) |
| `speed` | `1.0` | Playback speed multiplier |
| `format` | `wav` | Output format (`wav` or `mp3`) |
| `british` | `false` | Use British English phonemes |

## Available Voices

5 American English female voices are downloaded by `setup.sh`:

| Voice | Character |
|-------|-----------|
| `af_heart` | Warm, natural (default) |
| `af_bella` | Bright, clear |
| `af_nicole` | Soft |
| `af_sarah` | Gentle |
| `af_sky` | Airy |

To download additional voices (British, male, etc.):

```bash
# List all available voices on HuggingFace
.venv/bin/python -c "
from huggingface_hub import list_repo_files
for f in sorted(list_repo_files('hexgrad/Kokoro-82M')):
    if 'voices/' in f: print(f)
"

# Download one
.venv/bin/python -c "
from huggingface_hub import hf_hub_download
hf_hub_download('hexgrad/Kokoro-82M', 'voices/bf_emma.pt', local_dir='models')
"
```

## Architecture

```
Text → espeak-ng (phonemizer) → Kokoro phonemes → KModel (82M transformer) → WAV
```

- **Phonemization**: `espeak-ng` + `phonemizer` (offline, no GPU needed, avoids spacy dependency)
- **Synthesis**: Kokoro-82M StyleTTS2 model running on CPU via PyTorch
- **Output**: 24 kHz, 16-bit mono WAV (or MP3 via ffmpeg)

## GPU Acceleration

The Intel Arc B70 GPU can be used by switching to OpenVINO ONNX runtime:

1. Export the model to ONNX (one-time conversion)
2. Install `onnxruntime-openvino`
3. Update `generate.py` to use the ONNX backend

This is not wired up yet — the CPU path produces 2-5 seconds of audio per second
of processing, which is fast enough for most use cases.

## Dependencies

Python 3.14 + packages from `requirements.txt` installed into `.venv/`:

```
numpy pyyaml soundfile torch transformers scipy phonemizer loguru huggingface_hub onnxruntime
```

System dependency: `espeak-ng` (for phonemization).

## Files

```
scripts/tts/
├── README.md            # This file
├── setup.sh             # One-time bootstrap (downloads model + voices, creates venv)
├── config.yaml          # Pinned voice + format settings
├── generate.py          # Main TTS engine
├── run.sh               # Venv wrapper
├── batch.sh             # Batch generation from stdin/file
├── requirements.txt     # Python deps
├── .gitignore           # Ignores output/, models/, .venv/
├── kokoro/              # Spacy-free Kokoro model modules (committed)
├── models/              # Downloaded by setup.sh (gitignored)
└── output/              # Generated .wav files (gitignored)
```
