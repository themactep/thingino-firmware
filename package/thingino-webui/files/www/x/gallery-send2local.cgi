#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Local Recordings Gallery"
default_for send_local_save_dir "/mnt/records"
dir="$send_local_save_dir"

safe_path() {
	real=$(readlink -f -- "$1") && [ -e "$real" ] && [ "${real#"$dir"/}" != "$real" ]
}

if [ -n "$GET_dl" ]; then
	file="$GET_dl"
	safe_path "$file" || redirect_back "danger" "Forbidden"
	length=$(stat -c%s "$file")
	timemodepoch=$(stat -c%Y "$file")
	timestamp=$(TZ=GMT0 date +"%a, %d %b %Y %T %Z" --date="@$timemodepoch")
	http_header "HTTP/1.0 200 OK"
	http_header "Date: $timestamp"
	http_header "Server: $SERVER_SOFTWARE"
	http_header "Content-type: application/octet-stream"
	http_header "Content-Length: $length"
	http_header "Content-Disposition: attachment; filename=$(basename "$file")"
	http_header "Cache-Control: no-store"
	http_header "Pragma: no-cache"
	http_header
	cat "$file"
	exit 0
fi
%>

<%in _header.cgi %>

<%
[ -d "$dir" ] || mkdir -p "$dir"
list=$(ls -1t $dir/*.jpg 2>/dev/null | tr '\n' ' ')
%>

<% if [ -z "$list" ]; then %>
<div class="alert alert-info">No saved videos found in <code><%= $dir %></code>.</div>
<% else %>
<div class="row row-cols-2 row-cols-md-3 row-cols-lg-4 g-3">
<%
for f in $list; do
	[ -f "$f" ] || continue
	thumb="$f"
	base=$(basename "$f")
	name_noext="${base%.*}"
	video_ext="mp4"
	vid="$dir/${name_noext}.${video_ext}"
	if [ ! -f "$vid" ]; then
		video_ext="mov"
		vid="$dir/${name_noext}.${video_ext}"
		[ ! -f "$vid" ] && continue
	fi
	c=1
%>
	<% while [ -f "$vid" ]; do %>
	<div class="col">
		<div class="card h-100 shadow-sm">
			<a href="?dl=<%= $vid %>" class="position-relative">
				<img src="?dl=<%= $thumb %>" class="card-img-top" alt="<%= $base %>">
				<span class="position-absolute top-0 start-0 badge rounded-pill bg-dark m-2">▶</span>
			</a>
			<div class="card-body p-2">
				<p class="card-text small text-center"><%= $name_noext %></p>
			</div>
		</div>
	</div>
	<%
		c=$((c+1))
		vid="$dir/${name_noext}_${c}.${video_ext}"
	done
done
%>
</div>
<% fi %>

<%in _footer.cgi %>
