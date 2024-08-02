#!/bin/sh
echo "HTTP/1.1 200 OK
Content-Type: multipart/x-mixed-replace; boundary=frame
Cache-Control: no-cache
Pragma: no-cache
Connection: close
"
file=/tmp/snapshot.jpg
while :; do
	inode=$(stat -c%i $file)
	[ "$inode" = "$inode_old" ] && continue
	inode_old=$inode
	mjpeg_frame $file frame || exit
	sleep 0.5
done
