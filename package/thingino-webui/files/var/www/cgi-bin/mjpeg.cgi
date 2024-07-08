#!/bin/sh
preview=/tmp/snapshot.jpg
frame="--frame\r\nContent-Type: image/jpeg\r\n\r\n"
echo "HTTP/1.1 200 OK
Content-Type: multipart/x-mixed-replace; boundary=frame
Pragma: no-cache
Connecton: close
"

echo -n -e $frame
cat $preview
echo -n -e $frame
while :; do
	cat $preview
	echo -n -e "\r\n\r\n"
	echo -n -e $frame
	sleep 1
done
