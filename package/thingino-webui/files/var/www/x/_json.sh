http_200() {
	echo "HTTP/1.1 200 OK"
}

http_400() {
	echo "HTTP/1.1 400 Bad Request"
}

http_412() {
	echo "HTTP/1.1 412 OK"
}

json_header() {
	echo "Content-type: application/json
Pragma: no-cache
Expires: $(TZ=GMT0 date +'%a, %d %b %Y %T %Z')
Etag: \"$(cat /proc/sys/kernel/random/uuid)\"
"
}

json_error() {
	http_412
	json_header
	echo "{\"error\":{\"code\":412,\"message\":\"$1\"}}"
	exit 0
}

json_ok() {
	http_200
	json_header
	echo "{\"code\":200,\"result\":\"success\",\"message\":$1}"
	exit 0
}
