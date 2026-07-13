#!/bin/sh
#
# selfheal.sh - self-healing watchdog for T41NQ thingino cameras.
#
# Two entry points, both driven from cron (see /etc/init.d/S96selfheal):
#   selfheal.sh check             - run every minute: network + daemon health,
#                                   escalating recovery (soft reconnect -> reboot)
#   selfheal.sh reboot-scheduled  - run at 03:00: staggered nightly reboot
#
# Design notes (full rationale in custom/selfheal/SELFHEAL-DESIGN.md):
#  - Network target is the DEFAULT GATEWAY discovered at runtime, not a fixed IP.
#    On this network nothing is reachable without the gateway, so gateway
#    reachability == network up. An empty default route also counts as "down".
#  - Escalation is gentle: soft Wi-Fi recovery first, reboot only after the
#    network has been down long enough that a router reboot (~35 s) or an AP
#    reboot (~1-2 min) would already be over.
#  - Failure counters live in /tmp (tmpfs) so they reset on every boot -> no
#    reboot loops.
#  - Reboot is made reliable: sync -> `reboot -f` -> sysrq force -> (hw watchdog
#    underneath). sysrq is enabled on this kernel (kernel.sysrq=1).
#  - Logging is SD-first, /root-fallback (stops at 200 KB free), syslog always.
#    Heartbeats are suppressed on the /root fallback to spare the NOR flash.
#
# Everything tunable is in the CONFIG block below.

# --------------------------- CONFIG ----------------------------------------
NET_SOFT_FAILS=3         # consecutive 1-min fails -> soft Wi-Fi recovery
NET_HARD_FAILS=10        # consecutive 1-min fails -> reboot
MIN_UPTIME=300           # never reboot within this many seconds of boot (anti-loop; 5 min)

RAPTOR_PROC=rvd          # raptor core video daemon (pidof target)
RAPTOR_INITD=/etc/init.d/S31raptor
RAPTOR_SOFT_FAILS=2      # consecutive fails -> restart raptor
RAPTOR_HARD_FAILS=5      # consecutive fails (restart didn't help) -> reboot
CHECK_RTSP=1             # 1 = also require RTSP :554 to be listening
RTSP_PORT=554
RTSP_GRACE=60            # after rvd (re)starts, :554 is down ~20-30 s - don't enforce
                         # the :554 check until rvd has been up at least this long

PING_WAIT=3              # ping timeout (seconds)

# Logging
SD_MOUNT=/mnt/mmcblk0p1
SD_LOG=$SD_MOUNT/selfheal.log
ROOT_LOG=/root/selfheal.log
SD_MIN_KB=5000           # need > this free on SD to log there (~5 MB)
ROOT_MIN_KB=200          # need > this free on the overlay to log to /root (your rule)
SD_LOG_MAX_KB=5000       # rotate SD log at ~5 MB, keep 3
ROOT_LOG_MAX_KB=64       # rotate /root log at 64 KB, keep 1 (tiny by design)
HEARTBEAT_MIN=60         # heartbeat interval in minutes (SD only)

# Scheduled reboot
REBOOT_STAGGER_MAX=900   # spread the 03:00 reboot over 0..900 s, per-host offset

# Safety: NEVER reboot or act while a firmware flash / maintenance is happening -
# a reboot mid-flash corrupts the NOR and bricks the camera. Two safeguards:
#  - a manual inhibit flag (`selfheal.sh pause` / `resume`), and
#  - auto-detection of in-progress flash tools (below).
# (U-Boot flashing is inherently safe - nothing here is running then.)
INHIBIT_FILE=/tmp/selfheal.inhibit
FLASH_PROCS="sysupgrade flashcp flash_erase flash_eraseall mtd nandwrite ubiformat ubiupdatevol fw_setenv mkfs.jffs2 upgrade"

# State (tmpfs - resets on boot)
S_NETFAIL=/tmp/selfheal.netfail
S_RAPTORFAIL=/tmp/selfheal.raptorfail
S_LASTBEAT=/tmp/selfheal.lastbeat
LOCK=/tmp/selfheal.lock
TAG=selfheal
# ---------------------------------------------------------------------------

