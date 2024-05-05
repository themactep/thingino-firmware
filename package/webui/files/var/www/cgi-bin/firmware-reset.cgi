#!/usr/bin/haserl
<%in p/common.cgi %>
<% page_title="Erase overlay" %>
<%in p/header.cgi %>
<pre id="output" data-cmd="flash_eraseall -j /dev/mtd4" data-reboot="true"></pre>
<a class="btn btn-primary" href="/">Go home</a>
<a class="btn btn-danger" href="reboot.cgi">Reboot camera</a>
<%in p/footer.cgi %>
