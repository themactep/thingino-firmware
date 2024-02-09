#!/bin/bash
#
# GStreamer based video player for glass-on-glass tests.
# Use it with https://thingino.com/timer

protocol="$1"
codec="$2"

show_help_and_exit() {
    echo "Usage: $0 [rtmp|rtsp] [h264|h265] [rtsp://root:root@192.168.1.10:554/stream=0]"
    exit 1
}

case "$protocol" in
    "rtmp")
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
                gst-launch-1.0 -vvv rtspsrc location=${url} ! queue ! \
                rtph264depay ! h264parse ! avdec_h264 ! fpsdisplaysink sync=false name=v
                ;;
            "h265")
                gst-launch-1.0 -vvv rtspsrc location=${url} ! queue ! \
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
esac

exit 0
