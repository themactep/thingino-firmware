#!/usr/bin/haserl
<%in p/common.cgi %>
<%
[ -z "$GET_f" ] && set_error_flag "Nothing to restore."

file=$GET_f
[ ! -f "/rom/${file}" ] && set_error_flag "File /rom/${file} not found!"

[ -n "$error" ] && redirect_back

cp "/rom/${file}" "${file}"
if [ $? -eq 0 ]; then
	redirect_back "success" "File ${file} restored to firmware defaults."
else
	redirect_back "danger" "Cannot restore ${file}!"
fi
%>
