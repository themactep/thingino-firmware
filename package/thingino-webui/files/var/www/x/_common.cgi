#!/bin/haserl
<%
IFS_ORIG=$IFS

STR_CONFIGURE_SOCKS5="<a href=\"config-socks5.cgi\">Configure SOCKS5</a>"
STR_NOT_SUPPORTED="not supported on this system"
STR_SUPPORTS_STRFTIME="Supports <a href=\"https://man7.org/linux/man-pages/man3/strftime.3.html \" target=\"_blank\">strftime</a> format."

# tag "tag" "text" "css" "extras"
tag() {
	local c="$3"
	[ -n "$c" ] && c=" class=\"$c\""
	local x="$4"
	[ -n "$x" ] && x=" $x"
	echo "<$1$c$x>$2</$t>"
}

# A "tag" "classes" "extras"
A() {
	local c="$2"
	[ -n "$c" ] && c=" class=\"$c\""
	local x="$3"
	[ -n "$x" ] && x=" $x"
	echo "<$1$c$x>"
}

Z() {
	echo "</$1>"
}

# tag "text" "classes" "extras"
div() {
	tag "div" "$1" "$2" "$3"
}
h1() {
	tag "h1" "$1" "$2" "$3"
}
h2() {
	tag "h2" "$1" "$2" "$3"
}
h3() {
	tag "h3" "$1" "$2" "$3"
}
h4() {
	tag "h4" "$1" "$2" "$3"
}
h5() {
	tag "h5" "$1" "$2" "$3"
}
h6() {
	tag "h6" "$1" "$2" "$3"
}
label() {
	tag "label" "$1" "$2" "$3"
}
li() {
	tag "li" "$1" "$2" "$3"
}
p() {
	tag "p" "$1" "$2" "$3"
}
span() {
	tag "span" "$1" "$2" "$3"
}

div_() {
	A "div" "$1" "$2"
}
_div() {
	Z "div"
}

span_() {
	A "span" "$1" "$2"
}
_span() {
	Z "span"
}

