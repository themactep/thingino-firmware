#!/bin/haserl
<%in _common.cgi %>
<%
page_title="File Manager"
[ -n "$GET_cd" ] && dir=${GET_cd}
# expand traversed path to a real directory name
dir=$(cd ${dir:-/}; pwd)
# no need for POSIX awkward double root
dir=$(echo $dir | sed s#^//#/#)
%>
<%in _header.cgi %>
<h4><%= $dir %></h4>
<%
lsfiles=$(ls -al $dir)
IFS=$'\n'
for line in $lsfiles; do
	echo "<div class=\"row mb-3\">"
	# skip total line
	[ -n "$(echo $line | grep ^total)" ] && continue
	# skip .
	[ -n "$(echo $line | grep \\s\.$)" ] && continue

	name=${line##* }; line=${line% *}
	permissions=$(echo $line | awk '{print $1}')
	# hardlinks=$(echo $line | awk '{print $2}')
	# owner=$(echo $line | awk '{print $3}')
	# group=$(echo $line | awk '{print $4}')
	filesize=$(echo $line | awk '{print $5}')
	timestamp=$(echo $line | awk '{print $6,$7,$8}')

	path=$(echo "${dir}/${name}" | sed s#^//#/#)
	echo "<div class=\"col-10 col-lg-4\">"
	if [ -d "${path}" ]; then
		echo "<a href=\"?cd=${path}\" class=\"fw-bold\">${name}</a>"
	else
		echo "<a href=\"dl.cgi?file=${path}\" class=\"fst-italic\">${name}</a>"
	fi
	echo "</div>"
	echo "<div class=\"col-2 col-lg-2 font-monospace text-end\">${filesize}</div>"
	echo "<div class=\"col-6 col-lg-2 font-monospace text-center\">${permissions}</div>"
	echo "<div class=\"col-6 col-lg-2 font-monospace text-end\">${timestamp}</div>"
	echo "</div>"
done
IFS=$IFS_ORIG
%>
<%in _footer.cgi %>
