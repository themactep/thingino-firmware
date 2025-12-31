#!/bin/sh
set -eu

usage() {
    cat <<'EOF'
Usage: convert_audio.sh [-o out_dir] [-r sample_rate] [-c channels] [-b lossy_kbps] [-n] [-f formats] input_audio [input_audio2 ...]

Converts the input audio into multiple Prudynt-supported formats (PCM, WAV, FLAC,
MP3, Opus, AAC). Requires ffmpeg/libopus/libmp3lame/aac encoders.
Supports multiple input files and wildcards (e.g., *.wav).

Options:
  -o out_dir        Directory for generated files (default: ./converted)
  -r sample_rate    Target sample rate in Hz (default: 16000)
  -c channels       Channel count (default: 1)
  -b lossy_kbps     Bitrate in kbps for MP3/AAC (default: 64). Opus uses half.
  -n                Apply audio normalization (loudnorm)
  -f formats        Comma-separated list of formats (default: all)
                    Available: pcm,wav,flac,mp3,opus,aac
  -h                Show this help.
EOF
}

OUT_DIR=converted
SAMPLE_RATE=16000
CHANNELS=1
LOSSY_KBPS=64
NORMALIZE=0
FORMATS="pcm,wav,flac,mp3,opus,aac"

while getopts "o:r:c:b:nf:h" opt; do
    case ${opt} in
        o) OUT_DIR=${OPTARG} ;;
        r) SAMPLE_RATE=${OPTARG} ;;
        c) CHANNELS=${OPTARG} ;;
        b) LOSSY_KBPS=${OPTARG} ;;
        n) NORMALIZE=1 ;;
        f) FORMATS=${OPTARG} ;;
        h) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [ $# -lt 1 ]; then
    usage >&2
    exit 1
fi

command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg is required" >&2; exit 1; }

mkdir -p "$OUT_DIR"

LOSSY_BITRATE=${LOSSY_KBPS}k
OPUS_KBPS=$((LOSSY_KBPS / 2))
[ "$OPUS_KBPS" -lt 8 ] && OPUS_KBPS=8

should_convert() {
    case ",$FORMATS," in
        *,"$1",*) return 0 ;;
        *) return 1 ;;
    esac
}

process_file() {
    INPUT=$1
    if [ ! -f "$INPUT" ]; then
        echo "Input file '$INPUT' not found, skipping" >&2
        return 1
    fi

    BASENAME=$(basename "$INPUT")
    STEM=${BASENAME%.*}
    IS_RAW_PCM=0
    case $BASENAME in
        *.pcm) IS_RAW_PCM=1 ;;
    esac

    run_ffmpeg() {
        local af_filter=""
        if [ "$NORMALIZE" -eq 1 ]; then
            af_filter="-af loudnorm=I=-16:TP=-1.5:LRA=11"
        fi
        if [ "$IS_RAW_PCM" -eq 1 ]; then
            ffmpeg -loglevel error -y -f s16le -ar "$SAMPLE_RATE" -ac "$CHANNELS" -i "$INPUT" $af_filter "$@"
        else
            ffmpeg -loglevel error -y -i "$INPUT" $af_filter "$@"
        fi
    }

    CONVERTED=""

    # WAV (container only)
    if should_convert wav; then
        run_ffmpeg -ar "$SAMPLE_RATE" -ac "$CHANNELS" "$OUT_DIR/$STEM.wav"
        CONVERTED="${CONVERTED}wav|"
    fi

    # RAW PCM (s16le)
    if should_convert pcm; then
        run_ffmpeg -f s16le -acodec pcm_s16le -ar "$SAMPLE_RATE" -ac "$CHANNELS" "$OUT_DIR/$STEM.pcm"
        CONVERTED="${CONVERTED}pcm|"
    fi

    # FLAC (lossless)
    if should_convert flac; then
        run_ffmpeg -c:a flac -ar "$SAMPLE_RATE" -ac "$CHANNELS" "$OUT_DIR/$STEM.flac"
        CONVERTED="${CONVERTED}flac|"
    fi

    # MP3
    if should_convert mp3; then
        run_ffmpeg -c:a libmp3lame -b:a "$LOSSY_BITRATE" -ar "$SAMPLE_RATE" -ac "$CHANNELS" "$OUT_DIR/$STEM.mp3"
        CONVERTED="${CONVERTED}mp3|"
    fi

    # Opus (Ogg)
    if should_convert opus; then
        run_ffmpeg -c:a libopus -b:a "${OPUS_KBPS}k" -application audio -ar "$SAMPLE_RATE" -ac "$CHANNELS" "$OUT_DIR/$STEM.opus"
        CONVERTED="${CONVERTED}opus|"
    fi

    # AAC (ADTS)
    if should_convert aac; then
        run_ffmpeg -c:a aac -b:a "$LOSSY_BITRATE" -ar "$SAMPLE_RATE" -ac "$CHANNELS" -f adts "$OUT_DIR/$STEM.aac"
        CONVERTED="${CONVERTED}aac|"
    fi

    CONVERTED=${CONVERTED%|}
    echo "Converted $INPUT -> $OUT_DIR/$STEM.[${CONVERTED}]"
}

for INPUT_FILE in "$@"; do
    process_file "$INPUT_FILE"
done
