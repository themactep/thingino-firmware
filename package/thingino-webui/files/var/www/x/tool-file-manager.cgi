#!/bin/haserl
<%in _common.cgi %>
<%
page_title="File Manager"

if [ -n "$GET_play" ]; then
	file=$GET_play
	check_file_exist $file
	filelength=$(stat -c%s $file)

	if ! env | grep -q ^HTTP_RANGE; then
		echo -en "HTTP/1.1 200 OK\r\n"
		echo -en "Content-Type: video/mp4\r\n"
		echo -en "Accept-Ranges: bytes\r\n"
		echo -en "Content-Length: $filelength\r\n"
		echo -en "\r\n"
		cat $file
		exit 0
	fi

	start=$(env | awk -F'[=-]' '/^HTTP_RANGE=/{print $3}')
	[ -z "$start" ] && start=0

	if [ "$start" -gt "$filelength" ]; then
		echo -en "HTTP/1.1 416 Requested Range Not Satisfiable\r\n"
		echo -en "Content-Range: bytes */$filelength\r\n"
		echo -en "\r\n"
		exit 0
	fi

	end=$(env | awk -F'[=-]' '/^HTTP_RANGE=/{print $4}')
	[ -z "$end" ] && end=$((filelength - 1))
	blocksize=$((end - start + 1))

	echo -en "HTTP/1.1 206 Partial Content\r\n"
	echo -en "Content-Range: bytes $start-$end/$filelength\r\n"
	echo -en "Content-Length: $blocksize\r\n"
	echo -en "\r\n"
	dd if=$file skip=$start bs=$blocksize count=1 iflag=skip_bytes
	exit 0
fi

if [ -n "$GET_dl" ]; then
	file=$GET_dl
	check_file_exist $file
	length=$(stat -c%s $file)
	timemodepoch=$(stat -c%Y $file)
	timestamp=$(TZ=GMT0 date +"%a, %d %b %Y %T %Z" --date="@$timemodepoch")
	echo -en "HTTP/1.0 200 OK\r\n
Date: $timestamp\r\n
Server: $SERVER_SOFTWARE\r\n
Content-type: application/octet-stream\r\n
Content-Length: $length\r\n
Content-Disposition: attachment; filename=$(basename $file)\r\n
Cache-Control: no-store\r\n
Pragma: no-cache\r\n
\r\n
"
	cat $file
	exit 0
fi
%>
<%in _header.cgi %>
<%
path2links() {
	echo -n "<a href=\"?cd=/\">⌂</a>"
	for d in ${1//\// }; do
		d2="$d2/$d"
		echo -n "/<a href=\"?cd=$d2\">$d</a>"
	done
}
# expand traversed path to a real directory name
dir=$(cd ${GET_cd:-/}; pwd)
# no need for POSIX awkward double root
dir=$(echo $dir | sed s#^//#/#)
%>
<h4><% path2links "$dir" %></h4>
<table class="table files" id="filelist">
<thead>
<tr>
<th>Name</th>
<th>Size</th>
<th>Permissions</th>
<th>Date</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<div class="modal fade" id="playerModal" tabindex="-1" aria-labelledby="playerModalLabel" aria-hidden="true">
<div class="modal-dialog modal-dialog-centered modal-lg"><div class="modal-content">
<div class="modal-header"><h1 class="modal-title fs-5" id="playerModalLabel">Video Player</h1>
<button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button></div>
<div class="modal-body"></div>
<div class="modal-footer">
<a href="#" class="btn btn-primary" id="playerModalDownload">Download</a>
<button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
</div></div>
</div></div>

<script>
const path = "<%= $dir %>"
const tablebody = $('#filelist tbody')
const iconPlay = '▶️';
const iconStop = '⏹️️';
const lsJson=[<% ls -ALlp --group-directories-first --full-time $dir | awk '{print "{\"name\":\""$9"\",\"size\":\""$5"\",\"permissions\":\""$1"\",\"time\":\""$6,$7,$8"\"},"}' %>]
lsJson.forEach(file => {
	let html = '<tr><td>'
	if (file.name.endsWith('/')) {
		html += '<a href="?cd=' + path + '/' + file.name + '" class="fw-bold">' + file.name + '</a>'
	} else {
		html += '<a href="?dl=' + path + '/' + file.name + '">' + file.name + '</a>'
		if (file.name.endsWith('.mp4'))
			html += '<button type="button" class="btn btn-sm btn-primary ms-3"' +
				' data-bs-toggle="modal" data-bs-target="#playerModal"' +
				' data-bs-url="?play=' + path + '/' + file.name + '" title="Play">' +
				iconPlay + '️</button>'
	}
	html += '</td><td>' + file.size + '</td><td>' + file.permissions + '</td><td>' + file.timestamp + '</td></tr>'
	tablebody.innerHTML += html
})

const videoPlayer = document.createElement("video")
videoPlayer.id="player"
videoPlayer.classList.add("w-100", "img-fluid")
videoPlayer.controls = true

const playerModal = document.querySelector("#playerModal")
playerModal.querySelector('.modal-body').append(videoPlayer);
playerModal.addEventListener("show.bs.modal", ev => {
	const btn = ev.relatedTarget
	$('#playerModalLabel').textContent = btn.dataset.bsUrl.replace('?play=', '')
	$('#playerModalDownload').href = btn.dataset.bsUrl.replace('?play=', '?dl=')
	videoPlayer.src = btn.dataset.bsUrl
	if (videoPlayer.paused) {
		async function playVideo(el) {
			try {
				await videoPlayer.play();
			} catch (err) {
				console.debug(err)
			}
		}
	} else {
		videoPlayer.pause();
	}
})
playerModal.addEventListener("hidden.bs.modal", ev => {
	videoPlayer.pause()
})
</script>

<% env %>

<%in _footer.cgi %>
