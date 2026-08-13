#!/usr/bin/env python3
"""
Thingino TTS Generator — standardized text-to-speech using Kokoro-82M.

Produces repeatable, high-quality audio with a fixed voice configuration.
All settings are pinned in config.yaml so every future generation sounds identical.

Usage:
    python generate.py "Hello world"                    # single phrase → output/
    python generate.py "Hello world" -o custom.wav      # named output
    python generate.py --stdin < phrases.txt            # batch from stdin
    python generate.py --list-voices                    # show available voices
"""

import argparse
import os
import re
import sys
import warnings
from pathlib import Path

# Suppress non-critical warnings for clean output
warnings.filterwarnings("ignore", category=UserWarning, module="torch")
warnings.filterwarnings("ignore", category=FutureWarning, module="torch")

import numpy as np
import soundfile as sf
import torch
import yaml
from phonemizer.backend import EspeakBackend

# ── Paths ────────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
MODEL_DIR = SCRIPT_DIR / "models"
OUTPUT_DIR = SCRIPT_DIR / "output"
DEFAULT_CONFIG = SCRIPT_DIR / "config.yaml"

# Local kokoro model modules (flattened from pip package, spacy-free)
sys.path.insert(0, str(SCRIPT_DIR))
from kokoro.model import KModel  # noqa: E402
sys.path.pop(0)

# ── Phoneme mapping from misaki's EspeakFallback ──────────────────────────
E2M = sorted(
    {
        "ʔˌn\u0329": "tn",
        "ʔn\u0329": "tn",
        "ʔn": "tn",
        "ʔ": "t",
        "a^ɪ": "I",
        "a^ʊ": "W",
        "d^ʒ": "ʤ",
        "e^ɪ": "A",
        "e": "A",
        "t^ʃ": "ʧ",
        "ɔ^ɪ": "Y",
        "ə^l": "ᵊl",
        "ʲo": "jo",
        "ʲə": "jə",
        "ʲ": "",
        "ɚ": "əɹ",
        "r": "ɹ",
        "x": "k",
        "ç": "k",
        "ɐ": "ə",
        "ɬ": "l",
        "\u0303": "",
    }.items(),
    key=lambda kv: -len(kv[0]),
)


def text_to_phonemes(text: str, british: bool = False) -> str:
    """Convert English text to Kokoro-compatible phonemes via espeak-ng."""
    backend = EspeakBackend(
        language="en-gb" if british else "en-us",
        preserve_punctuation=True,
        with_stress=True,
        tie="^",
    )
    ps = backend.phonemize([text])
    if not ps:
        return ""
    ps = ps[0].strip()

    # Apply espeak → Kokoro mappings (from misaki EspeakFallback)
    for old, new in E2M:
        ps = ps.replace(old, new)
    ps = re.sub(r"(\S)\u0329", r"ᵊ\1", ps).replace(chr(809), "")

    if british:
        ps = ps.replace("e^ə", "ɛː")
        ps = ps.replace("iə", "ɪə")
        ps = ps.replace("ə^ʊ", "Q")
    else:
        ps = ps.replace("o^ʊ", "O")
        ps = ps.replace("ɜːɹ", "ɜɹ")
        ps = ps.replace("ɜː", "ɜɹ")
        ps = ps.replace("ɪə", "iə")
        ps = ps.replace("ː", "")

    ps = ps.replace("o", "ɔ")  # for espeak < 1.52
    ps = ps.replace("^", "")
    return ps


# ── Config ────────────────────────────────────────────────────────────────
DEFAULT_CONFIG_YAML = """\
# Thingino TTS — default configuration
# All generated audio will use these settings for repeatable output.

voice: af_heart         # female American English (Kokoro voice name)
speed: 1.0              # playback speed (0.5 = slower, 1.5 = faster)
sample_rate: 24000      # Kokoro native sample rate
format: wav             # wav or mp3 (mp3 requires ffmpeg)
british: false          # true for British English phonemes
"""


def load_config(path=None):
    path = Path(path) if path else DEFAULT_CONFIG
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(DEFAULT_CONFIG_YAML)
        print(f"Created default config at {path}")
    with open(path) as f:
        return yaml.safe_load(f)


# ── Model ─────────────────────────────────────────────────────────────────
_model = None
_config_cache = None


def get_model(config):
    global _model, _config_cache
    if _model is None or _config_cache != config:
        device = "cpu"  # Intel GPU acceleration via OpenVINO can be added later
        _model = KModel(config=str(MODEL_DIR / "config.json"),
                         model=str(MODEL_DIR / "kokoro-v1_0.pth"))
        _model = _model.to(device).eval()
        _config_cache = config
    return _model


