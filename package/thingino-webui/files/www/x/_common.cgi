#!/bin/haserl
<%
. /usr/share/common

IFS_ORIG=$IFS

STR_EIGHT_OR_MORE_CHARS=" pattern=\".{8,}\" title=\"8 characters or longer\""
STR_NOT_SUPPORTED="not supported on this system"
STR_PASSWORD_TO_PSK="Plain-text password will be automatically converted to a PSK upon submission"
STR_SUPPORTS_STRFTIME="Supports <a href=\"https://strftime.net/\" target=\"_blank\">strftime</a> format"
STR_USER_TEXT_FMT="Supports %hostname, %ipaddress, %fps, %bps"

pagename=$(basename "$SCRIPT_NAME")
pagename="${pagename%%.*}"

# files
alerts_dir="/tmp/alerts"
ensure_dir "$alerts_dir"

signature_file="/tmp/signature.txt"

sysinfo_file="/tmp/sysinfo.txt"

# read from files
ws_token="$(cat /run/prudynt_websocket_token)"

# name, text
error_if_empty() {
	[ -z "$1" ] && set_error_flag "$2"
}

# name, value
default_for() {
	[ -z "$(eval echo \$$1)" ] || return
	eval $1=\$2
}

alert_append() {
	echo "$2" >> "$alerts_dir/$1.txt"
}

