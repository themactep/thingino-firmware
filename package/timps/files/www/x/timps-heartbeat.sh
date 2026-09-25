#!/bin/sh
# timps heartbeat payload builder, shared by json-heartbeat.cgi (SSE) and json-heartbeat-slow.cgi.

TIMPS_CONF="${TIMPS_CONF:-/etc/timps.conf}"
# timps now speaks HTTPS-only on its port when http.https is set (ONVIF-safe 8880 by default).
_timps_port=$(sed -n 's/^[[:space:]]*http\.port[[:space:]]*=[[:space:]]*\([0-9]\{1,\}\).*/\1/p' "$TIMPS_CONF" 2>/dev/null | head -n1)
[ -n "$_timps_port" ] || _timps_port=8880
_timps_https=$(sed -n 's/^[[:space:]]*http\.https[[:space:]]*=[[:space:]]*\([0-9A-Za-z]*\).*/\1/p' "$TIMPS_CONF" 2>/dev/null | head -n1)
case "$_timps_https" in
	1 | true | yes | on)
		_timps_scheme=https
		TIMPS_CURL_K="-k"
		;;
	*)
		_timps_scheme=http
		TIMPS_CURL_K=""
		;;
esac
TIMPS_CONTROL_URL="$_timps_scheme://127.0.0.1:$_timps_port/control"
TIMPS_DAYNIGHT_MODE_FILE="${TIMPS_DAYNIGHT_MODE_FILE:-/run/thingino/daynight_mode}"
TIMPS_IRCUT_MODE_FILE="${TIMPS_IRCUT_MODE_FILE:-/tmp/ircutmode.txt}"

timps_hb_light_state() {
	command -v light >/dev/null 2>&1 || {
		printf 'null'
		return 0
	}
	v=$(light "$1" read 2>/dev/null | tr -d '\r\n')
	case "$v" in
		0 | 1) printf '%s' "$v" ;;
		*) printf 'null' ;;
	esac
}

timps_hb_ircut_state() {
	v=$(sed -n '1p' "$TIMPS_IRCUT_MODE_FILE" 2>/dev/null | tr -d '\r\n ')
	case "$v" in
		0 | 1) printf '%s' "$v" ;;
		*) printf 'null' ;;
	esac
}

timps_hb_wg_status() {
	if ip link show wg0 2>/dev/null | grep -q 'state UP'; then
		printf '1'
	else
		printf '0'
	fi
}

timps_heartbeat_payload() {
	CUR=$(curl -s $TIMPS_CURL_K -m 2 "$TIMPS_CONTROL_URL" 2>/dev/null)

	# ISP running mode from the flat image object (0 = day/color, 1 = night)
	RM=$(printf '%s' "$CUR" | sed -n 's/.*"image":{[^}]*"running_mode":\([01]\).*/\1/p')
	# native auto day/night detection on/off (the trailing daynight object)
	DN_EN=$(printf '%s' "$CUR" | sed -n 's/.*"daynight":{"enabled":\([01]\).*/\1/p')
	DNOBJ=$(printf '%s' "$CUR" | sed -n 's/.*"daynight":{\([^}]*\)}.*/\1/p')
	BRI=$(printf '%s' "$DNOBJ" | sed -n 's/.*"brightness":\(-\{0,1\}[0-9][0-9]*\(\.[0-9][0-9]*\)\{0,1\}\).*/\1/p')
	TG=$(printf '%s' "$DNOBJ" | sed -n 's/.*"total_gain":\(-\{0,1\}[0-9][0-9]*\).*/\1/p')
	case "$BRI" in '' | -*) BRI=null ;; esac
	case "$TG" in '' | -*) TG=null ;; esac
	# live mic mute + persisted audio enable from the flat audio object
	MUTE=$(printf '%s' "$CUR" | sed -n 's/.*"audio":{[^}]*"mute":\([01]\).*/\1/p')
	AEN=$(printf '%s' "$CUR" | sed -n 's/.*"audio":{[^}]*"enabled":\([01]\).*/\1/p')
	PRIV=$(printf '%s' "$CUR" | sed -n 's/.*"privacy":{\(.*\)},"daynight".*/\1/p')
	case "$PRIV" in *'"enabled":1'*) PRIV=true ;; *) PRIV=false ;; esac
	# recording status: rec_ch<channel> reflects the timps recorder state
	REC=$(printf '%s' "$CUR" | sed -n 's/.*"record":{\([^}]*\)}.*/\1/p')
	RECING=$(printf '%s' "$REC" | sed -n 's/.*"recording":\([01]\).*/\1/p')
	RECCH=$(printf '%s' "$REC" | sed -n 's/.*"channel":\([0-9]\).*/\1/p')
	REC0=false
	REC1=false
	if [ "$RECING" = "1" ]; then
		if [ "$RECCH" = "1" ]; then REC1=true; else REC0=true; fi
	fi

	MODE=$(sed -n '1p' "$TIMPS_DAYNIGHT_MODE_FILE" 2>/dev/null | tr -d '\r\n ')
	case "$MODE" in
		day | night) ;;
		*)
			case "$RM" in
				0) MODE=day ;;
				1) MODE=night ;;
				*) MODE=unknown ;;
			esac
			;;
	esac

	case "$RM" in
		0 | 1) COLOR=$RM ;;
		*) COLOR=null ;;
	esac

	if [ "$DN_EN" = "1" ]; then DN_JSON=true; else DN_JSON=false; fi

	# Mic button state: on unless live-muted (or audio disabled entirely)
	if [ "$MUTE" = "1" ] || [ "$AEN" = "0" ]; then MIC=false; else MIC=true; fi

	MOTION=$(sed -n 's/^[[:space:]]*motion\.enabled[[:space:]]*=[[:space:]]*\([01]\).*/\1/p' "$TIMPS_CONF" 2>/dev/null | head -n 1)
	if [ "$MOTION" = "1" ]; then MOTION=true; else MOTION=false; fi

	printf '{"time_now":%s,"uptime":%s,"daynight_brightness":%s,"total_gain":%s,"daynight_mode":"%s","rec_ch0":%s,"rec_ch1":%s,"motion_enabled":%s,"privacy_enabled":%s,"color_mode":%s,"mic_enabled":%s,"spk_enabled":false,"spk_supported":false,"daynight_enabled":%s,"ircut_state":%s,"ir850_state":%s,"ir940_state":%s,"white_state":%s,"wg_status":%s}\n' \
		"$(date +%s)" \
		"$(cut -d '.' -f 1 /proc/uptime 2>/dev/null || printf '0')" \
		"$BRI" \
		"$TG" \
		"$MODE" \
		"$REC0" \
		"$REC1" \
		"$MOTION" \
		"$PRIV" \
		"$COLOR" \
		"$MIC" \
		"$DN_JSON" \
		"$(timps_hb_ircut_state)" \
		"$(timps_hb_light_state ir850)" \
		"$(timps_hb_light_state ir940)" \
		"$(timps_hb_light_state white)" \
		"$(timps_hb_wg_status)"
}
