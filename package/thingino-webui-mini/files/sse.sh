#!/bin/sh
# BusyBox httpd CGI script emitting Server-Sent Events (SSE)
# Streams CPU usage (%) and load averages from /proc.
# Place in document_root/cgi-bin/sse.sh and make executable: chmod 755 cgi-bin/sse.sh
# Start server (example): busybox httpd -f -p 8080 -h .

# Exit cleanly if client disconnects
trap 'exit 0' INT TERM PIPE

# CGI headers for SSE
# Note: BusyBox httpd is HTTP/1.0 without keep-alive; SSE still works by keeping process alive
# and sending a continuous stream.
echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo "Connection: keep-alive"
# Allow cross-origin for convenience; adjust as needed
echo "Access-Control-Allow-Origin: *"
# Optional: reconnection time hint for clients (in ms)
echo
printf 'retry: 2000\n\n'

cpu_percent() {
  # Compute CPU usage percentage using two snapshots from /proc/stat
  # Returns an integer 0..100
  # Read first snapshot
  read stat1 < /proc/stat || return 0
  # shellcheck disable=SC2086
  set -- $stat1
  # Fields: cpu user nice system idle iowait irq softirq steal guest guest_nice
  u1=$2; n1=$3; s1=$4; i1=$5; w1=$6; ir1=$7; si1=$8; st1=${9:-0}
  sleep 1
  read stat2 < /proc/stat || echo 0
  set -- $stat2
  u2=$2; n2=$3; s2=$4; i2=$5; w2=$6; ir2=$7; si2=$8; st2=${9:-0}
  total1=$((u1+n1+s1+i1+w1+ir1+si1+st1))
  total2=$((u2+n2+s2+i2+w2+ir2+si2+st2))
  idle1=$((i1+w1))
  idle2=$((i2+w2))
  dt=$((total2-total1))
  di=$((idle2-idle1))
  if [ "$dt" -gt 0 ] 2>/dev/null; then
    echo $(((100*(dt - di))/dt))
  else
    echo 0
  fi
}

while :; do
  # Gather metrics
  CPU=$(cpu_percent)
  # /proc/loadavg: 1min 5min 15min running/threads lastpid
  if read L1 L5 L15 _ < /proc/loadavg; then
    :
  else
    L1=0; L5=0; L15=0
  fi

  # Emit an SSE event with JSON payload
  echo "event: metrics" 2>/dev/null || exit 0
  # Use printf to avoid locale issues; values are numbers (no quotes)
  printf 'data: {"cpu":%s,"load1":%s,"load5":%s,"load15":%s}\n\n' "$CPU" "$L1" "$L5" "$L15" 2>/dev/null || exit 0

  # Pace the loop. cpu_percent already sleeps 1s, so a small extra delay is enough
  sleep 0.2 2>/dev/null || sleep 1
done

