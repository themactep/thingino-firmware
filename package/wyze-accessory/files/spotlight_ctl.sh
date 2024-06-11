#!/bin/sh

case "$1" in
	"on_high")
		printf "\xaa\x55\x43\x05\x16\xff\x07\x02\x63" > /dev/ttyUSB0
		;;
	"on_low")
		printf "\xaa\x55\x43\x05\x16\x33\x07\x01\x97" > /dev/ttyUSB0
		;;
	"off")
		printf "\xaa\x55\x43\x05\x16\x00\x07\x01\x64" > /dev/ttyUSB0
		;;
	*)
		echo "usage: spotlight_ctl on_high"
		echo "usage: spotlight_ctl on_low"
		echo "usage: spotlight_ctl off"
		;;
esac
