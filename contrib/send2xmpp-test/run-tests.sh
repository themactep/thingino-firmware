#!/bin/sh
# Exercise package/send2xmpp/files/send2xmpp against the local BOSH test
# server.  The double-quote case is the Openfire 5.x regression from #1985;
# the single-quote case keeps the older Prosody-style path covered.
set -u

BOSH_URL="${BOSH_URL:-http://bosh:5280/http-bind}"
SERVER="http://bosh:5280"
SCRIPT="/scripts/send2xmpp"
rc=0

pass() { echo "PASS: $*"; }
bad() {
	echo "FAIL: $*"
	rc=1
}

wait_for_bosh() {
	i=0
	while [ "$i" -lt 60 ]; do
		if curl -sf "$SERVER/health" >/dev/null 2>&1; then
			return 0
		fi
		i=$((i + 1))
		sleep 1
	done
	return 1
}

json_has() {
	# $1 = JSON, $2 = fixed string
	printf '%s' "$1" | grep -qF "$2"
}

if ! wait_for_bosh; then
	echo "FAIL: BOSH test server did not become ready"
	exit 1
fi

# 1x1 JPEG, enough for the upload path.
printf '\xff\xd8\xff\xe0\x00\x10\x4a\x46\x49\x46\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xdb\x00\x43\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\x09\x09\x08\x0a\x0c\x14\x0d\x0c\x0b\x0b\x0c\x19\x12\x13\x0f\x14\x1d\x1a\x1f\x1e\x1d\x1a\x1c\x1c\x20\x24\x2e\x27\x20\x22\x2c\x23\x1c\x1c\x28\x37\x29\x2c\x30\x31\x34\x34\x34\x1f\x27\x39\x3d\x38\x32\x3c\x2e\x33\x34\x32\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00\xff\xc4\x00\x14\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xc4\x00\x14\x10\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00\x7f\xff\xd9' >/tmp/test.jpg

for style in double single; do
	echo "== attribute style: $style"
	curl -sf "$SERVER/reset" >/dev/null
	XMPP_BOSH_URL="$BOSH_URL?style=$style"
	export XMPP_BOSH_URL

	msg="text $style openfire-style"
	if sh "$SCRIPT" -m "$msg"; then
		pass "text $style delivery"
	else
		bad "text $style delivery"
	fi
	body=$(curl -sf "$SERVER/messages")
	if json_has "$body" "$msg"; then
		pass "text $style received by server"
	else
		bad "text $style received by server ($body)"
	fi

	curl -sf "$SERVER/reset" >/dev/null
	if sh "$SCRIPT" -i /tmp/test.jpg -m "image $style"; then
		pass "image $style delivery"
	else
		bad "image $style delivery"
	fi
	body=$(curl -sf "$SERVER/messages")
	uploads=$(curl -sf "$SERVER/uploads")
	if json_has "$body" "upload/get"; then
		pass "image $style message carries upload URL"
	else
		bad "image $style message carries upload URL ($body)"
	fi
	if json_has "$uploads" '"size":'; then
		pass "image $style bytes uploaded"
	else
		bad "image $style bytes uploaded ($uploads)"
	fi
done

# XML escaping on a message body, independent of the attribute style.
curl -sf "$SERVER/reset" >/dev/null
XMPP_BOSH_URL="$BOSH_URL?style=double"
export XMPP_BOSH_URL
msg='special & < > " test'
if sh "$SCRIPT" -m "$msg"; then
	pass "escaped message delivery"
else
	bad "escaped message delivery"
fi
body=$(curl -sf "$SERVER/messages")
if json_has "$body" 'special & < >'; then
	pass "escaped message decoded by server"
else
	bad "escaped message decoded by server ($body)"
fi

echo
if [ "$rc" -eq 0 ]; then
	echo "All send2xmpp tests passed."
else
	echo "send2xmpp tests failed."
fi
exit "$rc"
