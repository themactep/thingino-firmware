#!/usr/bin/haserl
<%in p/common.cgi %>
<%
page_title="Majestic Configuration"
supports_strftime="Supports <a href=\"https://man7.org/linux/man-pages/man3/strftime.3.html \" target=\"_blank\">strftime()</a> format."

if [ "POST" = "$REQUEST_METHOD" ]; then
	mj_conf=/etc/majestic.yaml
	temp_yaml=/tmp/majestic.yaml

	cp -f $mj_conf $temp_yaml

	OIFS=$IFS
	IFS=$'\n' # make newlines the only separator
	for yaml_param_name in $(printenv|grep POST_mj_); do
		form_field_name=$(echo $yaml_param_name | sed 's/^POST_mj_//')
		key=".$(echo $form_field_name | cut -d= -f1 | sed 's/_/./g')"

		value="$(echo $form_field_name | cut -d= -f2)"

		case "$key" in
			.video0.codec)
				if [ "off" = "$value" ]; then
					yaml-cli -s ".video0.enabled" "false" -i $temp_yaml
					value=""
				else
					yaml-cli -s ".video0.enabled" "true" -i $temp_yaml
				fi
				;;
			.video1.codec)
				if [ "off" = "$value" ]; then
					yaml-cli -s ".video1.enabled" "false" -i $temp_yaml
					value=""
				else
					yaml-cli -s ".video1.enabled" "true" -i $temp_yaml
				fi
				;;
			.audio.volume)
				if [ "off" = "$value" ]; then
					yaml-cli -s ".audio.enabled" "false" -i $temp_yaml
					value=""
				else
					yaml-cli -s ".audio.enabled" "true" -i $temp_yaml
				fi
				;;
			.osd.enabled)
				[ "false" = "$value" ] && yaml-cli -s ".motionDetect.visualize" "false" -i $temp_yaml
				;;
		esac

		# read existing value
		oldvalue=$(yaml-cli -g "$key" -i $temp_yaml)

		if [ -z "$value" ]; then
			[ -n "$oldvalue" ] && yaml-cli -d $key -i "$temp_yaml" -o "$temp_yaml"
		else
			[ "$oldvalue" != "$value" ] && yaml-cli -s $key "$value" -i "$temp_yaml" -o "$temp_yaml"
		fi
	done
	IFS=$OIFS

	[ -n "$(diff -q $temp_yaml $mj_conf)" ] && cp -f $temp_yaml $mj_conf

	rm $temp_yaml

	killall -1 majestic

	redirect_to "$HTTP_REFERER"
fi

