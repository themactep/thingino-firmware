#!/bin/sh
set -eu

usage() {
    cat <<'EOF'
Usage: convert_audio.sh [-o out_dir] [-r sample_rate] [-c channels] [-b lossy_kbps] input_audio

Converts the input audio into multiple Prudynt-supported formats (PCM, WAV, FLAC,
MP3, Opus, AAC). Requires ffmpeg/libopus/libmp3lame/aac encoders.

Options:
  -o out_dir        Directory for generated files (default: ./converted)
  -r sample_rate    Target sample rate in Hz (default: 16000)
  -c channels       Channel count (default: 1)
  -b lossy_kbps     Bitrate in kbps for MP3/AAC (default: 64). Opus uses half.
  -h                Show this help.
EOF
}

OUT_DIR=converted
SAMPLE_RATE=16000
CHANNELS=1
LOSSY_KBPS=64

while getopts "o:r:c:b:h" opt; do
    case ${opt} in
        o) OUT_DIR=${OPTARG} ;;
        r) SAMPLE_RATE=${OPTARG} ;;
        c) CHANNELS=${OPTARG} ;;
        b) LOSSY_KBPS=${OPTARG} ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [ $# -ne 1 ]; then
    usage >&2
    exit 1
fi

INPUT=$1
if [ ! -f "$INPUT" ]; then
    echo "Input file '$INPUT' not found" >&2
    exit 1
fi

command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg is required" >&2; exit 1; }

mkdir -p "$OUT_DIR"
BASENAME=$(basename "$INPUT")
STEM=${BASENAME%.*}
LOSSY_BITRATE=${LOSSY_KBPS}k
OPUS_KBPS=$((LOSSY_KBPS / 2))
[ "$OPUS_KBPS" -lt 8 ] && OPUS_KBPS=8
IS_RAW_PCM=0
case $BASENAME in
    *.pcm) IS_RAW_PCM=1 ;;
esac

run_ffmpeg() {
    if [ "$IS_RAW_PCM" -eq 1 ]; then
        ffmpeg -loglevel error -y -f s16le -ar "$SAMPLE_RATE" -ac "$CHANNELS" -i "$INPUT" "$@"
    else
        ffmpeg -loglevel error -y -i "$INPUT" "$@"
    fi
}

# WAV (container only)
run_ffmpeg -ar "$SAMPLE_RATE" -ac "$CHANNELS" "$OUT_DIR/$STEM.wav"

# RAW PCM (s16le)
run_ffmpeg -f s16le -acodec pcm_s16le -ar "$SAMPLE_RATE" -ac "$CHANNELS" "$OUT_DIR/$STEM.pcm"

# FLAC (lossless)
run_ffmpeg -c:a flac -ar "$SAMPLE_RATE" -ac "$CHANNELS" "$OUT_DIR/$STEM.flac"

# MP3
run_ffmpeg -c:a libmp3lame -b:a "$LOSSY_BITRATE" -ar "$SAMPLE_RATE" -ac "$CHANNELS" "$OUT_DIR/$STEM.mp3"

# Opus (Ogg)
run_ffmpeg -c:a libopus -b:a "${OPUS_KBPS}k" -application audio -ar "$SAMPLE_RATE" -ac "$CHANNELS" "$OUT_DIR/$STEM.opus"

# AAC (ADTS)
run_ffmpeg -c:a aac -b:a "$LOSSY_BITRATE" -ar "$SAMPLE_RATE" -ac "$CHANNELS" -f adts "$OUT_DIR/$STEM.aac"

echo "Converted $INPUT -> $OUT_DIR/$STEM.[pcm|wav|flac|mp3|opus|aac]"