now()      { date '+%s'; }
stamp()    { date '+%F %T'; }
uptime_s() { cut -d. -f1 /proc/uptime; }

# --- logging ----------------------------------------------------------------
# Pick a writable log target honouring the space rules; empty = syslog only.
_log_target() {
	if grep -q " $SD_MOUNT " /proc/mounts 2>/dev/null; then
		a=$(df -k "$SD_MOUNT" 2>/dev/null | awk 'NR==2{print $4}')
		[ "${a:-0}" -gt "$SD_MIN_KB" ] && { echo "$SD_LOG"; return; }
	fi
	a=$(df -k /root 2>/dev/null | awk 'NR==2{print $4}')
	[ "${a:-0}" -gt "$ROOT_MIN_KB" ] && { echo "$ROOT_LOG"; return; }
	echo ""
}

_rotate() {
	f=$1; max=$2; keep=$3
	[ -f "$f" ] || return
	sz=$(( $(wc -c < "$f" 2>/dev/null || echo 0) / 1024 ))
	[ "$sz" -lt "$max" ] && return
	i=$keep
	while [ "$i" -gt 1 ]; do mv "$f.$((i-1))" "$f.$i" 2>/dev/null; i=$((i-1)); done
	mv "$f" "$f.1" 2>/dev/null
}

# log <kind> <message>   kind: event | beat
log() {
	kind=$1; shift
	logger -t "$TAG" "$*"                         # syslog (RAM) - always, free
	tgt=$(_log_target)
	[ -z "$tgt" ] && return                        # no disk space anywhere
	# routine heartbeats never touch the flash fallback (wear)
	[ "$kind" = beat ] && [ "$tgt" = "$ROOT_LOG" ] && return
	if [ "$tgt" = "$SD_LOG" ]; then _rotate "$tgt" "$SD_LOG_MAX_KB" 3
	else                            _rotate "$tgt" "$ROOT_LOG_MAX_KB" 1; fi
	echo "$(stamp) [$kind] $*" >> "$tgt" 2>/dev/null
}

