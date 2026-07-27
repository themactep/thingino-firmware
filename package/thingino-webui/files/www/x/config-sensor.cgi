#!/bin/haserl --upload-limit=1024 --upload-dir=/tmp
<%in _common.cgi %>
<%
page_title="Sensor"

SENSOR_IQ_PATH="/usr/share/sensor"
SENSOR_IQ_UPLOAD_PATH="/opt/sensor"
SENSOR_FILE="${SENSOR}-$(fw_printenv -n soc).bin"

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	if [ "$POST_action" = "restore_factory_file" ]; then
		rm "$SENSOR_IQ_UPLOAD_PATH/uploaded.bin"
		rm "/overlay$SENSOR_IQ_PATH/$SENSOR_FILE"; mount -o remount /
		touch /tmp/sensor-iq-restart.txt
	elif [ -n "$HASERL_sensorfile_path" ]; then
		if [ $(stat -c%s $HASERL_sensorfile_path) -eq 0 ]; then
			set_error_flag "File upload failed. Empty file?"
		else
			mkdir "$SENSOR_IQ_UPLOAD_PATH"
			mv "$HASERL_sensorfile_path" "$SENSOR_IQ_UPLOAD_PATH/uploaded.bin"
			ln -sf "$SENSOR_IQ_UPLOAD_PATH/uploaded.bin" "$SENSOR_IQ_PATH/${SENSOR_FILE}"
			touch /tmp/sensor-iq-restart.txt
		fi
	fi
	redirect_to $SCRIPT_NAME
fi
%>
<%in _header.cgi %>
<div class="row g-4">
<div class="col col-lg-4">
<div class="alert alert-success">
<h4>Restore sensor IQ file</h4>
<p>The original file bundled with the firmware will be restored.</p>
<form action="<%= $SCRIPT_NAME %>" method="post">
<input type="hidden" name="action" value="restore_factory_file">
<% button_submit "Restore factory default" "success" %>
</form>
</div>
</div>
<div class="col col-lg-4">
<div class="alert alert-danger">
<h4>Install sensor IQ file</h4>
<p>Upload a custom sensor IQ file for <%= $soc_model %> and <%= $sensor_model %>,
 e.g. from stock firmware backup. In case it does not work for you, restore the bundled file.</p>
<p>Attention! This file won't survive a system upgrade, even partial!</p>
<form action="<%= $SCRIPT_NAME %>" method="post" enctype="multipart/form-data">
<% field_file "sensorfile" %>
<% button_submit "Install" "danger" %>
</form>
</div>
</div>
</div>
<%in _footer.cgi %>
