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
		cp -f "/rom$SENSOR_IQ_PATH/$SENSOR_FILE" "$SENSOR_IQ_PATH"
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
<h4>Restore factory sensor IQ file</h4>
<p>The default file will be restored.
<form action="<%= $SCRIPT_NAME %>" method="post">
<input type="hidden" name="action" value="restore_factory_file">
<% button_submit "Restore factory default" "success" %>
</form>
</div>
<div class="alert alert-danger">
<h4>Install sensor IQ file</h4>
<p>Provide here a sensor IQ file compatible with (<%= $soc_model + $sensor_model + lens %>).
 <br/>This file can be found in stock firmware for example.
 <br/>It won't resist a system upgrade, even partial.
 <br/>In case it does not work, restore the factory file.
 <br/>
</p>
<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4" enctype="multipart/form-data">
<% field_file "sensorfile" %>
<% button_submit "Install" "danger" %>
</form>
</div>
</div>
</div>
<%in _footer.cgi %>
