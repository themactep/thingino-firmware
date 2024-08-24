#!/bin/haserl
<%in _common.cgi %>
<%
if [ "POST" = "$REQUEST_METHOD" ]; then
	editor_file="$POST_editor_file"
	editor_text="$POST_editor_text"
	editor_backup="$POST_editor_backup"

	# strip carriage return (\u000D) characters
	editor_text=$(echo "$editor_text" | sed s/\\r//g)

	case "$POST_action" in
		restore)
			if [ ! -f "$editor_file" ]; then
				redirect_to "${SCRIPT_NAME}?f=${editor_file}" "danger" "File not found!"
			elif [ ! -f "$editor_file.backup" ]; then
				redirect_to "${SCRIPT_NAME}?f=${editor_file}" "danger" "File not found!"
			else
				mv "$editor_file.backup" "$editor_file"
				redirect_to "${SCRIPT_NAME}?f=${editor_file}" "success" "File restored from backup."
			fi
			;;
		save)
			if [ -z "$editor_text" ]; then
				alert_save "warning" "Empty payload. File not saved!"
			else
				if [ -n "$editor_backup" ]; then
					cp "$editor_file" "${editor_file}.backup"
				else
					[ -f "${editor_file}.backup" ] && rm "${editor_file}.backup"
				fi
			echo "$editor_text" >"$editor_file"
			redirect_to "${SCRIPT_NAME}?f=${editor_file}" "success" "File saved."
			fi
			;;
		*)
			alert_save "danger" "UNKNOWN ACTION: $POST_action"
			;;
	esac
else
	editor_file="$GET_f"
	if [ ! -f "$editor_file" ]; then
		alert_save "danger" "File not found!"
	elif [ -n "$editor_file" ]; then
		if [ "b" = "$( (cat -v "$editor_file" | grep -q "\^@") && echo "b" )" ]; then
			alert_save "danger" "Not a text file!"
		elif [ "$(stat -c%s $editor_file)" -gt "102400" ]; then
			alert_save "danger" "Uploded file is too large!"
		else
			editor_text="$(cat $editor_file | sed "s/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g;s/\"/\&quot;/g")"
		fi
	fi
fi

page_title="Text editor"
%>
<%in _header.cgi %>

<ul class="nav nav-tabs" role="tablist">
<% tab_lap "edit" "Editor" "active" %>
<% tab_lap "file" "File" %>
<% if [ -f "${editor_file}.backup" ]; then %>
<% tab_lap "back" "Backup" %>
<% tab_lap "diff" "Difference" %>
<% fi %>
</ul>

<div class="tab-content p-2" id="tab-content">
<div id="edit-tab-pane" role="tabpanel" class="tab-pane fade show active" aria-labelledby="edit-tab" tabindex="0">
<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_hidden "action" "save" %>
<% field_hidden "editor_file" "$editor_file" %>
<% field_textedit "editor_text" "$editor_file" "File content" %>
<p class="boolean"><span class="form-check form-switch">
<input type="checkbox" id="editor_backup" name="editor_backup" value="true" class="form-check-input" role="switch">
<label for="editor_backup" class="form-label form-check-label">Create backup file</label>
</span></p>
<% button_submit %>
</form>
</div>

<div id="file-tab-pane" role="tabpanel" class="tab-pane fade" aria-labelledby="file-tab" tabindex="0">
<% ex "cat -t $editor_file" %>
</div>

<% if [ -f "${editor_file}.backup" ]; then %>
<div id="back-tab-pane" role="tabpanel" class="tab-pane fade" aria-labelledby="back-tab" tabindex="0">
<% ex "cat -t ${editor_file}.backup" %>
<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_hidden "action" "restore" %>
<% field_hidden "editor_file" "$editor_file" %>
<% button_submit "Restore" "danger" %>
</form>
</div>
<div id="diff-tab-pane" role="tabpanel" class="tab-pane fade" aria-labelledby="diff-tab" tabindex="0">
<h4>Changes against previous version</h4>
<%
# it's ugly but shows non-printed characters (^M/^I)
_n=$(basename $editor_file)
cat -t $editor_file >/tmp/${_n}.np
cat -t ${editor_file}.backup >/tmp/${_n}.backup.np
pre "$(diff -s -d -U0 /tmp/${_n}.backup.np -L ${editor_file}.backup /tmp/${_n}.np -L $editor_file)"
rm /tmp/${_n}.np /tmp/${_n}.backup.np
unset _n
%>
</div>
<% fi %>
</div>

<%in _footer.cgi %>
