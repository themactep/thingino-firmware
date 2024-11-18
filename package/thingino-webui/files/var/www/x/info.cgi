#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Information"

run_commands() {
	IFS=";"
	for c in $1; do
		ex "$c"
		button_send2tb "$c"
	done
	IFS=$IFS_ORIG
}

name=$QUERY_STRING
[ -z "$name" ] && redirect_to "$SCRIPT_NAME?system"

case "$name" in
	dmesg | logcat | logread | lsmod)
			cmd=$name
			;;
	crontab)	cmd="crontab -l"
			extras="<p><a href=\"https://devhints.io/cron\">Cron syntax cheatsheet</a></p>" \
				"<p><a class=\"btn btn-warning\" href=\"texteditor.cgi?f=/etc/crontabs/root\">Edit file</a></p>"
			;;
	httpd)		cmd="cat /etc/httpd.conf; printenv"
			extras="$(button_restore_from_rom "/etc/httpd.conf")"
			;;
	netstat)	cmd="netstat -a" ;;
	prudynt)	cmd="cat /etc/prudynt.cfg" ;;
	status)		cmd="uptime;df -T;cat /proc/meminfo | grep Mem" ;;
	system)		cmd="cat /etc/os-release" ;;
	top)		cmd="top -n 1 -b" ;;
	weblog)		cmd="cat /tmp/webui.log" ;;
	*)		cmd="true" ;;
esac
%>
<%in _header.cgi %>
<ul class="nav nav-tabs mb-3">
<%
for i in crontab dmesg httpd logcat logread lsmod netstat prudynt status system top weblog; do
	[ "$name" = "$i" ] && active=" active" || active=""
	echo "<li class=\"nav-item\"><a class=\"nav-link$active\" href=\"?$i\">$i</a></li>"
done
%>
</ul>
<%
run_commands "$cmd"
echo "$extras"
# button_refresh
# button_download "$command"
%>
<%in _footer.cgi %>
