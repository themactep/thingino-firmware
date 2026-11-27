#!/bin/bash
# Functional test for json-webtorrent.cgi with a mocked raptorctl.
#
# The mock models the REAL raptorctl/daemon split, which the pending_restart
# logic depends on:
# - `config set` writes the config FILE only; a running daemon keeps its
#   in-memory copy until restarted (file == memory only after start/restart).
# - `config get` answers from the running daemon's memory when rwd is up,
#   and falls back to the FILE when rwd is down (real raptorctl behavior).
# - `rwd status`/`rwd share` fail when the daemon is not running (no socket);
#   share returns the RUNNING key: prefix_<pinned> or a random runtime key,
#   with the prefix computed by the REAL prefix function from the CGI.
set -u
WT="$(cd "$(dirname "$0")/../.." && pwd)"
CGI=$WT/package/thingino-raptor/files/www/x/json-webtorrent.cgi
T=/tmp/wt-cgi-test
rm -rf "$T"
mkdir -p "$T/mock-bin" "$T/www/x"
MOCKCONF=$T/raptor.conf # config FILE (/etc/raptor.conf analog)
MOCKMEM=$T/raptor.mem   # daemon in-memory config analog
PASS=0 FAIL=0

# test copy of CGI with auth stubbed out
# NOTE: run under bash, not /bin/sh (dash): the urldecode helper uses
# printf '%b' with \xHH escapes, which busybox ash (camera) and bash
# support but dash does not.
sed 's|^\. /var/www/x/auth.sh$|:|; s|^require_auth$|:|' "$CGI" >"$T/cgi-test.sh"
chmod +x "$T/cgi-test.sh"

# real prefix function, extracted fresh from the CGI under test
sed -n '/^key_prefix_from_key()/,/^}/p' "$CGI" >"$T/prefix.sh"

cat >"$T/mock-bin/raptorctl" <<EOF
#!/bin/sh
CONF="\${MOCKCONF:?}"
MEM="\${MOCKMEM:?}"
. "\${PREFIXFILE:?}"   # real key_prefix_from_key
printf '%s\n' "\$*" >> "\$CONF.calls" 2>/dev/null || :
cmd=\$1
mem_key() { grep '^share_key[[:space:]]*=' "\$MEM" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' '; }
daemon_up() { [ -f "\$CONF.started" ]; }
case "\$cmd" in
  config)
    sub=\$2; section=\$3; key=\$4
    if [ "\$sub" = get ]; then
      # daemon up: in-memory copy; daemon down: real raptorctl reads the file
      if daemon_up; then src=\$MEM; else src=\$CONF; fi
      grep "^\${key}[[:space:]]*=" "\$src" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' '
    elif [ "\$sub" = set ]; then
      shift 4; val="\$*"
      touch "\$CONF"
      grep -Ev "^\${key}[[:space:]]*=" "\$CONF" > "\$CONF.new" 2>/dev/null || :
      echo "\${key} = \${val}" >> "\$CONF.new"
      mv "\$CONF.new" "\$CONF"
      # deliberately does NOT touch \$MEM: daemon never sees it until restart
      exit 0
    fi
    ;;
  save)
    # daemon writes its in-memory copy back to the file
    daemon_up || exit 1
    cp "\$MEM" "\$CONF"
    ;;
  rwd)
    if [ "\${MOCK_RWD_DOWN:-0}" = 1 ]; then exit 1; fi
    sub=\$2
    case "\$sub" in
      status)
        daemon_up || exit 1    # no control socket when not running
        ;;
      restart|start)
        [ "\${MOCK_RWD_STUCK:-0}" = 1 ] || {
          touch "\$CONF.started"
          cp "\$CONF" "\$MEM"   # daemon loads the file at start
        }
        exit 0
        ;;
      share)
        daemon_up || exit 1
        k=\$(mem_key)
        if [ -n "\$k" ]; then
          key="\$(key_prefix_from_key "\$k")_\$k"
        else
          key=LIVERANDOM7
        fi
        printf '{"status":"ok","key":"%s","url":"https://viewer.thingino.com/share.html#key=%s"}' "\$key" "\$key"
        ;;
    esac
    ;;
esac
EOF
chmod +x "$T/mock-bin/raptorctl"

jsonq() { # dotted path under "data"; reads $T/out
	python3 -c '
import json, sys, functools
v = functools.reduce(lambda a, k: a[k], sys.argv[1].split("."), json.load(open(sys.argv[2])))
print("null" if v is None else "true" if v is True else "false" if v is False else v)
' "data.$1" "$T/out"
}

