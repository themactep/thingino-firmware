#!/bin/sh

. /etc/init.d/rc.common

ENABLED=false
INTERVAL=60
RTSP_URL="rtsp://thingino:thingino@127.0.0.1/ch0"
RETRY_COUNT=3            # Number of retries before declaring the stream down
RETRY_DELAY=10           # Delay in seconds between retry attempts
RESTART_LIMIT=3          # Maximum number of restarts before alerting
RESTART_DELAY=10         # Delay in seconds between restarts
RESTART_COUNT=0
PID_FILE="/run/rtsp_watchdog.pid"  # PID file to store the background process ID

# Handle signals
trap 'echo "Stream Watchdog: Stopping watchdog..."; cleanup; exit 0' INT TERM

cleanup() {
	# Kill any background processes and cleanup resources
	[ -n "$PID" ] && kill $PID
}

watch() {
	while true; do
		SUCCESS=false

		for i in $(seq 1 $RETRY_COUNT); do
			openRTSP -v -V -d 5 -t "$RTSP_URL" > /dev/null 2>&1 &
			PID=$!

			wait $PID
			if [ $? -eq 0 ]; then
				echo "Stream Watchdog: Stream stream is active."
				SUCCESS=true
				RESTART_COUNT=0  # Reset the restart count after a successful check
				break
			else
				echo "Stream Watchdog: Attempt $i failed. Retrying in $RETRY_DELAY seconds..."
				sleep $RETRY_DELAY  # Delay before retrying
			fi
		done

		if ! $SUCCESS; then
			echo "Stream Watchdog: Stream stream is down, restarting server..."
			service restart prudynt

			RESTART_COUNT=$((RESTART_COUNT+1))

			# Delay before checking the stream again after a restart
			echo "Stream Watchdog: Waiting $RESTART_DELAY seconds before rechecking..."
			sleep $RESTART_DELAY

			if [ $RESTART_COUNT -ge $RESTART_LIMIT ]; then
				echo "Stream Watchdog: Restart limit reached, noting to log..."
				# ALERT!
				RESTART_COUNT=0  # Reset the count after escalation
			fi
		fi

		# Sleep for a defined interval before the next full check cycle
		sleep $INTERVAL
	done
}

start() {
	starting
	is_streamer_disabled && quit "Streamer disabled"
	watch &
	echo $! > "$PID_FILE"  # Store the PID of the background process
}

stop() {
	stopping
	if [ -f "$PID_FILE" ]; then
		PID=$(cat "$PID_FILE")
		if kill -0 "$PID" 2>/dev/null; then
			kill "$PID"
			echo "Stream Watchdog: Watchdog process stopped."
			rm -f "$PID_FILE"  # Clean up the PID file
		else
			echo "Stream Watchdog: No running watchdog process found."
		fi
	else
		echo "Stream Watchdog: PID file not found."
	fi
}

case "$1" in
	start)
		start
		;;
	stop)
		stop
		;;
	restart)
		stop
		sleep 1
		start
		;;
	*)
		echo "Usage: $0 {start|stop|restart}"
		exit 1
		;;
esac

exit 0
