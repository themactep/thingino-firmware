#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-cache\r\n'
printf 'Connection: close\r\n'
printf '\r\n'

SENSOR_MODEL=$(cat /proc/jz/sensor/name 2>/dev/null)
SOC_MODEL=$(soc -m 2>/dev/null)
SOC_FAMILY=$(soc -f 2>/dev/null)

SENSOR_IQ_PATH="/etc/sensor"
SENSOR_IQ_FILE="${SENSOR_MODEL}-${SOC_MODEL}.bin"
SENSOR_FILE_FULL_PATH="${SENSOR_IQ_PATH}/${SENSOR_IQ_FILE}"

if [ -f "$SENSOR_FILE_FULL_PATH" ]; then
  FILE_MD5=$(md5sum "$SENSOR_FILE_FULL_PATH" 2>/dev/null | cut -d' ' -f1)
  if [ -z "$FILE_MD5" ]; then
    FILE_MD5="Unknown"
  fi
else
  FILE_MD5="File not found"
fi

cat << EOF
{
  "sensor_model": "$SENSOR_MODEL",
  "soc_model": "$SOC_MODEL",
  "soc_family": "$SOC_FAMILY",
  "file_path": "$SENSOR_FILE_FULL_PATH",
  "md5": "$FILE_MD5"
}
EOF