run_cgi() { # method, body -> $T/out = JSON body, $T/raw = headers+body
	local method=$1 body=${2:-}
	local -a env=("REQUEST_METHOD=$method" "PATH=$T/mock-bin:$PATH"
		"MOCKCONF=$MOCKCONF" "MOCKMEM=$MOCKMEM" "WT_CONF_FILE=$MOCKCONF"
		"PREFIXFILE=$T/prefix.sh")
	if [ -n "$body" ]; then
		printf '%s' "$body" | env "${env[@]}" "CONTENT_LENGTH=$(printf '%s' "$body" | wc -c)" bash "$T/cgi-test.sh" >"$T/raw" 2>&1
	else
		env "${env[@]}" bash "$T/cgi-test.sh" >"$T/raw" 2>&1
	fi
	sed -n '/^{/,$p' "$T/raw" >"$T/out"
}

check() { # name, predicate command...
	local name=$1
	shift
	if "$@"; then
		PASS=$((PASS + 1))
		echo "PASS: $name"
	else
		FAIL=$((FAIL + 1))
		echo "FAIL: $name"
		head -4 "$T/raw" | sed 's/^/      /'
	fi
}

has() { grep -q "$1" "$T/out"; }
not_has() { ! grep -q "$1" "$T/out"; }
status_is() { grep -q "^Status: $1" "$T/raw"; }
file_share_key() { grep '^share_key' "$MOCKCONF" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' '; }
mem_share_key() { grep '^share_key' "$MOCKMEM" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' '; }
calls_has() { grep -q "$1" "$MOCKCONF.calls" 2>/dev/null; }
not_calls_has() { ! grep -q "$1" "$MOCKCONF.calls" 2>/dev/null; }

seed_conf() { # $@ = extra lines (e.g. share_key pin)
	{
		echo "[system]"
		echo "video_backend = imp"
		echo ""
		echo "[webtorrent]"
		echo "enabled = true"
		echo "tracker = wss://tracker.example.org"
		echo "stun_server = stun.example.org"
		echo "stun_port = 3478"
		echo "tls_verify = true"
		for l in "$@"; do echo "$l"; done
	} >"$MOCKCONF"
	: >"$MOCKCONF.calls"
	rm -f "$MOCKCONF.started"
}

daemon_start() { # start daemon with current file contents
	touch "$MOCKCONF.started"
	cp "$MOCKCONF" "$MOCKMEM"
}

file_pinned_to() { # pin share_key in the FILE only (out-of-band edit analog)
	grep -v '^share_key' "$MOCKCONF" >"$MOCKCONF.new"
	echo "share_key = $1" >>"$MOCKCONF.new"
	mv "$MOCKCONF.new" "$MOCKCONF"
}

# shellcheck disable=SC1091  # prefix.sh is generated into $T just above
. "$T/prefix.sh"
PIN=MyPin1234
PREFIXED=$(key_prefix_from_key "$PIN")

# ── T1: GET with daemon down, unpinned: no URL guess, no key leak ──
seed_conf
MOCK_RWD_DOWN=1 run_cgi GET
check "T1 daemon-down unpinned: url null" not_has '"url": *"https'
check "T1b no runtime key leak" not_has 'LIVERANDOM7'

# ── T2: GET daemon down, pinned key in file -> deterministic URL ──
seed_conf "share_key = $PIN"
MOCK_RWD_DOWN=1 run_cgi GET
check "T2 daemon-down pinned: url prefix_key" has "#key=${PREFIXED}_${PIN}\""
check "T2b url built from viewer default" has '"url": *"https://viewer.thingino.com/share.html'

# ── T3: GET daemon UP (unpinned runtime), file pinned out-of-band -> pending ──
seed_conf
daemon_start
file_pinned_to "$PIN"
run_cgi GET
check "T3 out-of-band pin while running: pending true" [ "$(jsonq share.pending_restart)" = true ]
check "T3b shown key is still the RUNNING one" has 'LIVERANDOM7'

# ── T4: POST restart syncs file -> memory; pending clears, URL becomes pinned ──
run_cgi POST "action=restart"
run_cgi GET
check "T4 restart applied pin: url prefix_key" has "#key=${PREFIXED}_${PIN}"
check "T4b pending cleared after restart" [ "$(jsonq share.pending_restart)" = false ]

