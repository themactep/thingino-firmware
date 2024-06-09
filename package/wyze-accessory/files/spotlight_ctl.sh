#!/bin/sh

if [[ "$1" == "on_high" ]]; then
	echo -ne "\xaa\x55\x43\x05\x16\xff\x07\x02\x63" > /dev/ttyUSB0
elif [[ "$1" == "on_low" ]]; then
	echo -ne "\xaa\x55\x43\x05\x16\x33\x07\x01\x97" > /dev/ttyUSB0
elif [[ "$1" == "off" ]]; then
	echo -ne "\xaa\x55\x43\x05\x16\x00\x07\x01\x64" > /dev/ttyUSB0
else
	echo "usage: spotlight_ctl on_high"
	echo "usage: spotlight_ctl on_low"
	echo "usage: spotlight_ctl off"
fi