# ── Generation ────────────────────────────────────────────────────────────
def generate(text: str, config: dict, output_path=None) -> np.ndarray:
    """Generate audio for text. Returns (audio_array, sample_rate)."""
    model = get_model(config)
    voice_name = config["voice"]
    speed = config["speed"]
    british = config.get("british", False)

    # Load voice
    voice_path = MODEL_DIR / "voices" / f"{voice_name}.pt"
    if not voice_path.exists():
        raise FileNotFoundError(
            f"Voice '{voice_name}' not found at {voice_path}. "
            f"Available voices: {list_voices()}"
        )
    pack = torch.load(str(voice_path), weights_only=True)

    # Phonemize
    phonemes = text_to_phonemes(text, british=british)
    if not phonemes:
        print(f"Warning: empty phonemes for text: {text!r}")
        return np.zeros(0)

    # Truncate if too long (model limit: 510 phonemes + BOS/EOS = 512)
    if len(phonemes) > 510:
        print(f"Warning: truncating phonemes from {len(phonemes)} to 510")
        phonemes = phonemes[:510]

    # Run inference
    with torch.no_grad():
        output = model(phonemes, pack[len(phonemes) - 1], speed, return_output=True)

    audio = output.audio.numpy()

    # Save if requested
    if output_path:
        sf.write(str(output_path), audio, config["sample_rate"])
        print(f"Saved: {output_path} ({len(audio) / config['sample_rate']:.2f}s)")

    return audio


# ── Voicelist ─────────────────────────────────────────────────────────────
def list_voices():
    voices_dir = MODEL_DIR / "voices"
    if not voices_dir.exists():
        return []
    return sorted([p.stem for p in voices_dir.glob("*.pt")])


def describe_voices():
    """Describe each available voice by language and gender."""
    descriptions = {
        "af_heart": "🇺🇸 Female — warm, natural (default)",
        "af_alloy": "🇺🇸 Female — versatile",
        "af_aoede": "🇺🇸 Female — melodic",
        "af_bella": "🇺🇸 Female — bright, clear",
        "af_jessica": "🇺🇸 Female — calm",
        "af_kore": "🇺🇸 Female — energetic",
        "af_nicole": "🇺🇸 Female — soft",
        "af_nova": "🇺🇸 Female — crisp",
        "af_river": "🇺🇸 Female — smooth",
        "af_sarah": "🇺🇸 Female — gentle",
        "af_sky": "🇺🇸 Female — airy",
        "am_adam": "🇺🇸 Male — deep",
        "am_echo": "🇺🇸 Male — resonant",
        "am_eric": "🇺🇸 Male — steady",
        "am_fenrir": "🇺🇸 Male — rich",
        "am_liam": "🇺🇸 Male — casual",
        "am_michael": "🇺🇸 Male — clear",
        "am_onyx": "🇺🇸 Male — strong",
        "am_puck": "🇺🇸 Male — light",
        "am_santa": "🇺🇸 Male — jolly",
        "bf_alice": "🇬🇧 Female — refined",
        "bf_emma": "🇬🇧 Female — elegant",
        "bf_isabella": "🇬🇧 Female — bright",
        "bf_lily": "🇬🇧 Female — soft",
        "bm_daniel": "🇬🇧 Male — deep",
        "bm_fable": "🇬🇧 Male — warm",
        "bm_george": "🇬🇧 Male — classic",
        "bm_lewis": "🇬🇧 Male — crisp",
    }
    voices = list_voices()
    print(f"{len(voices)} voices available:\n")
    for v in voices:
        desc = descriptions.get(v, "")
        print(f"  {v:<20} {desc}")


# ── CLI ───────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="Thingino TTS — standardized Kokoro text-to-speech generator"
    )
    parser.add_argument(
        "text", nargs="?", help="Text to synthesize (or use --stdin)"
    )
    parser.add_argument(
        "-o", "--output", help="Output file path (default: auto-named in output/)"
    )
    parser.add_argument(
        "-c", "--config", default=DEFAULT_CONFIG, help="Path to config.yaml"
    )
    parser.add_argument(
        "--stdin", action="store_true", help="Read text from stdin (one phrase per line)"
    )
    parser.add_argument(
        "--list-voices", action="store_true", help="List available voices and exit"
    )
    parser.add_argument(
        "-v", "--voice", help="Override voice from config"
    )
    parser.add_argument(
        "-s", "--speed", type=float, help="Override speed from config"
    )
    args = parser.parse_args()

    # Voice listing
    if args.list_voices:
        describe_voices()
        return

    # Load config
    config = load_config(args.config)
    if args.voice:
        config["voice"] = args.voice
    if args.speed:
        config["speed"] = args.speed

    # Collect texts
    texts = []
    if args.stdin:
        texts = [line.strip() for line in sys.stdin if line.strip()]
    elif args.text:
        texts = [args.text]
    else:
        parser.print_help()
        return

    # Ensure output directory exists
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Generate each phrase
    for text in texts:
        # Auto-name from text
        if args.output and len(texts) == 1:
            out_path = Path(args.output)
        else:
            slug = re.sub(r"[^a-z0-9]+", "_", text.lower().strip()).strip("_")[:60]
            if not slug:
                slug = "output"
            ext = config.get("format", "wav")
            out_path = OUTPUT_DIR / f"{slug}.{ext}"

        audio = generate(text, config, output_path=out_path)

        # Optionally convert to mp3
        if str(out_path).endswith(".mp3"):
            wav_path = out_path.with_suffix(".wav")
            os.rename(out_path, wav_path)
            import subprocess
            subprocess.run(
                ["ffmpeg", "-y", "-i", str(wav_path), "-q:a", "2", str(out_path)],
                capture_output=True,
            )
            wav_path.unlink()
            print(f"Converted to MP3: {out_path}")


if __name__ == "__main__":
    main()