alerts_read() {
	[ -d "$alerts_dir" ] || return
	[ -z "$(ls -A $alerts_dir)" ] && return

	IFS=$'\n'
	for file in $(ls -1 $alerts_dir/*.txt); do
		echo "<div class=\"alert alert-$(basename $file .txt) alert-dismissible fade show\" role=\"alert\">"
		for line in $(cat $file); do
			echo "<p>$line</p>"
		done
		button_close
		echo "</div>"
		rm $file
	done
	IFS=$IFS_ORIG
}

# time_gmt "format" "date"
time_gmt() {
	if [ -n "$2" ]; then
		TZ=GMT0 date +"$1" --date="$2"
	else
		TZ=GMT0 date +"$1"
	fi
}

time_epoch() {
	time_gmt "%s" "$1"
}

time_http() {
	time_gmt "%a, %d %b %Y %T %Z" "$1"
}

button_close() {
	echo "<button type=\"button\" class=\"btn btn-close\" data-bs-dismiss=\"alert\" aria-label=\"Close\"></button>"
}

button_download() {
	echo "<a href=\"dl2.cgi?log=$1\" class=\"btn btn-primary\">Download log</a>"
}

button_help() {
	echo "<div class=\"switch float-end\"><img type=\"button\" src=\"/a/help.svg\" class=\"img-fluid\"" \
	" data-bs-toggle=\"modal\" data-bs-target=\"#helpModal\" alt=\"Help\" style=\"max-height:1.5rem\"></div>"
}

button_refresh() {
	echo "<a href=\"$REQUEST_URI\" class=\"btn btn-primary refresh\">Refresh</a>"
}

button_restore_from_rom() {
	[ -f "/rom/$1" ] || return 1

	if [ -z "$(diff "/rom/$1" "$1")" ]; then
		echo "<p class=\"small fst-italic\">File matches the version in ROM.</p>"
		return 1
	fi

	echo "<p><a class=\"btn btn-danger\" href=\"restore.cgi?f=$1\">Replace $1 with its version from ROM</a></p>"
}

button_send2tb() {
	echo "<p class=\"mb-4\"><a class=\"text-warning\"" \
	 "href=\"send.cgi?to=termbin&payload=$(echo "$1" | base64)\"" \
	 "target=\"_blank\">Share via TermBin</a></p>"
}

# button_submit "text" "type" "extras"
button_submit() {
	local c t x

	t="${1:-Save changes}"
	c="${2:-primary}"
	x="${3:- }"
	echo "<div class=\"mt-3\"><input type=\"submit\" class=\"btn btn-$c\"$x value=\"$t\"></div>"
}

button_sync_time() {
	local text

	if [ "true" = "$wlanap_enabled" ]; then
		text="Set time from the browser"
	else
		text="Synchronize time from NTP server"
	fi
	echo "<button id=\"sync-time\" type=\"button\" class=\"btn btn-secondary mb-3\">$text</button>"
}

# 1: name
# 2: status
button_test() {
	echo "<div class=\"switch float-end\">" \
	"<button type=\"button\" id=\"$1_toggle\" data-pin=\"$1\" data-status=\"$2\"" \
	" class=\"btn btn-sm btn-outline-secondary m-0 led-status\">Test</button></div>"
}

check_file_exist() {
	[ -f "$1" ] || redirect_back "danger" "File $1 not found"
}

check_mac_address() {
	echo "$1" | grep -qE "^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$"
}

check_password() {
	local safe_page

	safe_page="/x/config-webui.cgi"
	[ -z "$REQUEST_URI" ] || [ "$REQUEST_URI" = "$safe_page" ] && return
	if [ ! -f /etc/shadow- ] || [ -z $(awk -F: '/^root/{print $2}' /etc/shadow-) ]; then
		redirect_to "$safe_page" "danger" "You must set your own secure password!"
	fi
}

checked_if() {
	[ "$1" = "$2" ] && echo -n " checked"
}

checked_if_not() {
	[ "$1" = "$2" ] || echo -n " checked"
}

selected_if() {
	[ "$1" = "$2" ] && echo -n " selected"
}

if_else() {
	[ "$1" = "$2" ] && echo -n " $3" || echo -n " $4"
}

ex() {
	echo "<div class=\"${2:-ex}\"><h6># $1</h6><pre class=\"small\">"
	# NB! $() forks process and stalls output
	eval "$1" | sed "s/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g;s/\"/\&quot;/g"
	echo "</pre></div>"
}

# field_checkbox "name" "label" "hint"
field_checkbox() {
	local v

	v=$(t_value "$1")
	default_for v "false"
	echo "<p class=\"boolean form-check\">" \
	 "<input type=\"hidden\" id=\"$1-false\" name=\"$1\" value=\"false\">" \
	 "<input type=\"checkbox\" name=\"$1\" id=\"$1\" value=\"true\"" \
	 " class=\"form-check-input\"$(checked_if "true" "$v")>" \
	 "<label for=\"$1\" class=\"form-label\">$2</label>"
	[ -n "$3" ] && echo "<span class=\"hint text-secondary d-block mb-2\">$3</span>"
	echo "</p>"
}

field_color() {
	echo "<p id=\"$1_wrap\" class=\"file\">" \
	 "<label for=\"$1\" class=\"form-label\">$2</label>" \
	 "<input type=\"color\" id=\"$1\" name=\"$1\" class=\"form-control input-color\"></p>"
}

# field_file "name" "label" "hint"
field_file() {
	echo "<p id=\"$1_wrap\" class=\"file\">" \
	 "<label for=\"$1\" class=\"form-label\">$2</label>" \
	 "<input type=\"file\" id=\"$1\" name=\"$1\" class=\"form-control\">"
	[ -n "$3" ] && echo "<span class=\"hint text-secondary\">$3</span>"
	echo "</p>"
}

# field_gpio "name" "label"
field_gpio() {
	local active_suffix is_active is_active_low lit_on_boot name pin pin_off pin_status pin_on pwm var_pin var_pwm

	name=$1

	var_pin="${name}_pin"
	eval pin=\$$var_pin
	[ -z "$pin" ] && return

	var_pwm="${name}_pwm"
	eval pwm=\$$var_pwm

	[ "$pin" = "${pin//[^0-9]/}" ] && pin="${pin}O"

	active_suffix=${pin:0-1}
	case "$active_suffix" in
		o) pin_on=0; pin_off=1; is_active_low=" checked" ;;
		O) pin_on=1; pin_off=0 ;;
	esac
	pin=${pin:0:-1}
	pin_status=$(gpio read $pin)
	[ "$pin_status" -eq "$pin_on" ] && is_active=" checked"

	echo $DEFAULT_PINS | grep -E "\b$pin$active_suffix\b" > /dev/null && lit_on_boot=" checked"

	echo "<div class=\"col\"><div class=\"card h-100 gpio $name\"><div class=\"card-header\">$2" \
	 "<div class=\"switch float-end\"><button class=\"btn btn-sm btn-outline-secondary m-0 led-status\"" \
	 " type=\"button\" id=\"${name}_toggle\" $is_active>Test</button></div></div><div class=\"card-body\">" \
	 "<div class=\"row\"><label class=\"form-label col-9\" for=\"${name}_pin\">GPIO pin #</label>" \
	 "<div class=\"col\"><input type=\"text\" class=\"form-control text-end\" id=\"${name}_pin\"" \
	 " name=\"${name}_pin\" pattern=\"[0-9]{1,3}\" title=\"a number\" value=\"$pin\" required>" \
	 "</div></div>"

if [ $(is_pwm_pin "$pin") ]; then
	echo "<div class=\"row\">" \
	 "<label class=\"form-label col-9\" for=\"${name}_pwn_ch\">GPIO PWM channel</label><div class=\"col\">" \
	 "<input type=\"text\" class=\"form-control text-end\" id=\"${name}_pwm_ch\" name=\"${name}_pwm_ch\"" \
	 " pattern=\"[0-9]{1,3}\" title=\"empty or a number\" value=\"$pwm\"></div></div><div class=\"row\">" \
	 "<label class=\"form-label col-9\" for=\"${name}_pwm_lvl\">GPIO PWM level</label><div class=\"col\">" \
	 "<input type=\"text\" class=\"form-control text-end\" id=\"${name}_pwm_lvl\" name=\"${name}_pwm_lvl\"" \
	 " pattern=\"[0-9]{1,3}\" title=\"empty or a number\" value=\"$pwm\"></div></div>"
else
	echo "<div class=\"text-warning\">NOT A PWM PIN</div>"
fi
	echo "<div class=\"row\"><label class=\"form-label col-9\" for=\"${name}_inv\">Active low</label>" \
	 "<div class=\"col\"><input class=\"form-check-input\" type=\"checkbox\" id=\"${name}_inv\"" \
	 " name=\"${name}_inv\" value=\"true\"$is_active_low$is_disabled></div></div><div class=\"row mb-0\">" \
	 "<label class=\"form-label col-9\" for=\"${name}_lit\">Lit on boot</label><div class=\"col\">" \
	 "<input class=\"form-check-input\" type=\"checkbox\" id=\"${name}_lit\" name=\"${name}_lit\"" \
	 " value=\"true\"$lit_on_boot$is_disabled></div></div></div></div></div>"
}

# field_hidden "name" "value"
field_hidden() {
	echo "<input type=\"hidden\" name=\"$1\" id=\"$1\" value=\"$2\" class=\"form-hidden\">"
}

# field_number "name" "label" "range" "hint"
field_number() {
	local ab mn mx n r st v vr

	n=$1
	r=$3 # min,max,step,button
	mn=$(echo "$r" | cut -d, -f1)
	mx=$(echo "$r" | cut -d, -f2)
	st=$(echo "$r" | cut -d, -f3)
	ab=$(echo "$r" | cut -d, -f4)
	v=$(t_value "$n")
	vr=$v
	[ -n "$ab" ] && [ "$ab" = "$v" ] && vr=$(((mn + mx) / 2))
	echo "<div class=\"mb-2 number\"><label class=\"form-label\" for=\"$n\">$2</label><span class=\"input-group\">"
	# NB! no name on checkbox, since we don't want its data submitted
	if [ -n "$ab" ]; then
		echo "<label class=\"input-group-text\" for=\"${n}-auto\">$ab <input type=\"checkbox\"" \
		 " class=\"form-check-input auto-value ms-1\" id=\"${n}-auto\" data-for=\"$n\"" \
		 " data-value=\"$vr\" $(checked_if "$ab" "$v")></label>"
	fi
	echo "<input type=\"text\" id=\"$n\" name=\"$n\" class=\"form-control text-end\" value=\"$vr\"" \
	 " pattern=\"[0-9]{1,}\" title=\"numeric value\" data-min=\"$mn\" data-max=\"$mx\" data-step=\"$st\"></span>"
	[ -n "$4" ] && echo "<span class=\"hint text-secondary\">$4</span>"
	echo "</div>"
}

# field_password "name" "label" "hint"
field_password() {
	local v

	v=$(t_value "$1")
	echo "<div class=\"mb-2 password\" id=\"$1_wrap\"><label for=\"$1\" class=\"form-label\">$2</label>" \
	 "<span class=\"input-group\"><input type=\"password\" id=\"$1\" name=\"$1\" class=\"form-control\"" \
	 " value=\"$v\" placeholder=\"K3wLHaZk3R!\"><label class=\"input-group-text\"><input type=\"checkbox\"" \
	 " class=\"form-check-input me-1\" data-for=\"$1\"> show</label></span>"
	[ -n "$3" ] && echo "<span class=\"hint text-secondary\">$3</span>"
	echo "</div>"
}

# field_range "name" "label" "range" "hint"
field_range() {
	local ab mn mx n r st v vr

	n=$1
	r=$3 # min,max,step,button
	mn=$(echo "$r" | cut -d, -f1)
	mx=$(echo "$r" | cut -d, -f2)
	st=$(echo "$r" | cut -d, -f3)
	ab=$(echo "$r" | cut -d, -f4)
	v=$(t_value "$n")
	vr=$v
	[ -z "$vr" -o "$ab" = "$vr" ] && vr=$(((mn + mx) / 2))
	echo "<div class=\"mb-2 range\" id=\"${n}_wrap\"><label class=\"form-label\" for=\"$n\">$2</label>" \
	 "<span class=\"input-group\">"
	# NB! no name on checkbox, since we don't want its data submitted
	if [ -n "$ab" ]; then
		echo "<label class=\"input-group-text\" for=\"$n-auto\">$ab <input type=\"checkbox\"" \
		 " class=\"form-check-input auto-value ms-1\" id=\"${n}-auto\" data-for=\"$n\"" \
		 " data-value=\"$vr\" $(checked_if "$ab" "$v")></label>"
	fi
	echo "<span class=\"input-group-text range-value text-end\" id=\"$n-show\">$v</span>"
	# Input that holds the submitting value.
	echo "<input type=\"range\" id=\"$n\" name=\"$n\" value=\"$vr\" min=\"$mn\" max=\"$mx\" step=\"$st\"" \
	 " class=\"form-control form-range\"></span>"
	[ -n "$4" ] && echo "<span class=\"hint text-secondary\">$4</span>"
	echo "</div>"
}

# field_select "name" "label" "options" "hint" "units"
field_select() {
	local o n v

	o=$3
	o=${o//,/ }
	echo "<div class=\"mb-2 select\" id=\"$1_wrap\"><label for=\"$1\" class=\"form-label\">$2</label>" \
	 "<select class=\"form-select\" id=\"$1\" name=\"$1\">"
	[ -z "$(t_value "$1")" ] && echo "<option value=\"\">- Select -</option>"
	for o in $o; do
		v="${o%:*}"
		n="${o#*:}"
		n=${n//_/ }
		echo -n "<option value=\"$v\""
		[ "$(t_value "$1")" = "$v" ] && echo -n " selected"
		echo ">$n</option>"
		unset v; unset n
	done
	echo "</select>"
	[ -n "$5" ] && echo "<span class=\"input-group-text\">$5</span>"
	[ -n "$4" ] && echo "<span class=\"hint text-secondary\">$4</span>"
	echo "</div>"
}

# field_swith "name" "label" "hint" "options"
field_switch() {
	local o o1 o2 v

	v=$(t_value "$1")
	default_for v "false"
	o=$4
	default_for o "true,false"
	o1=$(echo "$o" | cut -d, -f1)
	o2=$(echo "$o" | cut -d, -f2)
	echo "<div class=\"mb-2 boolean\" id=\"$1_wrap\"><span class=\"form-check form-switch\">" \
	 "<input type=\"hidden\" id=\"$1-false\" name=\"$1\" value=\"$o2\">" \
	 "<input type=\"checkbox\" id=\"$1\" name=\"$1\" value=\"$o1\" role=\"switch\"" \
	 " class=\"form-check-input\"$(checked_if "$o1" "$v")>" \
	 "<label for=\"$1\" class=\"form-check-label\">$2</label></span>"
	[ -n "$3" ] && echo "<span class=\"hint text-secondary\">$3</span>"
	echo "</div>"
}

# field_text "name" "label" "hint" "placeholder" "extra"
field_text() {
	local h p v

	v="$(t_value "$1")"
	h="$3"
	p="$4"
	echo "<div class=\"mb-2 string\" id=\"$1_wrap\"><label for=\"$1\" class=\"form-label\">$2</label>" \
	 "<input type=\"text\" id=\"$1\" name=\"$1\" class=\"form-control\" value=\"$v\" placeholder=\"$p\"$5>"
	[ -n "$h" ] && echo "<span class=\"hint text-secondary\">$h</span>"
	echo "</div>"
}

# field_textarea "name" "label" "hint"
field_textarea() {
	local v

	v="$(t_value "$1")"
	echo "<div class=\"mb-2 textarea\" id=\"$1_wrap\"><label for=\"$1\" class=\"form-label\">$2</label>" \
	 "<textarea id=\"$1\" name=\"$1\" class=\"form-control\">$v</textarea>"
	[ -n "$3" ] && echo "<span class=\"hint text-secondary\">$3</span>"
	echo "</div>"
}

# field_textedit "name" "file" "label"
field_textedit() {
	echo "<div class=\"mb-2 textarea\" id=\"$1_wrap\"><label for=\"$1\" class=\"form-label\">$3</label>" \
	 "<textarea id=\"$1\" name=\"$1\" class=\"form-control\">$(cat "$2")</textarea></div>"
}

generate_signature() {
	echo "$soc_model, $sensor_model, $flash_size_mb MB, $network_hostname, $network_macaddr" >$signature_file
}

http_header() {
	echo -en "$1\r\n"
}

html_title() {
	echo -n "$(hostname) - $page_title - thingino"
}

html_theme() {
	test -f "$CONFIG_FILE" && webui_theme=$(awk -F= '/webui_theme/{print $2}' "$CONFIG_FILE" | tr -d '"')
	case "$webui_theme" in
		dark | light)
			echo -n $webui_theme
			;;
		auto)
			if [ $(date +%H) -gt 8 ] && [ $(date +%H) -lt 20 ]; then
				echo -n "light"
			else
				echo -n "dark"
			fi
			;;
		*)
			echo -n "dark"
			;;
	esac
}

include() {
	[ -f "$1" ] || touch $1
	[ -f "$1" ] && . "$1"
}

is_pwm_pin() {
	pwm-ctrl -l | awk "/^GPIO $1/{print \$4}" | sed s/PWM//
}

is_valid_mac() {
	echo "$1" | grep -Eiq '^([0-9a-f]{2}[:-]){5}([0-9a-f]{2})$'
}

is_isolated() {
	[ -f "$PORTAL_MODE_FLAG" ] || [ -f "$WLANAP_MODE_FLAG" ] || [ "true" = "$webui_paranoid" ]
}

link_to() {
	echo "<a href=\"$2\">$1</a>"
}

wiki_page() {
	echo "<p class=\"mb-0\"><a class=\"text-info\"" \
	" href=\"https://github.com/themactep/thingino-firmware/wiki/$1\">Thingino Wiki</a></p>"
}

menu() {
	local css i name
	local CSS_ENABLED=" class=\"enabled\""
	for i in $(ls -1 $1-*); do
		css=""
		name=$(echo $i | sed -r -n "s/$1-(.*).cgi/\1/p")
		if [ "service" = "$1" ]; then
			case "$name" in
				motion)
					jct /etc/prudynt.json get motion.enabled | grep -q true && css=$CSS_ENABLED
					;;
				mqtt)
					[ -f /bin/mosquitto_pub ] || continue
					;;
				telegrambot)
					[ -f /bin/jsonfilter    ] || continue
					pidof telegrambot > /dev/null && css=$CSS_ENABLED
					;;
				timelapse)
					crontab -l | grep -v '^#' | grep -q timelapse && css=$CSS_ENABLED
					;;
				videorec)
					pidof record > /dev/null && css=$CSS_ENABLED
					;;
				zerotier)
					[ -f /sbin/zerotier-cli ] || continue
					;;
			esac
		elif [ "config" = "$1" ]; then
			[ "$name" = "developer" ] && [ ! -f /etc/init.d/S44devmounts ] && continue
		fi

		echo -n "<li$css><a class=\"dropdown-item\" href=\"$i\">" \
			$(sed -r -n '/page_title=/s/^.*page_title="(.*)",*$/\1/p' $i) \
			"</a></li>"
	done
}

# normalize_pin "pin"
normalize_pin() {
	pin=$1
	# default to output high
	[ "$pin" = "${pin//[^0-9]/}" ] && pin="${pin}O"
	case ${pin:0-1} in
		o) pin_on=0; pin_off=1 ;;
		O) pin_on=1; pin_off=0 ;;
	esac
	pin=${pin:0:-1}
	printf "%d %d %d" $pin $pin_on $pin_off
}

# pre "text" "classes" "extras"
pre() {
	# replace <, >, &, ", and ' with HTML entities
	echo "<pre class=\"$2\" $3>$(echo -e "$1" | sed "s/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g;s/\"/\&quot;/g")</pre>"
}

progressbar() {
	local c="primary"
	[ "$1" -ge "75" ] && c="danger"
	echo "<div class=\"progress\" role=\"progressbar\" aria-valuenow=\"$1\" aria-valuemin=\"0\"" \
	 " aria-valuemax=\"100\"><div class=\"progress-bar progress-bar-striped progress-bar-animated bg-$c\"" \
	 " style=\"width:$1%\"></div></div>"
}

read_from_config() {
	awk -F= "/^$1/{print \$2}" $CONFIG_FILE
}

# read_from_post "plugin" "params"
read_from_post() {
	local p

	for p in $2; do
		eval $1_$p=\$POST_$1_$p
		sanitize "$1_$p"
	done
}

# redirect_back "flash class" "flash text"
redirect_back() {
	redirect_to "${HTTP_REFERER:-/}" "$1" "$2"
}

# redirect_to "url" "flash class" "flash text"
redirect_to() {
	[ -n "$3" ] && alert_append "$2" "$3"
	echo "HTTP/1.1 303 See Other
Content-type: text/html; charset=UTF-8
Cache-Control: no-store
Pragma: no-cache
Date: $(time_http)
Server: $SERVER_SOFTWARE
Location: $1

"
	exit 0
}

report_error() {
	echo "<h4 class=\"text-danger\">Oops. Something happened.</h4>" \
	 "<div class=\"alert alert-danger\">$1</div>"
}

# report_log "text" "extras"
report_log() {
	pre "$1" "small" "$2"
}

report_command_error() {
	echo "<h4 class=\"text-danger\">Oops. Something happened.</h4>" \
	 "<div class=\"alert alert-danger\">"
	report_command_info "$1" "$2"
	echo "</div>"
}

report_command_info() {
	echo "<h4># $1</h4><pre class=\"small\">$2</pre>"
}

sanitize() {
	local n=$1
	# strip trailing whitespace
	eval $n=$(echo \$${n})
	# escape double-quotes
	eval $n=$(echo \${$n//\\\"/\\\\\\\"})
	# escape variables
	eval $n=$(echo \${$n//\$/\\\\\$})
}

sanitize4web() {
	local n=$1
	[ -z "$n" ] && return
	# convert html entities
	eval $n=$(echo \${$n//\\\"/\&quot\;})
	eval $n=$(echo \${$n//\$/\\\$})
}

# list of "param=value" lines
save2config() {
	local tmp1file tmp2file name value

	tmp1file="$(mktemp -u)"
	cp "$CONFIG_FILE" "$tmp1file"

	tmp2file="$(mktemp -u)"
	echo "$1" > "$tmp2file"
	while read -r line; do
		[ -z "$line" ] && continue

		name="${line%%=*}"
		value="${line#*=}"
		sed -i -r "/^$name=.*/d" "$tmp1file"

		[ -n "$value" ] && echo "$line" >> "$tmp1file"
	done < "$tmp2file"
	rm "$tmp2file"

	sed '/^$/d' "$tmp1file" | sort -u > "$CONFIG_FILE"
	rm "$tmp1file"
}

save2env() {
	local tmpfile=$(mktemp -u)
	echo -e "$*" >> $tmpfile
	fw_setenv -s $tmpfile
	rm $tmpfile
	refresh_env_dump
}

set_error_flag() {
	alert_append "danger" "$1"
	error=1
}

signature() {
	[ -f "$signature_file" ] || generate_signature
	cat $signature_file
}

tab_lap() {
	local c s
	c=""
	s="false"
	[ -n "$3" ] && s="true" && c=" active"
	echo "<li class=\"nav-item\" role=\"presentation\"><button role=\"tab\" id=\"#$1-tab\"" \
	 " class=\"nav-link$c\" data-bs-toggle=\"tab\" data-bs-target=\"#$1-tab-pane\"" \
	 " aria-controls=\"$1-tab-pane\" aria-selected=\"$s\">$2</button></li>"
}

t_value() {
	eval echo "\$$1"
}

update_caminfo() {
	local tmpfile f v

	tmpfile=/tmp/sysinfo.tmp
	:>$tmpfile

	# Hardware

	# FIXME
	flash_type="NOR"
	flash_size=$((0x0$(awk '/"all"/{print $2}' /proc/mtd)))
	if [ "$flash_size" -eq 0 ]; then
		mtd_size=$(grep -E "nor|nand" $(ls /sys/class/mtd/mtd*/type) | sed -E "s|type.+|size|g")
		flash_size=$(awk '{sum+=$1} END{print sum}' $mtd_size)
	fi
	flash_size_mb=$((flash_size / 1024 / 1024))

	sensor_fps_max=$(sensor max_fps)
	sensor_fps_min=$(sensor min_fps)
	sensor_model=$(sensor name)

	soc_family=$SOC_FAMILY
	soc_model=$SOC_MODEL

	# Firmware
	# uboot_version=$(fw_printenv -n ver)
	# default_for uboot_version $(strings /dev/mtdblock0 | grep '^U-Boot \d' | head -1)

	# WebUI version
	ui_password=$(awk -F: '/^root/{print $2}' /etc/shadow-)

	# Network
	network_dhcp="false"
	if [ -f /etc/resolv.conf ]; then
		network_dns_1=$(grep nameserver /etc/resolv.conf | sed -n 1p | cut -d' ' -f2)
		network_dns_2=$(grep nameserver /etc/resolv.conf | sed -n 2p | cut -d' ' -f2)
	fi
	network_hostname=$(hostname -s)
	network_interfaces=$(ifconfig | awk '/^[^( |lo)]/{print $1}')

	# if no default interface then no gateway nor wan mac present
	network_default_interface="$(ip r | sed -nE '/default/s/.+dev (\w+).+?/\1/p' | head -n 1)"
	if [ -n "$network_default_interface" ]; then
		grep -q 'inet\|dhcp' /etc/network/interfaces.d/$network_default_interface && network_dhcp="true"
		network_gateway=$(ip r | sed -nE "/default/s/.+ via ([0-9\.]+).+?/\1/p")
	else
		network_default_interface=$(ip r | sed -nE 's/.+dev (\w+).+?/\1/p' | head -n 1)
		network_gateway="" # $(fw_printenv -n gatewayip) # FIXME: Why do we need this?
	fi
	network_macaddr=$(cat /sys/class/net/$network_default_interface/address)
	network_address=$(ip r | sed -nE "/$network_default_interface/s/.+src ([0-9\.]+).+?/\1/p" | uniq)
	network_cidr=$(ip r | sed -nE "/$network_default_interface/s/^[0-9\.]+(\/[0-9]+).+?/\1/p")
	network_netmask=$(ifconfig $network_default_interface | grep "Mask:" | cut -d: -f4) # FIXME: Maybe convert from $network_cidr?

	overlay_root=$(mount | grep upperdir= | sed -r 's/^.*upperdir=([a-z\/]+).+$/\1/')

	# Default timezone is GMT
	tz_data=$(cat /etc/TZ)
	tz_name=$(cat /etc/timezone)
	if [ -z "$tz_data" ] || [ -z "$tz_name" ]; then
		tz_data="GMT0"; echo "$tz_data" >/etc/TZ
		tz_name="Etc/GMT"; echo "$tz_name" >/etc/timezone
	fi

	# prudynt values
	#rtsp_endpoint_ch0=$(jct /etc/prudynt.json get stream0.rtsp_endpoint | tr -d '"')
	#rtsp_endpoint_ch1=$(jct /etc/prudynt.json get stream1.rtsp_endpoint | tr -d '"')

	# create a sourceable file
	for v in flash_size flash_size_mb flash_type network_address network_cidr network_default_interface network_dhcp network_dns_1 network_dns_2 network_gateway network_hostname network_interfaces network_macaddr network_netmask overlay_root rtsp_endpoint_ch0 rtsp_endpoint_ch1 soc_family soc_model sensor_fps_max sensor_fps_min sensor_model tz_data tz_name uboot_version ui_password; do
		eval "echo $v=\'\$$v\'>>$tmpfile"
	done

	# sort content alphabetically
	sort <$tmpfile | sed /^$/d >$sysinfo_file && rm $tmpfile && unset tmpfile

	echo -e "# caminfo $(date +"%F %T")\n" >>$sysinfo_file
	generate_signature
}

if [ -f "$OS_RELEASE_FILE" ]; then
	. "$OS_RELEASE_FILE"
fi

if [ "100.64.1.1" = $(ifconfig wlan0 | sed -En 's/^\s*inet addr:([0-9.]+)\s.*/\1/p') ]; then
	wlanap_enabled="true"
else
	wlanap_enabled="false"
fi

assets_ts=$(date +%Y%m%d%H%M)

[ -f "$sysinfo_file" ] || update_caminfo

include "$sysinfo_file"

check_password
%>
