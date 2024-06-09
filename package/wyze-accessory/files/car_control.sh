#!/bin/sh

echo "=== CAR CONTROL over COMMAND LINE! ==="
echo "CAR: car_control.sh"
echo "CAR: car_control.sh constant"
echo "CAR: car_control.sh constant low_speed"
echo "CAR: car_control.sh low_speed"
echo "CAR: w: forward "
echo "CAR: d: reverse"
echo "CAR: a: turn wheel left"
echo "CAR: d: turn wheel right"
echo "CAR: q: forward left"
echo "CAR: e: forward right"
echo "CAR: z: reverse left"
echo "CAR: c: reverse right"
echo "CAR: x: all stop"
echo "CAR: h: headlight on/off"
echo "CAR: j: irled on/off"
echo "CAR: b: honk"
echo -e ""
echo "CAR: 1: quit ASAP!"
echo -e ""
echo "Ready!"


headlight_state=false
irled_state=false

function headlight {
if [ "$headlight_state" = false ]; then
	echo -ne "\xaa\x55\x43\x04\x1e\x01\x01\x65" > /dev/ttyUSB0
	headlight_state=true
else
	echo -ne "\xaa\x55\x43\x04\x1e\x02\x01\x66" > /dev/ttyUSB0
	headlight_state=false
fi
}

function irled {
if [ "$irled_state" = false ]; then
	cmd irled on
	irled_state=true
else
	cmd irled off
	irled_state=false
fi
}

trap control_c SIGINT

control_c()
{
	echo -ne "\xaa\x55\x43\x06\x29\x80\x80\x00\x02\x71" > /dev/ttyUSB0
	echo "control-c KILL"
	pkill -9 -f car_control.sh
}

#idle background loop
while true; do
	echo -ne "\xaa\x55\x43\x06\x29\x80\x80\x00\x02\x71" > /dev/ttyUSB0
	#fw sends 0.2
	sleep 0.2
done &

while true; do
	if [ "$1" == "constant" ]; then
		read -s -n1 -t 0.05 input
	else
		read -rsn1 input
	fi

if [ "$input" = "w" ]; then
	#forward
	if [ "$1" == "low_speed" ] || [ "$2" == "low_speed" ]; then
		echo -ne "\xaa\x55\x43\x06\x29\x80\xca\x00\x02\xbb" > /dev/ttyUSB0
	else
		echo -ne "\xaa\x55\x43\x06\x29\x80\xe3\x00\x02\xd4" > /dev/ttyUSB0
	fi

elif [ "$input" = "s" ]; then
	#reverse
	if [ "$1" == "low_speed" ] || [ "$2" == "low_speed" ]; then
		echo -ne "\xaa\x55\x43\x06\x29\x80\x3b\x00\x02\x2c" > /dev/ttyUSB0
	else
		echo -ne "\xaa\x55\x43\x06\x29\x80\x36\x00\x02\x27" > /dev/ttyUSB0
	fi

elif [ "$input" = "a" ]; then
	#left
	echo -ne "\xaa\x55\x43\x06\x29\x76\x81\x00\x02\x68" > /dev/ttyUSB0

elif [ "$input" = "d" ]; then
	#right
	echo -ne "\xaa\x55\x43\x06\x29\x8a\x81\x00\x02\x7c" > /dev/ttyUSB0

elif [ "$input" = "q" ]; then
	#forward left
	if [ "$1" == "low_speed" ] || [ "$2" == "low_speed" ]; then
		echo -ne "\xaa\x55\x43\x06\x29\x76\xca\x00\x02\xb1" > /dev/ttyUSB0
	else
		echo -ne "\xaa\x55\x43\x06\x29\x76\xe3\x00\x02\xca" > /dev/ttyUSB0
	fi

elif [ "$input" = "e" ]; then
	#forward right
	if [ "$1" == "low_speed" ] || [ "$2" == "low_speed" ]; then
		echo -ne "\xaa\x55\x43\x06\x29\x8a\xca\x00\x02\xc5" > /dev/ttyUSB0
	else
		echo -ne "\xaa\x55\x43\x06\x29\x8a\xe3\x00\x02\xde" > /dev/ttyUSB0
	fi

elif [ "$input" = "z" ]; then
	#reverse left
	if [ "$1" == "low_speed" ] || [ "$2" == "low_speed" ]; then
		echo -ne "\xaa\x55\x43\x06\x29\x76\x3b\x00\x02\x22" > /dev/ttyUSB0
	else
		echo -ne "\xaa\x55\x43\x06\x29\x76\x36\x00\x02\x1d" > /dev/ttyUSB0
	fi

elif [ "$input" = "c" ]; then
	#reverse right
	if [ "$1" == "low_speed" ] || [ "$2" == "low_speed" ]; then
		echo -ne "\xaa\x55\x43\x06\x29\x8a\x3b\x00\x02\x36" > /dev/ttyUSB0
	else
		echo -ne "\xaa\x55\x43\x06\x29\x8a\x36\x00\x02\x31" > /dev/ttyUSB0
	fi

elif [ "$input" = "c" ]; then
	echo -ne "\xaa\x55\x43\x06\x29\x80\x80\x00\x02\x71" > /dev/ttyUSB0

elif [ "$input" = "h" ]; then
	headlight

elif [ "$input" = "j" ]; then
	irled

elif [ "$input" = "x" ]; then
	echo -ne "\xaa\x55\x43\x06\x29\x80\x80\x00\x02\x71" > /dev/ttyUSB0

elif [ "$input" = "b" ]; then
	/opt/wz_mini/bin/cmd aplay /opt/wz_mini/usr/share/audio/honk.wav 70 > /dev/null 2>&1 &

elif [ "$input" = "1" ]; then
	#exit
	echo -ne "\xaa\x55\x43\x06\x29\x80\x80\x00\x02\x71" > /dev/ttyUSB0
	pkill -9 -f car_control.sh
	break

    fi
done
