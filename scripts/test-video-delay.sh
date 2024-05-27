#!/bin/bash
#
# GStreamer based script for glass-to-glass latency testing.
# Use it together with https://thingino.com/timer
#
# 2023, Paul Philippov <paul@themactep.com>
#

if ! command -v gst-launch-1.0 > /dev/null; then
	echo "This script requires GStreamer."
	echo "Please run \"sudo apt install gstreamer1.0-tools gstreamer1.0-plugins-bad gstreamer1.0-libav\" first, then re-run this script."
	exit 1
fi

protocol="$1"
codec="$2"

show_help_and_exit() {
	echo "Usage: $0 [rtmp|rtsp] [h264|h265] [rtsp://thingino:thingino@192.168.1.10:554/ch0]"
	exit 1
}

case "$protocol" in
	"rtmp")
		echo "This only works with OpenIPC, not Thingino!"
		case "$codec" in
			"h265")
				gst-launch-1.0 -vvv udpsrc port=5600 \
					caps='application/x-rtp, media=(string)video, clock-rate=(int)90000, encoding-name=(string)H265' \
					! rtpjitterbuffer ! rtph265depay ! avdec_h265 ! glimagesink sync=false
				;;
			"h264")
				gst-launch-1.0 -vvv udpsrc port=5600 \
					caps='application/x-rtp, media=(string)video, clock-rate=(int)90000, encoding-name=(string)H264' \
					! rtpjitterbuffer ! rtph264depay ! avdec_h264 ! glimagesink sync=false
				;;
			*)
				echo "Unknown codec"
				exit 1
				;;
		esac
		echo "Add these lines to /etc/majestic.yaml:"
		echo "outgoing:"
		echo "  - udp://$(hostname -I | awk '{print $1}'):5600"
		;;
	"rtsp")
		url="$3"
		[ -z "$url" ] && show_help_and_exit
		case "$codec" in
			"h264")
				gst-launch-1.0 -vvv rtspsrc location=$url ! queue ! \
					rtph264depay ! h264parse ! avdec_h264 ! fpsdisplaysink sync=false name=v
				;;
			"h265")
				gst-launch-1.0 -vvv rtspsrc location=$url ! queue ! \
					rtph265depay ! h265parse ! avdec_h265 ! fpsdisplaysink sync=false name=v
				;;
			*)
				echo "Unknown codec"
				show_help_and_exit
				;;
		esac
		;;
	*)
		echo "Unknown protocol"
		show_help_and_exit
		;;
esac

exit 0
