#!/bin/sh
http_200() {
  printf 'Status: 200 OK\r\n'
}

json_header() {
  printf 'Content-Type: application/json\r\n'
  printf 'Pragma: no-cache\r\n'
  printf 'Expires: %s\r\n' "$(TZ=GMT0 date +'%a, %d %b %Y %T %Z')"
  printf 'Etag: "%s"\r\n' "$(cat /proc/sys/kernel/random/uuid)"
  printf '\r\n'
}

json_error() {
  http_200
  json_header
  printf '{"code":400,"result":"error","message":"%s"}\n' "$1"
  exit 0
}

json_success() {
  http_200
  json_header
  printf '{"code":200,"result":"success","data":%s}\n' "$1"
  exit 0
}

read_meminfo_value() {
  awk -v key="$1" '$1 == key ":" {print $2; exit}' /proc/meminfo
}

# "timezone":"%s" "$(cat /etc/timezone)"
# "uptime":"%s", "$(awk '{m=$1/60;h=m/60;printf "%sd %sh %sm %ss\n",int(h/24),int(h%24),int(m%60),int($1%60)}' /proc/uptime)"

mem_total=$(read_meminfo_value "MemTotal")
mem_active=$(read_meminfo_value "Active")
mem_buffers=$(read_meminfo_value "Buffers")
mem_cached=$(read_meminfo_value "Cached")
mem_free=$(read_meminfo_value "MemFree")

read_fs_stats() {
  df | awk -v mount="$1" '$NF == mount {print $2" "$3" "$4; exit}'
}

overlay_stats=$(read_fs_stats "/overlay")
extras_stats=$(read_fs_stats "/opt")

set -- $overlay_stats
overlay_total=${1:-0}
overlay_used=${2:-0}
overlay_free=${3:-0}

set -- $extras_stats
extras_total=${1:-0}
extras_used=${2:-0}
extras_free=${3:-0}

payload=$(printf '{"memory":{"total":%d,"active":%d,"buffers":%d,"cached":%d,"free":%d},"overlay":{"total":%d,"used":%d,"free":%d},"extras":{"total":%d,"used":%d,"free":%d},"timestamp":%d}' \
  "${mem_total:-0}" "${mem_active:-0}" "${mem_buffers:-0}" "${mem_cached:-0}" "${mem_free:-0}" \
  "${overlay_total:-0}" "${overlay_used:-0}" "${overlay_free:-0}" \
  "${extras_total:-0}" "${extras_used:-0}" "${extras_free:-0}" "$(date +%s)")

json_success "$payload"
