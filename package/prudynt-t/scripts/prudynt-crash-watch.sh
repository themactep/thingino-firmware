#!/bin/sh
set -eu

NFS_SERVER="${NFS_SERVER:-192.168.88.20:/nfs}"
CAPTURE_ROOT="${CAPTURE_ROOT:-/tmp/prudynt-capture}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CAMERA_DIR="$(basename "$(dirname "$(dirname "$SCRIPT_DIR")")")"

if [ -d "/mnt/nfs/$CAMERA_DIR" ]; then
    NFS_MOUNT="/mnt/nfs"
elif [ -d "/nfs/$CAMERA_DIR" ]; then
    NFS_MOUNT="/nfs"
else
    NFS_MOUNT="/nfs"
fi

BIN="$NFS_MOUNT/$CAMERA_DIR/usr/bin/prudynt-debug"

TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$CAPTURE_ROOT/$TS"
RUN_LOG="$OUT_DIR/prudynt-stdout.log"
MON_LOG="$OUT_DIR/monitor.log"

mkdir -p "$OUT_DIR"

echo "[$(date)] crash watch start" | tee -a "$MON_LOG"
echo "[$(date)] camera=$CAMERA_DIR mount=$NFS_MOUNT" | tee -a "$MON_LOG"

if [ ! -d "$NFS_MOUNT" ]; then
    mkdir -p "$NFS_MOUNT"
fi

if [ ! -x "$BIN" ]; then
    mount | grep " $NFS_MOUNT " >/dev/null 2>&1 || mount -t nfs -o nolock "$NFS_SERVER" "$NFS_MOUNT"
fi

if [ ! -x "$BIN" ]; then
    echo "[$(date)] ERROR: missing binary: $BIN" | tee -a "$MON_LOG"
    exit 1
fi

killall gdbserver 2>/dev/null || true
killall prudynt-debug 2>/dev/null || true
/etc/init.d/S31prudynt stop 2>/dev/null || true
killall prudynt 2>/dev/null || true
rm -f /tmp/prudynt_crash.log

echo "[$(date)] launching $BIN" | tee -a "$MON_LOG"
"$BIN" >"$RUN_LOG" 2>&1 &
APP_PID=$!
echo "$APP_PID" > "$OUT_DIR/pid"
echo "[$(date)] pid=$APP_PID" | tee -a "$MON_LOG"

(
    index=0
    while kill -0 "$APP_PID" 2>/dev/null; do
        index=$((index + 1))
        SNAP="$OUT_DIR/snap-$index"
        mkdir -p "$SNAP"

        cat "/proc/$APP_PID/maps" > "$SNAP/maps" 2>/dev/null || true
        cat "/proc/$APP_PID/status" > "$SNAP/status" 2>/dev/null || true
        cat "/proc/$APP_PID/stat" > "$SNAP/stat" 2>/dev/null || true
        cat "/proc/$APP_PID/stack" > "$SNAP/main.stack" 2>/dev/null || true

        for thread_dir in /proc/$APP_PID/task/*; do
            [ -d "$thread_dir" ] || continue
            tid="$(basename "$thread_dir")"
            cat "$thread_dir/stack" > "$SNAP/thread-$tid.stack" 2>/dev/null || true
        done

        ln -sfn "$SNAP" "$OUT_DIR/latest"
        sleep 1
    done
) &
MONITOR_PID=$!

wait "$APP_PID"
RC=$?

kill "$MONITOR_PID" 2>/dev/null || true
wait "$MONITOR_PID" 2>/dev/null || true

echo "$RC" > "$OUT_DIR/exit_code"
echo "[$(date)] prudynt exit code=$RC" | tee -a "$MON_LOG"

if [ -f /tmp/prudynt_crash.log ]; then
    cp /tmp/prudynt_crash.log "$OUT_DIR/prudynt_crash.log"
    echo "[$(date)] copied /tmp/prudynt_crash.log" | tee -a "$MON_LOG"
fi

dmesg | tail -n 200 > "$OUT_DIR/dmesg-tail.log" 2>/dev/null || true
echo "[$(date)] artifacts: $OUT_DIR" | tee -a "$MON_LOG"