config=""
_mj2="$(echo "$mj" | sed "s/ /_/g")"
for line in $_mj2; do
	yaml_param_name=${line%%|*}
	pn=${yaml_param_name#.}
	pn=${pn//./_}
	pn=${pn//-/_}
	domain=${pn%%_*}

	if [ "$old_domain" != "$domain" ]; then
		[ -n "$old_domain" ] && echo "</div></div>"
		echo "<div class=\"col\"><div class=\"card\">"
		old_domain=$domain
	fi

	form_field_name=mj_${pn}
	line=${line#*|}
	label_text=${line%%|*}
	label_text=${label_text//_/ }
	line=${line#*|}
	units=${line%%|*}
	line=${line#*|}
	form_field_type=${line%%|*}
	line=${line#*|}
	options=${line%%|*}
	line=${line#*|}
	placeholder=${line%%|*}
	line=${line#*|}
	hint=$line
	hint=${hint//_/ }

	value="$(yaml-cli -g "$yaml_param_name")"

	eval "$form_field_name=\"\$value\""
done

video0=${mj_video0_codec:-h264}
[ "true" != "$mj_video0_enabled" ] && video0="off"

video1=${mj_video1_codec:-h264}
[ "true" != "$mj_video1_enabled" ] && video1="off"

audio=${mj_audio_volume:-50}
[ "true" != "$mj_audio_enabled" ] && audio="off" && mj_audio_volume=""
[ "$mj_audio_volume" -gt 0 ] && audio="manual"
%>
<%in p/header.cgi %>

<p>Majestic: <%= $mj_version %>
| <a href="info-majestic.cgi">Majestic Config File (majestic.yaml)</a>
| <a href="majestic-endpoints.cgi">Majestic Endpoints</a></p>

<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<h3>Media Output</h3>
<div class="mb-3">
<p class="form-label">Video0</p>
<div class="btn-group d-flex" role="group" aria-label="Video0">
<input type="radio" class="btn-check" name="mj_video0_codec" id="mj_video0_codec_off" value="off"<% checked_if "$video0" "off" %>>
<label class="btn btn-outline-primary" for="mj_video0_codec_off">OFF</label>
<input type="radio" class="btn-check" name="mj_video0_codec" id="mj_video0_codec_h264" value="h264"<% checked_if "$video0" "h264" %>>
<label class="btn btn-outline-primary" for="mj_video0_codec_h264">H.264</label>
<input type="radio" class="btn-check" name="mj_video0_codec" id="mj_video0_codec_h265" value="h265"<% checked_if "$video0" "h265" %>>
<label class="btn btn-outline-primary" for="mj_video0_codec_h265">H.265</label>
</div>
</div>
<div class="mb-3">
<p class="form-label">Video1</p>
<div class="btn-group d-flex" role="group" aria-label="video1">
<input type="radio" class="btn-check" name="mj_video1_codec" id="mj_video1_codec_off" value="off"<% checked_if "$video1" "off" %>>
<label class="btn btn-outline-primary" for="mj_video1_codec_off">OFF</label>
<input type="radio" class="btn-check" name="mj_video1_codec" id="mj_video1_codec_h264" value="h264"<% checked_if "$video1" "h264" %>>
<label class="btn btn-outline-primary" for="mj_video1_codec_h264">H.264</label>
<input type="radio" class="btn-check" name="mj_video1_codec" id="mj_video1_codec_h265" value="h265"<% checked_if "$video1" "h265" %>>
<label class="btn btn-outline-primary" for="mj_video1_codec_h265">H.265</label>
</div>
</div>
<div class="mb-3">
<p class="form-label">Audio</p>
<div class="btn-group d-flex mb-2" role="group" aria-label="audio">
<input type="radio" class="btn-check" name="audio" id="audio_off" value="off"<% checked_if "$audio" "off" %>>
<label class="btn btn-outline-primary" for="audio_off">OFF</label>
<input type="radio" class="btn-check" name="audio" id="audio_auto" value="auto"<% checked_if "$audio" "auto" %>>
<label class="btn btn-outline-primary" for="audio_auto">Auto</label>
<input type="radio" class="btn-check" name="audio" id="audio_manual" value="manual"<% checked_if "$audio" "manual" %>>
<label class="btn btn-outline-primary" for="audio_manual">Manual</label>
</div>
<div class="range" id="audio_volume_wrap">
<% field_range "mj_audio_volume" "Audio volume level" "1,100,1" %>
</div>
</div>
<% field_switch "mj_jpeg_enabled" "Enable JPEG" %>
<% field_switch "mj_rtsp_enabled" "Enable RTSP" %>
<% field_switch "mj_hls_enabled" "Enable HLS" %>
</div>
<div class="col">
<h3>On-Screen Display</h3>
<% field_hidden "mj_osd_posX" %>
<% field_hidden "mj_osd_posY" %>
<% field_switch "mj_osd_enabled" "Enable OSD" %>
<% field_text "mj_osd_template" "OSD template" "$supports_strftime" "%a %e %B %Y %H:%M:%S %Z" %>
<% field_select "mj_osd_corner" "OSD preset position" "tl:Top_Left,tr:Top_Right,bl:Bottom_Left,br:Bottom_Right" %>
<% field_text "mj_osd_privacyMasks" "Privacy masks" "Coordinates of masked areas separated by commas." "0x0x234x640,2124x0x468x1300" %>
</div>
<div class="col">
<h3>Video Recording</h3>
<% field_switch "mj_records_enabled" "Enable recording" %>
<% field_text "mj_records_path" "Save video records to" "$supports_strftime" "/mnt/mmc/%Y/%m/%d/%H.mp4" %>

<h3>Motion Detection</h3>
<% field_switch "mj_motionDetect_enabled" "Enable motion detection" %>

<h3>ONVIF</h3>
<% field_switch "mj_onvif_enabled" "Enable ONVIF protocol" %>
</div>
</div>

<% button_submit %>
</form>

<script>
	function disableVolume(el) {
		if (el.checked) {
			const v = el.value;
			$('#mj_audio_volume').value = v;
			$('#mj_audio_volume-show').textContent = v;
			$('#mj_audio_volume-range').disabled = true;
		}
	}
	$('#audio_off').addEventListener('change', ev => disableVolume(ev.target))
	$('#audio_auto').addEventListener('change', ev => disableVolume(ev.target))
	$('#audio_manual').addEventListener('change', ev => {
		if (ev.target.checked) {
			const v = $('#mj_audio_volume-range').value;
			$('#mj_audio_volume').value = v;
			$('#mj_audio_volume-show').textContent = v;
			$('#mj_audio_volume-range').disabled = false;
		}
	})

	$("#mj_osd_corner")?.addEventListener("change", (ev) => {
		const padding = 32;
		switch (ev.target.value) {
			case "bl":
				$("#mj_osd_posX").value = padding;
				$("#mj_osd_posY").value = -(padding);
				break;
			case "br":
				$("#mj_osd_posX").value = -(padding);
				$("#mj_osd_posY").value = -(padding);
				break;
			case "tl":
				$("#mj_osd_posX").value = padding;
				$("#mj_osd_posY").value = padding;
				break;
			case "tr":
				$("#mj_osd_posX").value = -(padding);
				$("#mj_osd_posY").value = padding;
				break;
		}
	})

	$("#mj_netip_enabled")?.addEventListener("change", (ev) => {
		$("#mj_netip_user").required = ev.target.checked;
		$("#mj_netip_password_plain").required = ev.target.checked;
	})

	$("#mj_netip_password_plain") && $("form").addEventListener("submit", (ev) => {
		const pw = $("#mj_netip_password_plain").value.trim();
		if (pw !== "") $("#mj_netip_password").value = generateSofiaHash(pw);
	})

	disableVolume($('#audio_off'))
	disableVolume($('#audio_auto'))
</script>

<%in p/footer.cgi %>
