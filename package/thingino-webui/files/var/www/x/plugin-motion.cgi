#!/bin/haserl
<%in _common.cgi %>
<%
plugin="motion"
plugin_name="Motion guard"
page_title="Motion guard"
params="enabled sensitivity send2email send2ftp send2mqtt send2telegram send2webhook send2yadisk throttle"

config_file="${ui_config_dir}/${plugin}.conf"
[ ! -f "$config_file" ] && touch $config_file

prudynt_config=/etc/prudynt.cfg
prudynt_control=/etc/init.d/S95prudynt

if [ "POST" = "$REQUEST_METHOD" ]; then
	# parse values from parameters
	for p in $params; do
		eval ${plugin}_${p}=\$POST_${plugin}_${p}
		sanitize "${plugin}_${p}"
	done; unset p

	if [ -z "$error" ]; then
		tmp_file=$(mktemp)
		for p in $params; do
			echo "${plugin}_${p}=\"$(eval echo \$${plugin}_${p})\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		tmp_file=$(mktemp -u)
		cp $prudynt_config $tmp_file
		if [ $motion_enabled = "true" ]; then
			sed -i '/^motion:/n/enabled:/{s/ false;/ true;/}' $tmp_file
		else
			sed -i '/^motion:/n/enabled:/{s/ true;/ false;/}' $tmp_file
		fi
		sed -i -E "/^motion:/n/sensitivity:/{s/: \d*;/: ${motion_sensitivity};/}" $tmp_file
		sed -i -E "/^motion:/n/cooldown_time:/{s/: \d*;/: ${motion_throttle};/}" $tmp_file
		mv $tmp_file $prudynt_config

		$prudynt_control restart >/dev/null

		update_caminfo
		redirect_to "$SCRIPT_NAME"
	fi
else
	include $config_file

	# default values
	[ -z "$motion_sensitivity" ] && motion_sensitivity=1
	[ -z "$motion_throttle"    ] && motion_throttle=10
fi
%>
<%in _header.cgi %>
<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="row g-4 mb-4">
<div class="col col-12 col-xl-4">
<% field_switch "motion_enabled" "Enable motion guard" %>
<% field_range "motion_sensitivity" "Sensitivity" "1,8,1" %>
<% field_range "motion_throttle" "Delay between alerts, sec." "5,30,1" %>
</div>
<div class="col col-12 col-xl-4">
<h3>Actions</h3>
<ul class="list-group mb-3">
<li class="list-group-item send2email">
<% field_checkbox "motion_send2email" "Send to email" "<a href=\"plugin-send2email.cgi\">Configure sending to email</a>" %>
</li>
<li class="list-group-item send2ftp">
<% field_checkbox "motion_send2ftp" "Upload to FTP" "<a href=\"plugin-send2ftp.cgi\">Configure uploading to FTP</a>" %>
</li>
<li class="list-group-item send2mqtt">
<% field_checkbox "motion_send2mqtt" "Send to MQTT" "<a href=\"plugin-send2mqtt.cgi\">Configure sending to MQTT</a>" %>
</li>
<li class="list-group-item send2telegram">
<% field_checkbox "motion_send2telegram" "Send to Telegram" "<a href=\"plugin-send2telegram.cgi\">Configure sending to Telegram</a>" %>
</li>
<li class="list-group-item send2webhook">
<% field_checkbox "motion_send2webhook" "Send to webhook" "<a href=\"plugin-send2webhook.cgi\">Configure sending to a webhook</a>" %>
</li>
<li class="list-group-item send2yadisk">
<% field_checkbox "motion_send2yadisk" "Upload to Yandex Disk" "<a href=\"plugin-send2yadisk.cgi\">Configure sending to Yandex Disk</a>" %>
</li>
</ul>
</div>
<div class="col col-12 col-xl-4">
<% [ -f $config_file ] && ex "cat $config_file" %>
</div>
</div>
<% button_submit %>
</form>
<script>
<% [ "true" != "$email_enabled" ] && echo "\$('#motion_send2email').disabled = true;" %>
<% [ "true" != "$ftp_enabled" ] && echo "\$('#motion_send2ftp').disabled = true;" %>
<% [ "true" != "$mqtt_enabled" ] && echo "\$('#motion_send2mqtt').disabled = true;" %>
<% [ "true" != "$telegram_enabled" ] && echo "\$('#motion_send2telegram').disabled = true;" %>
<% [ "true" != "$webhook_enabled" ] && echo "\$('#motion_send2webhook').disabled = true;" %>
<% [ "true" != "$yadisk_enabled" ] && echo "\$('#motion_send2yadisk').disabled = true;" %>
</script>
<%in _footer.cgi %>
