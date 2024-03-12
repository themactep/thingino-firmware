#!/usr/bin/haserl
<%in p/common.cgi %>
<%
page_title="Majestic Endpoints"
url="root:root@${network_address}"
%>
<%in p/header.cgi %>
<div class="row row-cols-1 row-cols-md-2 g-4 mb-4">
<div class="col">
<h3>Video</h3>
<dl>
<dt>http://<%= $url %>/video.mp4</dt>
<dd>fMP4 video stream.</dd>
<dt>rtsp://<%= $url %>/stream=0</dt>
<dd>RTSP main stream (video0).</dd>
<dt>rtsp://<%= $url %>/stream=1</dt>
<dd>RTSP substream (video1).</dd>
<dt>http://<%= $network_address %>/hls</dt>
<dd>HLS live-streaming in web browser.</dd>
</dl>
<h3>Audio</h3>
<dl>
<dt>http://<%= $url %>/audio.opus</dt>
<dd>Opus audio stream.</dd>
<dt>http://<%= $url %>/audio.m4a</dt>
<dd>AAC audio stream.</dd>
</dl>
</div>
<div class="col">
<h3>Still Images</h3>
<dl>
<dt>http://<%= $url %>/image.jpg</dt>
<dd>Snapshot in JPEG format.<br>Optional parameters:
<ul class="small">
<li>width, height - size of resulting image</li>
<li>qfactor - JPEG quality factor (1-99)</li>
<li>color2gray - convert to grayscale</li>
<li>crop - crop resulting image as 16x16x320x320</li>
</ul>
</dd>
<dt>http://<%= $url %>/image.heif</dt>
<dd>Snapshot in HEIF format.</dd>
</dl>
<h3>Monitoring</h3>
<dl>
<dt>http://<%= $network_address %>/api/v1/config.json</dt>
<dd>Actual Majestic config in JSON format.</dd>
<dt>http://<%= $network_address %>/metrics</dt>
<dd>Node exporter for <a href="https://prometheus.io/">Prometheus</a>.</dd>
</dl>
</div>
</div>

<script>
	function initializeCopyToClipboard() {
		document.querySelectorAll("dt").forEach(function (element) {
			element.title = "Click to copy to clipboard";

			element.addEventListener("click", function (event) {
				event.target.preventDefault;
				event.target.animate({ color: 'red' }, 500);

				if (navigator.clipboard && window.isSecureContext) {
					navigator.clipboard.writeText(event.target.textContent).then(r => playChime(r));
				} else {
					let textArea = document.createElement("textarea");
					textArea.value = event.target.textContent;
					textArea.style.position = "fixed";
					textArea.style.left = "-999999px";
					textArea.style.top = "-999999px";
					document.body.appendChild(textArea);
					textArea.focus();
					textArea.select();
					return new Promise((res, rej) => {
						document.execCommand('copy') ? res() : rej();
						textArea.remove();
					});
				}
			})
		})
	}
	window.onload = function () {
		initializeCopyToClipboard();
	}
</script>
<%in p/footer.cgi %>
