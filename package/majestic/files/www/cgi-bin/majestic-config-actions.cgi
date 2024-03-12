#!/usr/bin/haserl --upload-limit=20 --upload-dir=/tmp
<%in p/common.cgi %>
<%
config_file=/etc/majestic.yaml
config_file_fw=/rom/etc/majestic.yaml

if [ "POST" = "$REQUEST_METHOD" ]; then
	case "$POST_action" in
		backup)
			echo "HTTP/1.0 200 OK
Date: $(time_http)
Server: $SERVER_SOFTWARE
Content-type: text/plain
Content-Disposition: attachment; filename=majestic.yaml
Content-Length: $(stat -c%s $config_file)
Cache-Control: no-store
Pragma: no-cache
"
			cat $config_file
			;;
		patch)
			patch_file=/tmp/majestic.patch
			diff $config_file_fw $config_file >$patch_file
			echo "HTTP/1.0 200 OK
Date: $(time_http)
Server: $SERVER_SOFTWARE
Content-type: text/plain
Content-Disposition: attachment; filename=majestic.$(time_epoch).patch
Content-Length: $(stat -c%s $patch_file)
Cache-Control: no-store
Pragma: no-cache
"
			cat $patch_file
			rm $patch_file
			;;
		reset)
			/usr/sbin/sysreset -m
			redirect_back
			;;
		restore)
			magicnum="23206d616a6573746963"
			file="$POST_mj_restore_file"
			file_name="$POST_mj_restore_file_name"
			file_path="$POST_mj_restore_file_path"
			error=""
			[ -z "$file_name" ] && error="No file found! Did you forget to upload?"
			[ ! -r "$file" ] && error="Cannot read uploded file!"
			[ "$(stat -c%s $file)" -gt "$maxsize" ] && error="Uploded file is too large! $(stat -c%s $file) > ${maxsize}."
			#[ "$magicnum" -ne "$(xxd -p -l 10 $file)" ] && error="File magic number does not match. Did you upload a wrong file? $(xxd -p -l 10 $file) != $magicnum"
			if [ -z "$error" ]; then
				# yaml-cli -i $POST_upfile -o /tmp/majestic.yaml # FIXME: sanitize
				mv $file_path /etc/majestic.yaml
				redirect_to $SCRIPT_NAME
			fi
			;;
	esac
fi
%>

<% page_title="Majestic Maintenance" %>
<%in p/header.cgi %>

<div class="row row-cols-1 row-cols-lg-3 g-4 mb-4">
<div class="col">
<h3>Backup Config</h3>
<p>Download recent majestic.yaml to preserve changes you made to the default configuration.</p>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "backup" %>
<% button_submit "Download config" %>
</form>
</div>
<div class="col">
<h3>Restore Config</h3>
<p>Restore custom Majestic configuration from a saved copy of majestic.yaml file.</p>
<form action="<%= $SCRIPT_NAME %>" method="post" enctype="multipart/form-data">
<% field_hidden "action" "restore" %>
<% field_file "mj_restore_file" "Backup file" "majestic.yaml" %>
<% button_submit "Upload config" "warning" %>
</form>
</div>
<div class="col">
<h3>Review Difference</h3>
<p>Compare recent majestic.yaml with the one supplied with the firmware.</p>
<a class="btn btn-primary" href="majestic-config-compare.cgi">Review changes</a>
</div>
<div class="col">
<h3>Export Patch</h3>
<p>Export changes made to majestic.yaml in a form of a patch file.</p>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "patch" %>
<% button_submit "Download patch file" %>
</form>
</div>
<div class="col">
<h3>Reset</h3>
<% if [ "$(diff -q $config_file_fw $config_file)" ]; then %>
<p>Reset Majestic configuration to its original state, as supplied with the firmware.</p>
<% button_mj_reset %>
<% else %>
<p>There is nothing to reset. Recent Majestic configuration does not differ from the one supplied with the firmware.</p>
<% fi %>
</div>
</div>

<%in p/footer.cgi %>
