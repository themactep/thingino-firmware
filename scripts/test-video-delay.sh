#!/bin/bash
#
# GStreamer based script for glass-to-glass latency testing.
# Use it together with https://thingino.com/timer
#
# 2023, Paul Philippov <paul@themactep.com>
# 2024-07-15: Rewrite for easier use.

if ! command -v gst-launch-1.0 > /dev/null; then
	echo "This script requires GStreamer."
	echo "Please run \"sudo apt install gstreamer1.0-tools gstreamer1.0-plugins-bad gstreamer1.0-libav\" first, then re-run this script."
	exit 1
fi

show_help_and_exit() {
	echo "Usage: $0 <rtsp://thingino:thingino@192.168.1.10:554/ch0> [h264|h265]"
	exit 1
}

url="$1"
[ -z "$url" ] && show_help_and_exit

codec="$2"
case "$codec" in
	"h265")
		gst-launch-1.0 -vvv rtspsrc location=$url ! queue ! \
			rtph265depay ! h265parse ! avdec_h265 ! fpsdisplaysink sync=false name=v
		;;
	"h264"|"")
		gst-launch-1.0 -vvv rtspsrc location=$url ! queue ! \
			rtph264depay ! h264parse ! avdec_h264 ! fpsdisplaysink sync=false name=v
		;;
	*)
		echo "Unknown codec"
		show_help_and_exit
		;;
esac

exit 0
