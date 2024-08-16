#!/usr/bin/haserl
<%in _common.cgi %>
<%
files=$(ls -1 /proc/umap/)
file=$GET_file
if [ -z "$file" ]; then
	file=$(echo $files | awk '{print $1}')
	redirect_to "${SCRIPT_NAME}?file=${file}"
fi
page_title="Information from /proc/umap"
%>
<%in _header.cgi %>
<p><%
for f in $files; do
	css="btn btn-sm btn-primary"
	[ "$f" = "$file" ] && css="${css} active"
	echo "<a class=\"${css}\" href=\"${SCRIPT_NAME}?file=${f}\">${f}</a>"
done
%>
</p>
<% ex "cat /proc/umap/${file}" %>
<% button_refresh %>
<%in _footer.cgi %>
