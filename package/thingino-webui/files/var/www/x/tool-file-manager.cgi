#!/bin/haserl
<%in _common.cgi %>
<%
page_title="File Manager"

if [ -n "$GET_dl" ]; then
	file=$GET_dl
	check_file_exist $file
	echo "HTTP/1.0 200 OK
Date: $(time_http)
Server: $SERVER_SOFTWARE
Content-type: application/octet-stream
Content-Disposition: attachment; filename=$(basename $file)
Content-Length: $(stat -c%s $file)
Cache-Control: no-store
Pragma: no-cache
"
	cat $file
	redirect_to $SCRIPT_NAME
fi

# expand traversed path to a real directory name
dir=$(cd ${GET_cd:-/}; pwd)

# no need for POSIX awkward double root
dir=$(echo $dir | sed s#^//#/#)
%>
<%in _header.cgi %>
<h4><%= $dir %></h4>
<table class="table files">
<thead>
<tr>
<th>Name</th>
<th>Size</th>
<th>Permissions</th>
<th>Date</th>
</tr>
</thead>
<tbody>
<%
lsfiles=$(ls -alLp --group-directories-first $dir)
IFS=$'\n'
for line in $lsfiles; do
	echo "<tr>"
	# skip .
	[ -n "$(echo $line | grep \s\./$)" ] && continue

	name=${line##* }; line=${line% *}
	path=$(echo "$dir/$name" | sed s#^//#/#)

	echo "<td>"
	if [ -d "$path" ]; then
		echo "<a href=\"?cd=$path\" class=\"fw-bold\">$name</a>"
	else
		echo "<a href=\"?dl=$path\" class=\"fw-normal\">$name</a>"
	fi
	echo "</td>"
	echo "<td>$(echo $line | awk '{print $5}')</td>"
	echo "<td>$(echo $line | awk '{print $1}')</td>"
	echo "<td>$(echo $line | awk '{print $6,$7,$8}')</td>"
	echo "</tr>"
done
IFS=$IFS_ORIG
%>
</tbody>
</table>
<%in _footer.cgi %>