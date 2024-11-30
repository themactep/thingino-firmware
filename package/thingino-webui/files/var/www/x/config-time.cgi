#!/bin/haserl
<%in _common.cgi %>
<%
plugin="time"
page_title="Time"

config_file="$ui_config_dir/$plugin.conf"
include $config_file

ntpd_static_config=/etc/default/ntp.conf
ntpd_working_config=/tmp/ntp.conf
ntpd_sync_status=/run/sync_status
seq=$(seq 0 3)

if [ "POST" = "$REQUEST_METHOD" ]; then
	case "$POST_action" in
		reset)
			cp -f /rom$ntpd_static_config $ntpd_working_config
			;;
		set)
			date -s "$POST_time"
			;;
		update)
			# check for mandatory data
			error_if_empty "$POST_tz_name" "Empty timezone name."
			error_if_empty "$POST_tz_data" "Empty timezone value."

			if [ -z "$error" ]; then
				[ "$tz_data" = "$POST_tz_data" ] || echo "$POST_tz_data" >/etc/TZ
				[ "$tz_name" != "$POST_tz_name" ] && \
					echo "$POST_tz_name" >/etc/timezone && \
					fw_setenv timezone "$POST_tz_name"

				tmp_file=$(mktemp)
				for i in $seq; do
					eval s="\$POST_ntp_server_$i"
					[ -n "$s" ] && echo "server $s iburst" >>$tmp_file
				done; unset i; unset s

				mv $tmp_file $ntpd_static_config
				cp $ntpd_static_config $ntpd_working_config
				chmod 444 $ntpd_static_config
				chmod 444 $ntpd_working_config
				service timezone restart > /dev/null
			fi
			;;
	esac

	update_caminfo
	redirect_to $SCRIPT_NAME
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_hidden "action" "update" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<h3>Time Zone</h3>
<datalist id="tz_list"></datalist>
<p class="string">
<label for="tz_name" class="form-label">Zone name</label>
<input type="text" id="tz_name" name="tz_name" value="<%= $tz_name %>" class="form-control" list="tz_list">
<span class="hint text-secondary">Start typing the name of the nearest large city in the box above then select from available variants.</span>
</p>
<p><a href="#" id="frombrowser">Pick up timezone from browser</a></p>
<p class="string">
<label for="tz_data" class="form-label">Zone string</label>
<input type="text" id="tz_data" name="tz_data" value="<%= $tz_data %>" class="form-control" readonly>
<span class="hint text-secondary">Control string of the timezone selected above. Read-only field, only for monitoring.</span>
</p>
</div>
<div class="col">
<h3>Time Synchronization</h3>
<%
for i in $seq; do
	x=$(expr $i + 1)
	[ -f "/etc/ntp.conf" ] && eval ntp_server_$i="$(sed -n ${x}p /etc/ntp.conf | cut -d' ' -f2)"
	field_text "ntp_server_$i" "NTP Server $((i + 1))"
done; unset i; unset x
%>
</div>
<div class="col">
<% button_sync_time %>
<p id="sync-time-wrapper"></p>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "get timezone" %>
<% ex "cat /etc/timezone" %>
<% ex "cat /etc/TZ" %>
<% ex "echo \$TZ" %>
<% [ -f "$ntpd_working_config" ] && ex "cat $ntpd_working_config" %>
<% [ -f "$ntpd_static_config" ] && ex "cat $ntpd_static_config" %>
<% [ -f "$ntpd_sync_status" ] && ex "cat $ntpd_sync_status" %>
</div>

<script>
	function findTimezone(tz) {
		return tz.n == $("#tz_name").value;
	}

	function updateTimezone() {
		const tz = TZ.filter(findTimezone);
		$("#tz_data").value = (tz.length == 0) ? "" : tz[0].v;
	}

	function useBrowserTimezone(event) {
		event.preventDefault();
		$("#tz_name").value = Intl.DateTimeFormat().resolvedOptions().timeZone.replaceAll('_', ' ');
		updateTimezone();
	}

	$('#sync-time').onclick = (ev) => {
		ev.preventDefault();
		fetch('/x/json-sync-time.cgi?' + new URLSearchParams({ "ts": Date.now() }).toString())
			.then(res => res.json())
			.then(json => {
				p = document.createElement('p');
				p.classList.add('alert', 'alert-' + json.result);
				p.textContent = json.message;
				$('#sync-time-wrapper').replaceWith(p);
			})
	}

	function populate_timezones() {
		if (navigator.userAgent.includes("Android") && navigator.userAgent.includes("Firefox")) {
			const sel = document.createElement("select");
			sel.classList.add("form-select");
			sel.name = "tz_name";
			sel.id = "tz_name";
			sel.options.add(new Option());
			let opt;
			TZ.forEach(function (tz) {
				opt = new Option(tz.n);
				opt.selected = (tz.n == tzn.value);
				sel.options.add(opt);
			});
			tzn.replaceWith(sel);
		} else {
			const el = $("#tz_list");
			el.innerHTML = "";
			TZ.forEach(function (tz) {
				const o = document.createElement("option");
				o.value = tz.n;
				el.appendChild(o);
			});
		}
	}

	let TZ;

	fetch(document.location.protocol + '//' + document.location.host + "/a/tz.json")
		.then(res => res.json())
		.then(json => {
			TZ = json;
			populate_timezones(json);
		})

	const tzn = $("#tz_name");
	tzn.onfocus = (ev) => ev.target.select();
	tzn.onselectionchange = updateTimezone;
	tzn.onchange = updateTimezone;
	$("#frombrowser").onclick = useBrowserTimezone;
</script>
<%in _footer.cgi %>
