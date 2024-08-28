#!/bin/sh

# Usage: script.sh <channel> <brightness 0-100>

if [ ! -e /dev/pwm ]; then
	echo "Error: /dev/pwm not found. Ensure the PWM device is available by loading the appropriate kernel modules."
	exit 1
fi

if [ "$#" -ne 2 ]; then
	echo "Usage: $0 <channel> <brightness 0-100>"
	exit 1
fi

CHANNEL="$1"
BRIGHTNESS="$2"

if [ "$(echo "$BRIGHTNESS < 0" | bc)" -eq 1 ] || [ "$(echo "$BRIGHTNESS > 100" | bc)" -eq 1 ]; then
	echo "Brightness must be between 0 and 100"
	exit 1
fi

# Define period in nanoseconds
PERIOD_NS=1000000

# Calculate the duty cycle using awk for floating-point arithmetic
DUTY_NS=$(awk -v b="$BRIGHTNESS" 'BEGIN {
	if (b == 0) {
		print 0
	} else if (b <= 10) {
		print b * 1000
	} else {
		print 100000 + (b - 11) * 9000
	}
}')

pwm -c "$CHANNEL" -e -p 1 -P "$PERIOD_NS" -D "$DUTY_NS"

echo "Channel $CHANNEL set to brightness $BRIGHTNESS%, Duty cycle: $DUTY_NS ns"
