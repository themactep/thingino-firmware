#!/usr/bin/haserl --upload-limit=1024 --upload-dir=/tmp
<%in p/common.cgi %>
<%in p/icons.cgi %>
<%
page_title="OSD"

OSD_CONFIG="/etc/prudynt.cfg"
OSD_FONT_PATH="/usr/share/fonts"
FONT_REGEXP="s/(#\s*)?font_path:(.+);/font_path: \"${OSD_FONT_PATH//\//\\/}\/\%s\";/"

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""
	if [ -n "$HASERL_fontfile_path" ] && [ $(stat -c%s $HASERL_fontfile_path) -gt 0 ]; then
		fontname="uploaded.ttf"
		mv "$HASERL_fontfile_path" "$OSD_FONT_PATH/$fontname"
		sed -ri "$(printf "$FONT_REGEXP" "$fontname")" /etc/prudynt.cfg
		need_to_reload="true"
	elif [ -n "$POST_fontname" ]; then
		sed -ri "$(printf "$FONT_REGEXP" "$POST_fontname")" /etc/prudynt.cfg
		need_to_reload="true"
	else
		echo "File upload failed. No font selected." > /root/fontname
		set_error_flag "File upload failed. No font selected."
	fi
fi
%>
<%in p/header.cgi %>
<% if [ "true" = "$need_to_reload" ]; then %>
<h3>Restarting Prudynt</h3>
<h4>Please wait...</h4>
<progress max="2" value="0"></progress>
<script>
const p=document.querySelector('progress'); let s=0;
function t(){s+=1;p.value=s;(s===p.max)?g():setTimeout(t,1000);}
function g(){window.location.replace(window.location);}
setTimeout(t, 2000);
</script>
<%
	/etc/init.d/S95prudynt restart &
else
	fontname=$(sed -nE '/font_path:/s/.*\/(.*)";/\1/p' $OSD_CONFIG)
	ts=$(date +%s)
%>
<div class="row g-4 mb-4">
<div class="col-lg-4">
<form action="<%= $SCRIPT_NAME %>" method="post" enctype="multipart/form-data">
<% field_select "fontname" "Select a font" "$(ls -1 $OSD_FONT_PATH)" %>
<% field_file "fontfile" "Upload a TTF file" %>
<% button_submit %>
</form>
</div>
<div class="col-lg-8">
<div id="preview-wrapper" class="mb-4 position-relative">
<img id="preview" src="image.cgi?t=<%= $ts %>" alt="Image: Preview" class="img-fluid">
<button type="button" class="btn btn-primary btn-large position-absolute top-50 start-50 translate-middle" data-bs-toggle="modal" data-bs-target="#previewModal"><%= $icon_zoom %></button>
</div>
<div class="modal fade" id="previewModal" tabindex="-1" aria-labelledby="previewModalLabel" aria-hidden="true">
<div class="modal-dialog modal-fullscreen"><div class="modal-content"><div class="modal-header">
<h1 class="modal-title fs-4" id="previewModalLabel">Full screen preview</h1>
<button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
</div>
<div class="modal-body text-center">
<img id="preview" src="image.cgi?t=<%= $ts %>" alt="Image: Preview" class="img-fluid">
</div>
</div>
</div>
</div>
<% ex "grep font_path $OSD_CONFIG | xargs" %>
</div>
</div>

<script>
const previewModal = new bootstrap.Modal('#previewModal', {});
$('#preview').addEventListener('click', ev => {
	previewModal.show();
});
</script>
<% fi %>

<style>
#preview-wrapper button { visibility: hidden; }
#preview-wrapper:hover button { visibility: visible; }
</style>

<%in p/footer.cgi %>
