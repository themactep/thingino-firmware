#!/bin/sh
# Check that every TZ string in tz.json parses with the target libc.
#
# Thingino ships uClibc-ng, whose tzset() (libc/misc/time/time.c) is stricter
# than glibc and musl. A string it cannot parse is dropped as a whole and the
# process runs in UTC. Its limits, mirrored below:
#   - zone names: 3 to 6 characters, letters only unless quoted in <...>
#   - rule times after '/': no sign, hours 0-24 (POSIX allows -167..167)
#   - the string must fit /etc/TZ's 68-byte read buffer with its newline
# The POSIX month (1-12) and week (1-5) limits are checked too.
#
# Usage: scripts/check-tz-json.sh [FILE]   (default: overlay/usr/share/tz.json)

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILE="${1:-$SCRIPT_DIR/../overlay/usr/share/tz.json}"

if [ ! -f "$FILE" ]; then
	echo "ERROR: $FILE not found" >&2
	exit 1
fi

tr '{' '\n' <"$FILE" | awk '
function fail(why) {
	printf "check-tz-json: %s: \"%s\": %s\n", name, val, why
	bad++
	return 0
}
function isdigit(c) { return c ~ /^[0-9]$/ }
function isalpha(c) { return c ~ /^[A-Za-z]$/ }
# hh[:mm[:ss]], hours below 25, minutes and seconds below 60, no sign;
# the same four passes as uClibc-ng getoffset() (the last one takes ":0")
function offset(    i, lim, f, d) {
	split("25 60 60 1", lim, " ")
	f = -1
	for (i = 1; i <= 4; i++) {
		d = 0
		while (d < 2 && isdigit(substr(s, p, 1))) {
			f = (d ? f * 10 : 0) + substr(s, p, 1)
			p++; d++
		}
		if (f < 0 || f >= lim[i]) return 0
		f = 0
		if (substr(s, p, 1) == ":") { p++; f = -1 }
	}
	return 1
}
function number(lo, hi,    d, f) {
	f = 0
	for (d = 0; d < 3 && isdigit(substr(s, p, 1)); d++) {
		f = f * 10 + substr(s, p, 1)
		p++
	}
	return d > 0 && f >= lo && f <= hi
}
function tzname(    q, n, c) {
	q = substr(s, p, 1) == "<"
	if (q) p++
	for (n = 0; ; n++) {
		c = substr(s, p, 1)
		if (!(isalpha(c) || (q && (isdigit(c) || c == "+" || c == "-")))) break
		p++
	}
	if (n < 3 || n > 6) return 0
	if (q && substr(s, p++, 1) != ">") return 0
	return 1
}
function rule(    c) {
	if (substr(s, p++, 1) != ",") return fail("missing , before rule")
	c = substr(s, p, 1)
	if (c == "M") {
		p++
		if (!number(1, 12) || substr(s, p++, 1) != "." ||
		    !number(1, 5) || substr(s, p++, 1) != "." || !number(0, 6))
			return fail("bad Mm.w.d rule")
	} else if (c == "J") {
		p++
		if (!number(1, 365)) return fail("bad Jn rule")
	} else if (!number(0, 365)) {
		return fail("bad rule")
	}
	if (substr(s, p, 1) == "/") {
		p++
		if (substr(s, p, 1) == "-" || substr(s, p, 1) == "+")
			return fail("signed rule time (uClibc-ng accepts 0-24 only)")
		if (!offset()) return fail("rule time out of range (uClibc-ng accepts 0-24 only)")
	}
	return 1
}
function check(    c) {
	s = val; p = 1
	if (length(s) > 67) return fail("longer than 67 characters")
	if (substr(s, p, 1) == ":") p++
	if (!tzname()) return fail("bad standard time name")
	c = substr(s, p, 1)
	if (c == "+" || c == "-") p++
	if (!offset()) return fail("bad standard time offset")
	if (p > length(s)) return 1
	if (!tzname()) return fail("bad daylight time name")
	c = substr(s, p, 1)
	if (c == "+" || c == "-") { p++; if (!offset()) return fail("bad daylight time offset") }
	else if (isdigit(c) && !offset()) return fail("bad daylight time offset")
	if (p > length(s)) return 1
	if (!rule() || !rule()) return 0
	if (p <= length(s)) return fail("trailing characters")
	return 1
}
/"n":/ {
	if (!match($0, /^"n":"[^"]*","v":"[^"]*"}/)) {
		printf "check-tz-json: cannot read entry: %s\n", $0
		bad++
		next
	}
	split(substr($0, 1, RLENGTH - 1), f, "\"")
	name = f[4]; val = f[8]; total++
	check()
}
END {
	if (bad) {
		printf "check-tz-json: %d of %d entries would run in UTC on uClibc-ng\n", bad, total
		exit 1
	}
	if (!total) { print "check-tz-json: no entries found"; exit 1 }
	printf "check-tz-json: %d entries OK\n", total
}'
