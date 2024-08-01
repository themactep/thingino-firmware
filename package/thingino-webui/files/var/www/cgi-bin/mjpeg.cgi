#!/bin/sh
preview=/tmp/snapshot.jpg
frame="--frame\r\nContent-Type: image/jpeg\r\n"
endofheader="\r\n"
echo "HTTP/1.1 200 OK
Content-Type: multipart/x-mixed-replace; boundary=frame
Cache-Control: no-cache
Pragma: no-cache
Connection: close
"

while :; do
	echo -n -e $frame
	echo -n -e "Content-Length: "$(stat -c %s ${preview})"\r\n"
	echo -n -e $endofheader
	cat $preview
	sleep 1
done
