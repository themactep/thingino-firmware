#!/bin/sh

# Display control options
cat <<EOF
=== CAR CONTROL over COMMAND LINE! ===
CAR: car_control.sh
CAR: car_control.sh constant
CAR: car_control.sh constant low_speed
CAR: car_control.sh low_speed
CAR: w: forward
CAR: d: reverse
CAR: a: turn wheel left
CAR: d: turn wheel right
CAR: q: forward left
CAR: e: forward right
CAR: z: reverse left
CAR: c: reverse right
CAR: x: all stop
CAR: h: headlight on/off
CAR: j: irled on/off
CAR: b: honk

CAR: 1: quit ASAP!

Ready!
EOF

headlight_state=false
irled_state=false

headlight() {
	if [ "$headlight_state" = false ]; then
		printf "\xaa\x55\x43\x04\x1e\x01\x01\x65" > /dev/ttyUSB0
		headlight_state=true
	else
		printf "\xaa\x55\x43\x04\x1e\x02\x01\x66" > /dev/ttyUSB0
		headlight_state=false
	fi
}

irled() {
	if [ "$irled_state" = false ]; then
		cmd irled on
		irled_state=true
	else
		cmd irled off
		irled_state=false
	fi
}

control_c() {
	printf "\xaa\x55\x43\x06\x29\x80\x80\x00\x02\x71" > /dev/ttyUSB0
	echo "control-c KILL"
	pkill -9 -f car_control.sh
}

trap control_c INT

# idle background loop
while true; do
	printf "\xaa\x55\x43\x06\x29\x80\x80\x00\x02\x71" > /dev/ttyUSB0
	# fw sends 0.2
	sleep 0.2
done &

while true; do
	if [ "$1" = "constant" ]; then
		read -r -s -n1 -t 0.05 input
	else
		read -r -s -n1 input
	fi

	case "$input" in
		w)
			if [ "$1" = "low_speed" ] || [ "$2" = "low_speed" ]; then
				printf "\xaa\x55\x43\x06\x29\x80\xca\x00\x02\xbb" > /dev/ttyUSB0
			else
				printf "\xaa\x55\x43\x06\x29\x80\xe3\x00\x02\xd4" > /dev/ttyUSB0
			fi
			;;
		s)
			if [ "$1" = "low_speed" ] || [ "$2" = "low_speed" ]; then
				printf "\xaa\x55\x43\x06\x29\x80\x3b\x00\x02\x2c" > /dev/ttyUSB0
			else
				printf "\xaa\x55\x43\x06\x29\x80\x36\x00\x02\x27" > /dev/ttyUSB0
			fi
			;;
		a)
			printf "\xaa\x55\x43\x06\x29\x76\x81\x00\x02\x68" > /dev/ttyUSB0
			;;
		d)
			printf "\xaa\x55\x43\x06\x29\x8a\x81\x00\x02\x7c" > /dev/ttyUSB0
			;;
		q)
			if [ "$1" = "low_speed" ] || [ "$2" = "low_speed" ]; then
				printf "\xaa\x55\x43\x06\x29\x76\xca\x00\x02\xb1" > /dev/ttyUSB0
			else
				printf "\xaa\x55\x43\x06\x29\x76\xe3\x00\x02\xca" > /dev/ttyUSB0
			fi
			;;
		e)
			if [ "$1" = "low_speed" ] || [ "$2" = "low_speed" ]; then
				printf "\xaa\x55\x43\x06\x29\x8a\xca\x00\x02\xc5" > /dev/ttyUSB0
			else
				printf "\xaa\x55\x43\x06\x29\x8a\xe3\x00\x02\xde" > /dev/ttyUSB0
			fi
			;;
		z)
			if [ "$1" = "low_speed" ] || [ "$2" = "low_speed" ]; then
				printf "\xaa\x55\x43\x06\x29\x76\x3b\x00\x02\x22" > /dev/ttyUSB0
			else
				printf "\xaa\x55\x43\x06\x29\x76\x36\x00\x02\x1d" > /dev/ttyUSB0
			fi
			;;
		c)
			if [ "$1" = "low_speed" ] || [ "$2" = "low_speed" ]; then
				printf "\xaa\x55\x43\x06\x29\x8a\x3b\x00\x02\x36" > /dev/ttyUSB0
			else
				printf "\xaa\x55\x43\x06\x29\x8a\x36\x00\x02\x31" > /dev/ttyUSB0
			fi
			;;
		h)
			headlight
			;;
		j)
			irled
			;;
		x)
			printf "\xaa\x55\x43\x06\x29\x80\x80\x00\x02\x71" > /dev/ttyUSB0
			;;
		b)
			/opt/wz_mini/bin/cmd aplay /opt/wz_mini/usr/share/audio/honk.wav 70 > /dev/null 2>&1 &
			;;
		1)
			printf "\xaa\x55\x43\x06\x29\x80\x80\x00\x02\x71" > /dev/ttyUSB0
			pkill -9 -f car_control.sh
			break
			;;
	esac
done