# ── T5: POST save: file written, memory untouched, no config save, pending true ──
seed_conf
daemon_start
run_cgi POST "action=save&enabled=true&tracker=wss%3A%2F%2Fnew.example%2Fws&stun_server=stun2.example.org&stun_port=3479&tls_verify=false&viewer_url=&share_key=$PIN"
check "T5 save persisted share_key to file" [ "$(file_share_key)" = "$PIN" ]
check "T5b daemon memory untouched (url still random)" has 'LIVERANDOM7'
check "T5c response flags pending_restart" [ "$(jsonq share.pending_restart)" = true ]
check "T5d settings mirror FILE (new pin shown)" has "\"share_key\": *\"$PIN\""
check "T5e raptorctl config save NOT called" not_calls_has 'save'
check "T5f tracker written urldecoded" [ "$(grep '^tracker' "$MOCKCONF" | head -1)" = "tracker = wss://new.example/ws" ]

# ── T6: POST save with EMPTY share_key generates an in-bounds pin (16 chars) ──
seed_conf
daemon_start
run_cgi POST "action=save&enabled=true&tracker=wss%3A%2F%2Ftracker.example.org&stun_server=stun.example.org&stun_port=3478&tls_verify=true&viewer_url=&share_key="
GEN=$(file_share_key)
check "T6 empty key generated 16-char pin" [ "${#GEN}" = 16 ]

# ── T7: POST rotate daemon UP: new pin, restart ran, pending false ──
seed_conf "share_key = $PIN"
daemon_start
run_cgi POST "action=rotate"
NEW=$(file_share_key)
check "T7 rotate persisted a fresh pin" [ "${#NEW}" = 16 ] && [ "$NEW" != "$PIN" ]
check "T7b restart synced memory from file" [ "$(mem_share_key)" = "$NEW" ]
check "T7c url is new prefixed key" has "#key=$(key_prefix_from_key "$NEW")_${NEW}"
check "T7d no config save call" not_calls_has 'save'

# ── T8: POST rotate daemon DOWN: pin lands in file, honest message ──
seed_conf
run_cgi POST "action=rotate"
GEN=$(file_share_key)
check "T8 rotate with rwd down pins key in file" [ "${#GEN}" = 16 ]
check "T8b message says goes live at next start" has 'goes live at the next start'
check "T8c no daemon start implied" [ ! -f "$MOCKCONF.started" ]

# ── T9: POST restart with stuck daemon -> 504 ──
seed_conf
MOCK_RWD_STUCK=1 run_cgi POST "action=restart"
check "T9 stuck restart returns 504" status_is 504

# ── T10: validation matrix ──
SAVE="action=save&enabled=true&tracker=wss%3A%2F%2Fok.example&stun_server=ok&stun_port=99&tls_verify=true&viewer_url="
seed_conf
run_cgi POST "$SAVE&share_key=bad%3Bkey"
check "T10 invalid key rejected 422" status_is 422
seed_conf
run_cgi POST "action=save&enabled=true&tracker=wss%3A%2F%2Fok.example&stun_server=ok&stun_port=notanumber&tls_verify=true&viewer_url=&share_key=GoodKey12"
check "T10b bad stun_port rejected" status_is 422
seed_conf
BIG=$(python3 -c "print('wss%3A%2F%2F' + 'x'*300)")
run_cgi POST "action=save&enabled=true&tracker=$BIG&stun_server=ok&stun_port=99&tls_verify=true&viewer_url=&share_key=GoodKey12"
check "T10c oversize tracker rejected" status_is 422
seed_conf
run_cgi POST "action=save&enabled=true&tracker=wss%3A%2F%2Fok.example&stun_server=ok&stun_port=99&tls_verify=true&viewer_url=ftp%3A%2F%2Fbad.example&share_key=GoodKey12"
check "T10d non-http viewer_url rejected" status_is 422
seed_conf
run_cgi POST "action=save&enabled=true&tracker=wss%3A%2F%2Fok.example&stun_server=ok&stun_port=99&tls_verify=true&viewer_url=&share_key=ab"
check "T10e too-short share_key rejected" status_is 422
seed_conf
run_cgi POST "action=save&enabled=true%0Ainjected=1&tracker=wss%3A%2F%2Fok.example&stun_server=ok&stun_port=99&tls_verify=true&viewer_url=&share_key=GoodKey12"
check "T10f newline in bool value tolerated (no crash)" status_is 200
seed_conf
run_cgi POST "action=save&enabled=true&tracker=wss%3A%2F%2Fok.example%0Ainjected%3D1&stun_server=ok&stun_port=99&tls_verify=true&viewer_url=&share_key=GoodKey12"
check "T10g newline injection in tracker rejected" status_is 422

# ── T11: GET with missing config file: valid JSON, defaults, no crash ──
seed_conf
rm -f "$MOCKCONF"
run_cgi GET
check "T11 missing config: enabled false" [ "$(jsonq webtorrent.enabled)" = false ]
check "T11b missing config: share_key null" [ "$(jsonq webtorrent.share_key)" = null ]

echo
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