# alert "text" "type" "extras"
alert() {
	echo "<div class=\"alert alert-$2\" $3>$1</div>"
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

button_download() {
	echo "<a href=\"dl2.cgi?log=$1\" class=\"btn btn-primary\">Download log</a>"
}

button_reboot() {
	echo "<form action=\"reboot.cgi\" method=\"post\"><input type=\"hidden\" name=\"action\" value=\"reboot\">"
	button_submit "Reboot camera" "danger"
	echo "</form>"
}

button_refresh() {
	echo "<a href=\"$REQUEST_URI\" class=\"btn btn-primary refresh\">Refresh</a>"
}

button_reset_firmware() {
	echo "<form action=\"firmware-reset.cgi\" method=\"post\"><input type=\"hidden\" name=\"action\" value=\"reset\">"
	button_submit "Reset firmware" "danger"
	echo "</form>"
}

button_restore_from_rom() {
	local file=$1
	[ ! -f "/rom/$file" ] && return
	if [ -z "$(diff "/rom/$file" "$file")" ]; then
		echo "<p class=\"small fst-italic\">File matches the version in ROM.</p>"
		return
	fi
	echo "<p><a class=\"btn btn-danger\" href=\"restore.cgi?f=$file\">Replace $file with its version from ROM</a></p>"
}

button_send2tb() {
	echo "<a class=\"btn btn-warning\" href=\"send.cgi?to=termbin&file=$1\" target=\"_blank\">Send to TermBin</a>"
}

# button_submit "text" "type" "extras"
button_submit() {
	local t="${1:-Save changes}"
	local c="${2:-primary}"
	local x="${3:- }"
	echo "<div class=\"mt-2\"><input type=\"submit\" class=\"btn btn-$c\"$x value=\"$t\"></div>"
}

check_file_exist() {
	[ -f "$1" ] || redirect_back "danger" "File $1 not found"
}

check_password() {
	local safepage="/x/config-webui.cgi"
	[ "$debug" -gt 0 ] && return
	[ -z "$REQUEST_URI" ] || [ "$REQUEST_URI" = "$safepage" ] && return
	if [ ! -f /etc/shadow- ] || [ -z $(grep root /etc/shadow- | cut -d: -f2) ]; then
		redirect_to "$safepage" "danger" "You must set your own secure password!"
	fi
}

checked_if() {
	[ "$1" = "$2" ] && echo -n " checked"
}

checked_if_not() {
	[ "$1" != "$2" ] && echo -n " checked"
}

selected_if() {
	[ "$1" = "$2" ] && echo -n " selected"
}

if_else() {
	[ "$1" = "$2" ] && echo -n " $3" || echo -n " $4"
}

e() {
	echo -e -n "$1"
}

ex() {
	echo "<div class=\"${2:-ex}\"><h6># $1</h6><pre class=\"small\">"
	# NB! $() forks process and stalls output.
	eval "$1" | sed "s/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g;s/\"/\&quot;/g"
	echo "</pre></div>"
}

# field_checkbox "name" "label" "hint"
field_checkbox() {
	local l=$2
	[ -z "$l" ] && l="$(t_label "$1")"
	[ -z "$l" ] && l="<span class=\"bg-warning\">$1</span>"
	local h=$3
	local v=$(t_value "$1")
	[ -z "$v" ] && v="false"
	echo "<p class=\"boolean form-check\">" \
		"<input type=\"hidden\" id=\"${1}-false\" name=\"$1\" value=\"false\">" \
		"<input type=\"checkbox\" name=\"$1\" id=\"$1\" value=\"true\" class=\"form-check-input\"$(checked_if "true" "$v")>" \
		"<label for=\"$1\" class=\"form-label\">$l</label>"
	[ -n "$h" ] && echo "<span class=\"hint text-secondary d-block mb-2\">$h</span>"
	echo "</p>"
}

# field_file "name" "label" "hint"
field_file() {
	local l=$2
	[ -z "$l" ] && l="$(t_label "$1")"
	[ -z "$l" ] && l="<span class=\"bg-warning\">$1</span>"
	local h=$3
	echo "<p class=\"file\">" \
		"<label for=\"$1\" class=\"form-label\">$l</label>" \
		"<input type=\"file\" id=\"$1\" name=\"$1\" class=\"form-control\">"
	[ -n "$h" ] && echo "<span class=\"hint text-secondary\">$h</span>"
	echo "</p>"
}

# field_hidden "name" "value"
field_hidden() {
	# do we need id here? id=\"${1}\". We do for netip password!
	echo "<input type=\"hidden\" name=\"$1\" id=\"$1\" value=\"$2\" class=\"form-hidden\">"
}

# field_number "name" "label" "range" "hint"
field_number() {
	local n=$1
	local l=$2
	[ -z "$l" ] && l="$(t_label "$1")"
	[ -z "$l" ] && l="<span class=\"bg-warning\">$1</span>"
	local r=$3 # min,max,step,button
	local mn=$(echo "$r" | cut -d, -f1)
	local mx=$(echo "$r" | cut -d, -f2)
	local st=$(echo "$r" | cut -d, -f3)
	local ab=$(echo "$r" | cut -d, -f4)
	local h=$4
	local v=$(t_value "$n")
	local vr=$v
	[ -n "$ab" ] && [ "$ab" = "$v" ] && vr=$(( ( $mn + $mx ) / 2 ))
	echo "<p class=\"number\">" \
		"<label class=\"form-label\" for=\"$n\">$l</label>" \
		"<span class=\"input-group\">"
	# NB! no name on checkbox, since we don't want its data submitted
	[ -n "$ab" ] && echo "<label class=\"input-group-text\" for=\"${n}-auto\">$ab" \
		"<input type=\"checkbox\" class=\"form-check-input auto-value ms-1\" id=\"${n}-auto\" data-for=\"$n\" data-value=\"$vr\" $(checked_if "$ab" "$v")>" \
		"</label>"
	echo "<input type=\"text\" id=\"$n\" name=\"$n\" class=\"form-control text-end\" value=\"$vr\" pattern=\"[0-9]{1,}\" title=\"numeric value\" data-min=\"$mn\" data-max=\"$mx\" data-step=\"$st\">" \
		"</span>"
	[ -n "$h" ] && echo "<span class=\"hint text-secondary\">$h</span>"
	echo "</p>"
}

# field_password "name" "label" "hint"
field_password() {
	local l=$2
	[ -z "$l" ] && l="$(t_label "$1")"
	[ -z "$l" ] && l="<span class=\"bg-warning\">$1</span>"
	local h=$3
	local v=$(t_value "$1")
	echo "<p class=\"password\" id=\"${1}_wrap\">" \
		"<label for=\"$1\" class=\"form-label\">$l</label><span class=\"input-group\">" \
		"<input type=\"password\" id=\"$1\" name=\"$1\" class=\"form-control\" value=\"$v\" placeholder=\"K3wLHaZk3R!\">" \
		"<label class=\"input-group-text\">" \
		"<input type=\"checkbox\" class=\"form-check-input me-1\" data-for=\"$1\"> show" \
		"</label></span>"
	[ -n "$h" ] && echo "<span class=\"hint text-secondary\">$h</span>"
	echo "</p>"
}

# field_range "name" "label" "range" "hint"
field_range() {
	local n=$1
	local l=$2
	[ -z "$l" ] && l="$(t_label "$n")"
	[ -z "$l" ] && l="<span class=\"bg-warning\">$n</span>"
	local r=$3 # min,max,step,button
	local mn=$(echo "$r" | cut -d, -f1)
	local mx=$(echo "$r" | cut -d, -f2)
	local st=$(echo "$r" | cut -d, -f3)
	local ab=$(echo "$r" | cut -d, -f4)
	local h=$4
	local v=$(t_value "$n")
	local vr=$v
	[ -z "$vr" -o "$ab" = "$vr" ] && vr=$(( ( $mn + $mx ) / 2 ))
	echo "<p class=\"range\" id=\"${n}_wrap\">" \
		"<label class=\"form-label\" for=\"$n\">$l</label>" \
		"<span class=\"input-group\">"
	# NB! no name on checkbox, since we don't want its data submitted
	[ -n "$ab" ] && echo "<label class=\"input-group-text\" for=\"${n}-auto\">$ab" \
		"<input type=\"checkbox\" class=\"form-check-input auto-value ms-1\" id=\"${n}-auto\" data-for=\"$n\" data-value=\"$vr\" $(checked_if "$ab" "$v")>" \
		"</label>"
	# Input that holds the submitting value.
	echo "<input type=\"hidden\" name=\"$n\" id=\"$n\" value=\"$v\">"
	# NB! no name on range, since we don't want its data submitted
	echo "<input type=\"range\" class=\"form-control form-range\" id=\"${n}-range\" value=\"$vr\" min=\"$mn\" max=\"$mx\" step=\"$st\">"
	echo "<span class=\"input-group-text show-value\" id=\"${n}-show\">$vr</span>" \
		"</span>"
	[ -n "$h" ] && echo "<span class=\"hint text-secondary\">$h</span>"
	echo "</p>"
}

# field_select "name" "label" "options" "hint" "units"
field_select() {
	local l=$2
	[ -z "$l" ] && l="$(t_label "$1")"
	[ -z "$l" ] && l="<span class=\"bg-warning\">$1</span>"
	local o=$3
	o=${o//,/ }
	local h=$4
	local u=$5
	echo "<p class=\"select\" id=\"${1}_wrap\">" \
		"<label for=\"$1\" class=\"form-label\">$l</label>" \
		"<select class=\"form-select\" id=\"$1\" name=\"$1\">"
	[ -z "$(t_value "$1")" ] && echo "<option value=\"\">Select from available options</option>"
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
	[ -n "$u" ] && echo "<span class=\"input-group-text\">$u</span>"
	[ -n "$h" ] && echo "<span class=\"hint text-secondary\">$h</span>"
	echo "</p>"
}

# field_swith "name" "label" "hint" "options"
field_switch() {
	local l=$2
	[ -z "$l" ] && l="$(t_label "$1")"
	[ -z "$l" ] && l="<span class=\"bg-warning\">$1</span>"
	local v=$(t_value "$1")
	[ -z "$v" ] && v="false"
	local h="$3"
	local o=$4
	[ -z "$o" ] && o="true,false"
	local o1=$(echo "$o" | cut -d, -f1)
	local o2=$(echo "$o" | cut -d, -f2)
	echo "<p class=\"boolean\" id=\"${1}_wrap\">" \
		"<span class=\"form-check form-switch\">" \
		"<input type=\"hidden\" id=\"${1}-false\" name=\"$1\" value=\"$o2\">" \
		"<input type=\"checkbox\" id=\"$1\" name=\"$1\" value=\"$o1\" role=\"switch\" class=\"form-check-input\"$(checked_if "$o1" "$v")>" \
		"<label for=\"$1\" class=\"form-check-label\">$l</label>" \
		"</span>"
	[ -n "$h" ] && echo "<span class=\"hint text-secondary\">$h</span>"
	echo "</p>"
}

# field_text "name" "label" "hint" "placeholder"
field_text() {
	local l=$2
	[ -z "$l" ] && l="$(t_label "$1")"
	[ -z "$l" ] && l="<span class=\"bg-warning\">$1</span>"
	local v="$(t_value "$1")"
	local h="$3"
	local p="$4"
	echo "<p class=\"string\" id=\"${1}_wrap\">" \
		"<label for=\"$1\" class=\"form-label\">$l</label>" \
		"<input type=\"text\" id=\"$1\" name=\"$1\" class=\"form-control\" value=\"$v\" placeholder=\"$p\">"
	[ -n "$h" ] && echo "<span class=\"hint text-secondary\">$h</span>"
	echo "</p>"
}

# field_textarea "name" "label" "hint"
field_textarea() {
	local l=$2
	[ -z "$l" ] && l="$(t_label "$1")"
	[ -z "$l" ] && l="<span class=\"bg-warning\">$1</span>"
	local v=$(t_value "$1")
	local h=$3
	echo "<p class=\"textarea\" id=\"${1}_wrap\">" \
		"<label for=\"$1\" class=\"form-label\">$l</label>" \
		"<textarea id=\"$1\" name=\"$1\" class=\"form-control\">$v</textarea>"
	[ -n "$h" ] && echo "<span class=\"hint text-secondary\">$h</span>"
	echo "</p>"
}

# field_textedit "name" "file" "label"
field_textedit() {
	local l=$3
	[ -z "$l" ] && l="$(t_label "$1")"
	[ -z "$l" ] && l="<span class=\"bg-warning\">$1</span>"
	local v=$(cat "$2")
	echo "<p class=\"textarea\" id=\"${1}_wrap\">" \
		"<label for=\"$1\" class=\"form-label\">$l</label>" \
		"<textarea id=\"$1\" name=\"$1\" class=\"form-control\">$v</textarea>"
	echo "</p>"
}

alert_append() {
	echo "$1:$2" >>"$alert_file"
}

alert_delete() {
	:>"$alert_file"
}

alert_read() {
	[ -f "$alert_file" ] || return
	[ -s "$alert_file" ] || return
	local c
	local m
	local l
	OIFS="$IFS"
	IFS=$'\n'
	for l in $(cat "$alert_file"); do
		c="$(echo $l | cut -d':' -f1)"
		m="$(echo $l | cut -d':' -f2-)"
		echo "<div class=\"alert alert-$c alert-dismissible fade show\" role=\"alert\">$m" \
			"<button type=\"button\" class=\"btn btn-close\" data-bs-dismiss=\"alert\" aria-label=\"Close\"></button>" \
			"</div>"
	done
	IFS=$OIFS
	alert_delete
}

alert_save() {
	echo "$1:$2" >$alert_file
}

header_bad_request() {
	echo "HTTP/1.1 400 Bad Request
Cache-Control: no-store
Pragma: no-cache
Date: $(time_http)
Server: $SERVER_SOFTWARE

"
}

header_ok() {
	echo "HTTP/1.1 200 OK
Content-type: application/json; charset=UTF-8
Cache-Control: no-store
Pragma: no-cache
Date: $(time_http)
Server: $SERVER_SOFTWARE

{}"
}

html_title() {
	[ -n "$page_title" ] && echo -n "$page_title"
	[ -n "$title" ] && echo -n ": $title"
	echo -n " - thingino"
}

# label "name" "classes" "extras" "units"
label() {
	local c="form-label"
	[ -n "$2" ] && c="$c $2"
	local l="$(t_label "$1")"
	[ -z "$l" ] && l="$1" && c="$c bg-warning"
	local x="$3"
	[ -n "$x" ] && x=" $x"
	local u="$4"
	[ -n "$u" ] && l="$l, <span class=\"units text-secondary x-small\">$u</span>"
	echo "<label for=\"$1\" class=\"$c\"$x>$l</label>"
}

link_to() {
	echo "<a href=\"$2\">$1</a>"
}

log() {
	echo $1 >/tmp/webui.log
}

menu() {
	local i
	local n
	for i in $(ls -1 $1-*); do
		if [ "plugin" = "$1" ]; then
			# get plugin name
			p="$(sed -r -n '/^plugin=/s/plugin="(.*)"/\1/p' $i)"

			# hide unsupported plugins
			[ "$p" = "mqtt"        ] && [ ! -f /bin/mosquitto_pub ] && continue
			[ "$p" = "telegrambot" ] && [ ! -f /bin/jsonfilter    ] && continue
			[ "$p" = "zerotier"    ] && [ ! -f /sbin/zerotier-cli ] && continue
			# get plugin description
			n="$(sed -r -n '/^plugin_name=/s/plugin_name="(.*)"/\1/p' $i)"

			# check if plugin is enabled
			echo -n "<li><a class=\"dropdown-item"
			grep -q -s "^${p}_enabled=\"true\"" $ui_config_dir/${p}.conf && echo -n " plugin-enabled"
			echo "\" href=\"$i\">$n</a></li>"
		else
			n="$(sed -r -n '/page_title=/s/^.*page_title="(.*)",*$/\1/p' $i)"
			echo -n "<li><a class=\"dropdown-item\" href=\"$i\">$n</a></li>"
		fi
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

# select_option "name" "value"
select_option() {
	local v=$2
	[ -z "$v" ] && v=$1
	local s=""
	[ "$v" = eval \$$v ] && $s=" selected"
	echo "<option value=\"$v\"$s>$1</label>"
}

# pre "text" "classes" "extras"
pre() {
	# replace <, >, &, ", and ' with HTML entities
	tag "pre" "$(echo -e "$1" | sed "s/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g;s/\"/\&quot;/g")" "$2" "$3"
}

progressbar() {
	local c="primary"
	[ "$1" -ge "75" ] && c="danger"
	echo "<div class=\"progress\" role=\"progressbar\" aria-valuenow=\"$1\" aria-valuemin=\"0\" aria-valuemax=\"100\">" \
		"<div class=\"progress-bar progress-bar-striped progress-bar-animated bg-$c\" style=\"width:$1%\"></div>" \
		"</div>"
}

# redirect_back "flash class" "flash text"
redirect_back() {
	redirect_to "${HTTP_REFERER:-/}" "$1" "$2"
}

# redirect_to "url" "flash class" "flash text"
redirect_to() {
	[ -n "$3" ] && alert_save "$2" "$3"
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
	echo "<h4 class=\"text-danger\">Oops. Something happened.</h4>"
	alert "$1" "danger"
}

# report_log "text" "extras"
report_log() {
	pre "$1" "small" "$2"
}

report_command_error() {
	echo "<h4 class=\"text-danger\">Oops. Something happened.</h4><div class=\"alert alert-danger\">"
	report_command_info "$1" "$2"
	echo "</div>"
}

report_command_info() {
	echo "<h4># $1</h4><pre class=\"small\">$2</pre>"
}

# row_ "class"
row_() {
	echo "<div class\"row $1\" $2>"
}

_row() {
	echo "</div>"
}

row() {
	row_ "$2"
	echo "$1"
	_row
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
	# convert html entities
	eval $n=$(echo \${$n//\\\"/\&quot\;})
	eval $n=$(echo \${$n//\$/\\\$})
}

set_error_flag() {
	alert_append "danger" "$1"
	error=1
}

generate_signature() {
	echo "$soc, $sensor, $flash_size_mb MB, $network_hostname, $network_macaddr" >$signature_file
}

signature() {
	[ ! -f "$signature_file" ] && generate_signature
	cat $signature_file
}

tab_lap() {
	local c=""
	local s="false"
	[ -n "$3" ] && s="true" && c=" active"
	echo "<li class=\"nav-item\" role=\"presentation\"><button role=\"tab\" id=\"#${1}-tab\"" \
		" class=\"nav-link$c\" data-bs-toggle=\"tab\" data-bs-target=\"#${1}-tab-pane\"" \
		" aria-controls=\"${1}-tab-pane\" aria-selected=\"$s\">$2</button></li>"
}

t_label() {
	eval "echo \$tL_$1"
}

t_value() {
	# eval "echo \"\$$1\""
	#eval echo '$'$1
	eval echo "\$$1"
}

update_caminfo() {
	debug=$(get debug)
	[ -z "$debug" ] && debug=0

	local tmpfile="$ui_tmp_dir/sysinfo.tmp"
	:>$tmpfile
	# add all web-related config files
	# do not include ntp
	for _f in admin email ftp motion socks5 speaker telegram webhook yadisk; do
		[ -f "$ui_config_dir/${_f}.conf" ] || continue
		cat "$ui_config_dir/${_f}.conf" >>$tmpfile
	done; unset _f

	# Hardware

	# FIXME
	flash_type="NOR"
	flash_size=$((0x0$(awk '/"all"/ {print $2}' /proc/mtd)))
	if [ "$flash_size" -eq 0 ]; then
		mtd_size=$(grep -E "nor|nand" $(ls /sys/class/mtd/mtd*/type) | sed -E "s|type.+|size|g")
		flash_size=$(awk '{sum+=$1} END{print sum}' $mtd_size)
	fi
	flash_size_mb=$((flash_size / 1024 / 1024))

	sensor=$(cat /etc/sensor/model)
	soc=$(/usr/sbin/soc -m)
	soc_family=$(/usr/sbin/soc -f)

	# Firmware
	uboot_version=$(get ver)
	[ -z "$uboot_version" ] && uboot_version=$(strings /dev/mtdblock0 | grep '^U-Boot \d' | head -1)
	fw_version=$(grep "^VERSION" /etc/os-release | cut -d= -f2 | tr -d /\"/)
	fw_build=$(grep "^GITHUB_VERSION" /etc/os-release | cut -d= -f2 | tr -d /\"/)

	# WebUI version
	ui_password=$(grep root /etc/shadow|cut -d: -f2)

	# Network
	network_dhcp="false"
	if [ -f /etc/resolv.conf ]; then
		network_dns_1=$(cat /etc/resolv.conf | grep nameserver | sed -n 1p | cut -d' ' -f2)
		network_dns_2=$(cat /etc/resolv.conf | grep nameserver | sed -n 2p | cut -d' ' -f2)
	fi
	network_hostname=$(hostname -s)
	network_interfaces=$(/sbin/ifconfig | grep '^\w' | awk {'print $1'} | tr '\n' ' ' | sed 's/ $//' | sed -E 's/\blo\b\s?//')

	# if no default interface then no gateway nor wan mac present
	network_default_interface=$(ip r | sed -nE '/default/s/.+dev (\w+).+?/\1/p' | head -n 1)
	if [ -n "$network_default_interface" ]; then
		[ "$(cat /etc/network/interfaces.d/$network_default_interface | grep inet | grep dhcp)" ] && network_dhcp="true"
		network_gateway=$(ip r | sed -nE "/default/s/.+ via ([0-9\.]+).+?/\1/p")
	else
		network_default_interface=$(ip r | sed -nE 's/.+dev (\w+).+?/\1/p' | head -n 1)
		network_gateway='' # $(get gatewayip) # FIXME: Why do we need this?
		# network_macaddr=$(get ethaddr)      # FIXME: Why do we need this?
		# network_address=$(get ipaddr)       # FIXME: Maybe use $(hostname -i) that would return 127.0.1.1?
		# network_netmask=$(get netmask)
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

	local variables="flash_size flash_size_mb flash_type fw_version fw_build
network_address network_cidr network_default_interface network_dhcp network_dns_1
network_dns_2 network_gateway network_hostname network_interfaces network_macaddr network_netmask
overlay_root soc soc_family sensor tz_data tz_name uboot_version ui_password"
	local v
	for v in $variables; do
		eval "echo $v=\'\$$v\'>>$tmpfile"
	done
	# sort content alphabetically
	sort <$tmpfile | sed /^$/d >$sysinfo_file && rm $tmpfile && unset tmpfile

	echo -e "debug=${debug}\n# caminfo $(date +"%F %T")\n" >>$sysinfo_file
	generate_signature
}

update_uboot_env() {
	local name="$1"
	local value="$2"
	[ "$value" != "$(get $name)" ] && fw_setenv $name $value
}

xl() {
	echo "<b>$1</b>"
	local o=$($1 2>&1)
	[ $? -ne 0 ] && error=1
	[ -n "$o" ] && echo "<div class=\"x-small p-3\"><i>$o</i></div>"
}

read_from_env() {
	local tmpfile=$(mktemp)
	fw_printenv | grep ^${1}_ > $tmpfile
	. $tmpfile
	rm $tmpfile
}

d() {
	echo "$1" >&2
}

dump() {
	echo "Content-Type: text/plain; charset=UTF-8
Date: $(time_http)
Pragma: no-cache
Connection: close

--------------------
$(env|sort)
--------------------
"
	for x in $1; do
		echo -e "$x = $(eval echo \$$x)\n"
	done
	exit
}

include() {
	[ -f "$1" ] && . "$1"
}

ui_tmp_dir=/tmp/webui
ui_config_dir=/etc/webui

alert_file=/tmp/webui/alert.txt
signature_file=/tmp/webui/signature.txt
sysinfo_file=/tmp/sysinfo.txt

[ -d $ui_tmp_dir ] || mkdir -p $ui_tmp_dir
[ -d $ui_config_dir ] || mkdir -p $ui_config_dir
[ -f $sysinfo_file ] || update_caminfo
include $sysinfo_file

pagename=$(basename "$SCRIPT_NAME")
pagename="${pagename%%.*}"

include _locale_en.cgi
include /etc/webui/mqtt.conf
include /etc/webui/socks5.conf
include /etc/webui/speaker.conf
include /etc/webui/telegram.conf
include /etc/webui/webhook.conf
include /etc/webui/webui.conf
include /etc/webui/yadisk.conf

# reload_locale

# FIXME: mandatory password change disabled for testing purposes
check_password
%>
