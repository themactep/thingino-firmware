#!/bin/sh
# Regression check for the open-ISP audio path on a Thingino camera.
#
# Usage: check-stream-health.sh <camera-ip> [user] [pass] [seconds]
#
# The T31 open-ISP audio path must deliver full-rate, gap-free AAC. This
# captures /mic and ch0 over RTSP and fails when the audio rate is low (the
# 24 kHz half-rate symptom) or the A/V audio timeline has discontinuities
# (the PTS-gap symptom). Run it after touching openimp, the ISP driver, or
# prudynt's audio path.
#
# Needs ffmpeg/ffprobe on the host. Exits non-zero on failure.

set -eu

IP=${1:-}
[ -n "$IP" ] || {
	echo "usage: $0 <camera-ip> [user] [pass] [seconds]" >&2
	exit 2
}
USER=${2:-thingino}
PASS=${3:-thingino}
SECS=${4:-10}

# AAC-LC at 48 kHz is 46.875 frames/s; require at least 90% of that.
MIN_FRAMES=$((SECS * 42))

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

capture() {
	ffmpeg -hide_banner -nostdin -v error -rtsp_transport tcp \
		-i "rtsp://$USER:$PASS@$IP/$1" -t "$SECS" -c copy "$TMP/$1.mkv" -y \
		>/dev/null 2>&1 || true
	[ -s "$TMP/$1.mkv" ] || {
		echo "FAIL: no data from /$1" >&2
		return 1
	}
}

frames() {
	ffprobe -v error -count_frames -select_streams a:0 \
		-show_entries stream=nb_read_frames -of default=nw=1:nk=1 \
		"$TMP/$1.mkv" 2>/dev/null | head -n1
}

gaps() {
	ffprobe -v error -select_streams a:0 -show_entries packet=pts_time \
		-of csv=p=0 "$TMP/$1.mkv" 2>/dev/null |
		awk -F, '$1!=""{if(p!=""){d=$1-p; if(d>0.05) n++} p=$1} END{print n+0}'
}

rc=0
for stream in mic ch0; do
	if ! capture "$stream"; then
		rc=1
		continue
	fi
	n=$(frames "$stream")
	echo "$stream: $n audio frames in ${SECS}s (need >= $MIN_FRAMES)"
	if [ "${n:-0}" -lt "$MIN_FRAMES" ]; then
		echo "FAIL: $stream audio rate too low (half-rate capture?)" >&2
		rc=1
	fi
done

if [ -s "$TMP/ch0.mkv" ]; then
	g=$(gaps ch0)
	echo "ch0: $g audio PTS discontinuities >50ms"
	if [ "${g:-0}" -gt 1 ]; then
		echo "FAIL: ch0 audio timeline has gaps" >&2
		rc=1
	fi
fi

[ "$rc" -eq 0 ] && echo "PASS"
exit "$rc"
