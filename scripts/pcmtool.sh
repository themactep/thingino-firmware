#!/bin/sh
# Convert audio file into PCM format, or play PCM audio file
# 2024 Paul Philippov, paul@themactep.com

if [ -z "$1" ]; then
	echo "Usage: $0 <audio file>"
	exit 1
fi	

encode() {
	ffmpeg -i "$1" -ar 16000 -f s16le -acodec pcm_s16le -ac 1 "${1%.*}.pcm"
}

decode() {
	ffplay -f s16le -ar 16000 "$1"
}

case "${1##*.}" in
	pcm)
		decode "$1"
		;;
	mp3 | opus | wav)
		encode "$1"
		;;
	*)
		echo "Unknown file format"
		exit 1
esac

exit 0
