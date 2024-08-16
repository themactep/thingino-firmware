#!/usr/bin/haserl
<%in _common.cgi %>
<% page_title="SD Card" %>
<%in _header.cgi %>
<% if ! ls /dev/mmc* >/dev/null 2>&1; then %>
<div class="alert alert-danger">
<h4>Does this camera support SD Card?</h4>
<p>Your camera does not have an SD Card slot or SD Card is not inserted.</p>
</div>
<%
else
	card_device="/dev/mmcblk0"
	card_partition="${card_device}p1"
	mount_point="${card_partition//dev/mnt}"
	error=""
	_o=""

	if [ -n "$POST_doFormatCard" ]; then
%>
<div class="alert alert-danger">
<h4>ATTENTION! SD Card formatting takes time.</h4>
<p>Please do not refresh this page. Wait until partition formatting is finished!</p>
</div>
<%
		if [ "$(grep $card_partition /etc/mtab)" ]; then
			_c="umount $card_partition"
			_o="${_o}\n${_c}\n$($_c 2>&1)"
			[ $? -ne 0 ] && error="Cannot unmount SD Card partition."
		fi

		if [ -z "$error" ]; then
			_c="echo -e 'o\nn\np\n1\n\n\nt\n6\nw'|fdisk $card_device"
			_o="${_o}\n${_c}\n$($_c 2>&1)"
			[ $? -ne 0 ] && error="Cannot create an SD Card partition."
		fi

		if [ -z "$error" ]; then
			_c="mkfs.vfat -v -n thingino $card_partition"
			_o="${_o}\n${_c}\n$($_c 2>&1)"
			[ $? -ne 0 ] && error="Cannot format SD Card partition."
		fi

		if [ -z "$error" ] && [ ! -d "$mount_point" ]; then
			_c="mkdir -p $mount_point"
			_o="${_o}\n${_c}\n$($_c 2>&1)"
			[ $? -ne 0 ] && error="Cannot create SD Card mount point."
		fi

		if [ -z "$error" ]; then
			_c="mount $card_partition $mount_point"
			_o="${_o}\n${_c}\n$($_c 2>&1)"
			[ $? -ne 0 ] && error="Cannot re-mount SD Card partition."
		fi

		if [ -n "$error" ]; then
			report_error "$error"
			[ -n "$_c" ] && report_command_info "$_c" "$_o"
		else
			report_log "$_o"
		fi
%>
<a class="btn btn-primary" href="/">Go home</a>
<%
	else
%>
<h4>SD card partitions</h4>
<%
		partitions=$(df -h | grep 'dev/mmc')
		echo "<pre class=\"small\">${partitions}</pre>"

		if [ -n "$partitions" ]; then
%>
<h4>Browse files on these partitions</h4>
<div class="mb-4">
<%
			IFS=$'\n'
			for i in $partitions; do
				# _mount="${i##* }"
				_mount=$(echo $i | awk '{print $6}')
				echo "<a href=\"file-manager.cgi?cd=${_mount}\" class=\"btn btn-primary\">${_mount}</a>"
				unset _mount
			done
			IFS=$IFS_ORIG
			unset _partitions
%>
</div>
<%
		fi
%>
<h4>Format SD card</h4>
<div class="alert alert-danger">
<h4>ATTENTION! Formatting will destroy all data on the SD Card.</h4>
<p>Make sure you have a backup copy if you are going to use the data in the future.</p>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "doFormatCard" "true" %>
<% button_submit "Format SD Card" "danger" %>
</form>
</div>
<%
	fi
fi
%>
<%in _footer.cgi %>
