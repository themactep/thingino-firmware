#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Erase overlay"
%>
<%in _header.cgi %>
<pre id="output" data-cmd="<% echo $POST_cmd | base64 -d %>" data-reboot="true"></pre>
<div class="alert alert-warning">
<p class="mb-0">After the reset is completed, you will need to reconfigure the camera. For detailed instructions, please consult the <a href="https://github.com/themactep/thingino-firmware/wiki/Camera-configuration">relevant article</a> in our wiki.</p>
</div>
<%in _footer.cgi %>