# --- safety: flash / maintenance inhibit ------------------------------------
# True (0) when we must NOT touch the system - a reboot mid-flash corrupts the
# NOR and bricks the camera. For the remotely-updated units (reachable only by
# ladder + 12 V, no practical U-Boot access) a network flash from running Linux
# is the ONLY update path, so this guard is what makes that safe. Three
# independent signals so we are protected even if the manual pause is forgotten:
inhibited() {
	# 1. manual flag: `selfheal.sh pause` (or stop)
	[ -f "$INHIBIT_FILE" ] && return 0
	# 2. a known flash tool is running
	for p in $FLASH_PROCS; do
		pidof "$p" >/dev/null 2>&1 && return 0
	done
	# 3. name-INDEPENDENT: some process holds an MTD device open. Every flasher
	#    opens /dev/mtdN (or /dev/mtdblockN) to write it; normal mounted
	#    filesystems are held by the kernel, not a process fd, so this never
	#    false-positives in normal operation. Catches dd, web-UI CGIs, sysupgrade,
	#    custom scripts - anything, regardless of its name. This is the one that
	#    saves you on a firmware update a year from now when nobody remembers.
	for fd in /proc/[0-9]*/fd/*; do
		case "$(readlink "$fd" 2>/dev/null)" in
			/dev/mtd[0-9]*|/dev/mtdblock[0-9]*) return 0 ;;
		esac
	done
	return 1
}

# --- reboot (made reliable) -------------------------------------------------
do_reboot() {
	if inhibited; then
		# RAM-only log: during a flash we must not write to disk either.
		logger -t "$TAG" "REBOOT SUPPRESSED ($1): flash/maintenance in progress"
		return
	fi
	log event "REBOOT: $1"
	sync
	reboot -f                                      # direct syscall, hang-resistant
	sleep 10
	# still alive? graceful path stuck -> force via sysrq (kernel.sysrq=1)
	echo b > /proc/sysrq-trigger 2>/dev/null
	# ...and the hardware watchdog (-T 60) is the final backstop.
}

# --- counters ---------------------------------------------------------------
_get() { cat "$1" 2>/dev/null || echo 0; }
_set() { echo "$2" > "$1"; }

# --- wifi power-save guard ---------------------------------------------------
# Keep 802.11 power-save OFF - it is the root cause of the "camera drops off the
# network" problem (the station dozes, the AP ages it out). The driver re-enables
# PS at (re)association even though rtw_power_mgnt=0, and `iw` is not installed,
# so iwconfig (WEXT) is the lever. Act (and log) ONLY when it has drifted back
# on, so the log reveals whether/how often something re-enables it.
ensure_ps_off() {
	command -v iwconfig >/dev/null 2>&1 || return
	iwconfig wlan0 2>/dev/null | grep -qi 'Power Management:on' || return
	iwconfig wlan0 power off 2>/dev/null
	log event "wifi power-save had drifted ON -> forced off"
}

# --- network health ---------------------------------------------------------
gateway() { ip route show default 2>/dev/null | awk '/default/{print $3; exit}'; }

net_ok() {
	gw=$(gateway)
	[ -z "$gw" ] && return 1                        # no default route = down
	ping -c1 -W "$PING_WAIT" "$gw" >/dev/null 2>&1
}

# Best-effort, smart soft recovery. The 10-min reboot is the guaranteed fix;
# this is the cheap attempt that avoids a reboot when a reconnect suffices.
soft_recover() {
	state=$(wpa_cli -i wlan0 status 2>/dev/null | sed -n 's/^wpa_state=//p')
	if [ "$state" != "COMPLETED" ]; then
		wpa_cli -i wlan0 reconnect >/dev/null 2>&1
		log event "soft: wlan0 not associated (state=${state:-?}) -> reconnect"
	elif ! ip -4 addr show wlan0 2>/dev/null | grep -q 'inet '; then
		kill -USR1 "$(pidof udhcpc)" 2>/dev/null || wpa_cli -i wlan0 reconnect >/dev/null 2>&1
		log event "soft: associated but no IPv4 -> DHCP renew"
	else
		wpa_cli -i wlan0 reconnect >/dev/null 2>&1
		log event "soft: associated+IP but gateway unreachable -> reconnect (likely upstream)"
	fi
	# a re-association may have re-enabled power-save (and fw-ps / turbo-edca);
	# re-apply the full wifi tuning if S95 is present, else at least force PS off.
	if [ -x /etc/init.d/S95wifi-tune ]; then
		/etc/init.d/S95wifi-tune restart >/dev/null 2>&1
	else
		ensure_ps_off
	fi
}

net_check() {
	if net_ok; then
		[ "$(_get $S_NETFAIL)" -ne 0 ] 2>/dev/null && log event "network recovered"
		_set "$S_NETFAIL" 0
		return
	fi
	n=$(( $(_get $S_NETFAIL) + 1 ))
	_set "$S_NETFAIL" "$n"
	log event "network unreachable (fail=$n, gw='$(gateway)')"

	[ "$n" -eq "$NET_SOFT_FAILS" ] && soft_recover

	if [ "$n" -ge "$NET_HARD_FAILS" ] && [ "$(uptime_s)" -gt "$MIN_UPTIME" ]; then
		do_reboot "network down ${n} min"
	fi
}

# --- raptor / streaming health ---------------------------------------------
# Seconds since process $1 started (field 22 of /proc/PID/stat is starttime in
# clock ticks; HZ=100 on this Ingenic 4.4.94 kernel). Big number if it's gone.
proc_age() {
	st=$(awk '{print $22}' /proc/"$1"/stat 2>/dev/null)
	[ -z "$st" ] && { echo 999999; return; }
	echo $(( $(cut -d. -f1 /proc/uptime) - st / 100 ))
}

raptor_alive() {
	pid=$(pidof "$RAPTOR_PROC" 2>/dev/null | cut -d' ' -f1)
	[ -z "$pid" ] && return 1                      # process gone = dead
	# Enforce the RTSP-listening check only if (a) netstat exists and (b) rvd has
	# been up longer than the startup grace - during the first ~20-30 s after a
	# (re)start rvd is alive but :554 is not listening yet, which is NOT a fault.
	if [ "$CHECK_RTSP" = 1 ] && command -v netstat >/dev/null 2>&1 \
	   && [ "$(proc_age "$pid")" -ge "$RTSP_GRACE" ]; then
		netstat -ltn 2>/dev/null | grep -q ":$RTSP_PORT " || return 1
	fi
	return 0
}

raptor_check() {
	if raptor_alive; then
		[ "$(_get $S_RAPTORFAIL)" -ne 0 ] 2>/dev/null && log event "raptor recovered"
		_set "$S_RAPTORFAIL" 0
		return
	fi
	n=$(( $(_get $S_RAPTORFAIL) + 1 ))
	_set "$S_RAPTORFAIL" "$n"
	log event "raptor ($RAPTOR_PROC) not healthy (fail=$n)"

	[ "$n" -eq "$RAPTOR_SOFT_FAILS" ] && {
		log event "restarting raptor"
		"$RAPTOR_INITD" restart >/dev/null 2>&1
	}

	if [ "$n" -ge "$RAPTOR_HARD_FAILS" ] && [ "$(uptime_s)" -gt "$MIN_UPTIME" ]; then
		do_reboot "raptor dead ${n} min"
	fi
}

# --- heartbeat --------------------------------------------------------------
heartbeat() {
	last=$(_get $S_LASTBEAT)
	t=$(now)
	[ $(( t - last )) -lt $(( HEARTBEAT_MIN * 60 )) ] && return
	_set "$S_LASTBEAT" "$t"
	rssi=$(awk 'NR==3{gsub(/\./,"",$4); print $4}' /proc/net/wireless 2>/dev/null)
	load=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null)
	log beat "alive up=$(uptime_s)s load=${load:-?} gw=$(gateway) rssi=${rssi:-?}dBm"
}

# --- lock (avoid overlapping cron runs; stale-safe) -------------------------
acquire_lock() {
	if mkdir "$LOCK" 2>/dev/null; then
		trap 'rmdir "$LOCK" 2>/dev/null' EXIT
		return 0
	fi
	# stale? (older than 5 min) -> steal it
	if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +5 2>/dev/null)" ]; then
		rmdir "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null
		trap 'rmdir "$LOCK" 2>/dev/null' EXIT
		return 0
	fi
	return 1
}

# --- dispatch ---------------------------------------------------------------
case "$1" in
	check)
		acquire_lock || exit 0
		if inhibited; then
			# fully passive during a flash/maintenance; RAM-only log, no disk I/O
			logger -t "$TAG" "paused: flash/maintenance in progress"
			exit 0
		fi
		ensure_ps_off      # root-cause guard: keep 802.11 PS off (before the ping)
		net_check
		raptor_check
		heartbeat
		;;
	reboot-scheduled)
		if inhibited; then
			logger -t "$TAG" "scheduled reboot skipped: flash/maintenance in progress"
			exit 0
		fi
		# deterministic per-host offset (no RNG -> no collision when all cameras
		# boot together after a power cut). Same hostname -> same offset.
		off=$(( 0x$(hostname | md5sum | cut -c1-4) % REBOOT_STAGGER_MAX ))
		log event "scheduled reboot in ${off}s (staggered)"
		sleep "$off"
		do_reboot "scheduled 03:00"   # re-checks inhibit after the sleep, too
		;;
	pause|stop)
		# call this before flashing over the network / any maintenance
		touch "$INHIBIT_FILE"
		logger -t "$TAG" "watchdog PAUSED by request ($INHIBIT_FILE)"
		echo "self-heal PAUSED - reboots and recovery actions inhibited."
		echo "run '$0 resume' when done (or just reboot; the flag is in tmpfs)."
		;;
	resume|start)
		rm -f "$INHIBIT_FILE"
		logger -t "$TAG" "watchdog RESUMED by request"
		echo "self-heal resumed."
		;;
	status)
		if inhibited; then
			echo "PAUSED (flash/maintenance detected or manual pause)"
		else
			echo "active"
		fi
		;;
	*)
		echo "Usage: $0 {check|reboot-scheduled|pause|resume|status}"
		echo "  pause|stop     inhibit all reboots/actions (before flashing)"
		echo "  resume|start   clear the inhibit"
		echo "  status         show whether the watchdog is active or paused"
		exit 1
		;;
esac
