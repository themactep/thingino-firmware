#!/bin/sh
# shellcheck disable=SC1091
# Sensor IQ binary upload for raptor images (replaces prudynt-only preview.cgi).

. /var/www/x/auth.sh
require_auth

SENSOR_IQ_PATH="/etc/sensor"
SENSOR_IQ_UPLOAD_PATH="/opt/sensor"
SENSOR_MODEL=$(cat /proc/jz/sensor/sensor0/name 2>/dev/null || cat /proc/jz/sensor/name 2>/dev/null)
SOC_MODEL=$(soc -f 2>/dev/null)
SENSOR_IQ_FILE="${SENSOR_MODEL}-${SOC_MODEL}.bin"
UPLOADED_SENSOR_IQ_FILE="${SENSOR_IQ_UPLOAD_PATH}/uploaded.bin"

send_redirect() {
	printf 'Status: 303 See Other\r\n'
	printf 'Location: %s\r\n' "$1"
	printf 'Cache-Control: no-store\r\n'
	printf 'Connection: close\r\n\r\n'
	exit 0
}

send_error() {
	printf 'Status: %s\r\n' "$1"
	printf 'Content-Type: text/plain\r\n'
	printf 'Cache-Control: no-store\r\n'
	printf 'Connection: close\r\n\r\n'
	printf '%s\n' "$2"
	exit 1
}

extract_part_value() {
	awk -v RS='\r\n\r\n' -v target="$2" '
    NR == target {
      sub(/\r\n--.*/, "", $0)
      gsub(/[\r\n]/, "", $0)
      print
      exit
    }
  ' "$1"
}

extract_upload_payload() {
	request_file=$1
	output_file=$2
	part_index=$3
	trailer=$(printf '\r\n--%s--\r\n' "$BOUNDARY" | wc -c | tr -d '[:space:]') || return 1
	start_offset=$(awk -v RS='\r\n\r\n' -v target="$part_index" '
    { offset += length($0) + 4 }
    NR == target - 1 { print offset; exit }
  ' "$request_file") || return 1
	total_size=$(wc -c <"$request_file" | tr -d '[:space:]') || return 1
	case "$start_offset" in '' | *[!0-9]*) return 1 ;; esac
	case "$total_size" in '' | *[!0-9]*) return 1 ;; esac
	case "$trailer" in '' | *[!0-9]*) return 1 ;; esac
	payload_size=$((total_size - start_offset - trailer))
	[ "$payload_size" -gt 0 ] 2>/dev/null || return 1
	dd if="$request_file" of="$output_file" bs=1 skip="$start_offset" count="$payload_size" 2>/dev/null || return 1
	[ -s "$output_file" ] || return 1
}

case "${REQUEST_METHOD:-GET}" in
	POST) ;;
	*) send_error '405 Method Not Allowed' 'Method not allowed.' ;;
esac

case "${CONTENT_TYPE:-}" in
	multipart/form-data*)
		BOUNDARY=$(printf '%s' "$CONTENT_TYPE" | sed -n 's/.*boundary=//p')
		BOUNDARY=${BOUNDARY%%;*}
		BOUNDARY=${BOUNDARY%\"}
		BOUNDARY=${BOUNDARY#\"}
		[ -n "$BOUNDARY" ] || send_error '400 Bad Request' 'Missing multipart boundary.'
		;;
	*) send_error '415 Unsupported Media Type' 'Unsupported content type.' ;;
esac

case "${CONTENT_LENGTH:-}" in
	'' | *[!0-9]*) send_error '411 Length Required' 'Invalid content length.' ;;
esac
[ "$CONTENT_LENGTH" -gt 0 ] 2>/dev/null || send_error '411 Length Required' 'Empty upload payload.'

REQUEST_FILE=$(mktemp /tmp/sensor-upload.XXXXXX) || send_error '500 Internal Server Error' 'Unable to allocate request buffer.'
UPLOAD_FILE=$(mktemp /tmp/sensor-file.XXXXXX) || {
	rm -f "$REQUEST_FILE"
	send_error '500 Internal Server Error' 'Unable to allocate upload buffer.'
}
trap 'rm -f "$REQUEST_FILE" "$UPLOAD_FILE"' EXIT INT TERM

dd bs=1 count="$CONTENT_LENGTH" of="$REQUEST_FILE" 2>/dev/null ||
	send_error '500 Internal Server Error' 'Failed to read upload payload.'

UPLOAD_FORM=$(extract_part_value "$REQUEST_FILE" 2)
[ "$UPLOAD_FORM" = sensor ] || send_error '400 Bad Request' 'Unsupported upload form.'

extract_upload_payload "$REQUEST_FILE" "$UPLOAD_FILE" 3 ||
	send_error '400 Bad Request' 'Failed to extract uploaded file.'

mkdir -p "$SENSOR_IQ_UPLOAD_PATH" "$SENSOR_IQ_PATH" ||
	send_error '500 Internal Server Error' 'Failed to create sensor directories.'
mv "$UPLOAD_FILE" "$UPLOADED_SENSOR_IQ_FILE" ||
	send_error '500 Internal Server Error' 'Failed to install sensor IQ file.'
UPLOAD_FILE=""
ln -sf "$UPLOADED_SENSOR_IQ_FILE" "$SENSOR_IQ_PATH/$SENSOR_IQ_FILE" ||
	send_error '500 Internal Server Error' 'Failed to link sensor IQ file.'

if [ -x /etc/init.d/S31raptor ]; then
	/etc/init.d/S31raptor restart >/dev/null 2>&1 &
fi

send_redirect '/streamer-sensor.html'
