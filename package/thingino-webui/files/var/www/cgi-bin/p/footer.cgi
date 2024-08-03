</div>
</main>
<footer class="x-small">
<div class="container pt-3">
<div class="row">
<div class="col col-2">
<p id="uptime" class="text-secondary"></p>
</div>
<div class="col col-10">
<p class="text-end">Powered by <a href="https://github.com/themactep/thingino-firmware">thingino</a>.</p>
</div>
</div>
</div>
</footer>

<% if [ "$debug" -gt 0 ]; then %>
<button id="debug-button" type="button" class="btn btn-primary btn-sm m-2 float-start" data-bs-toggle="offcanvas" data-bs-target="#offcanvasDebug" aria-controls="offcanvasDebug">Debug</button>
<div class="offcanvas offcanvas-start" tabindex="-1" id="offcanvasDebug" aria-labelledby="offcanvasDebugLabel">
<div class="offcanvas-header">
<h5 class="offcanvas-title" id="offcanvasDebugLabel">Debug Info</h5>
<form action="config-webui.cgi" method="post">
<% field_hidden "action" "init" %>
<% button_submit "Re-read environment" %>
</form>
<button type="button" class="btn-close" data-bs-dismiss="offcanvas" aria-label="Close"></button>
</div>
<div class="offcanvas-body x-small">
<ul class="nav nav-tabs" role="tablist">
<% tab_lap "t1" "sysinfo" "active" %>
<% tab_lap "t2" "Environment" %>
<% tab_lap "t3" "IMP" %>
<% tab_lap "t4" "U-Boot Env" %>
</ul>
<div class="tab-content p-2" id="tab-content">
<div id="t1-tab-pane" role="tabpanel" class="tab-pane fade active show" aria-labelledby="t1-tab" tabindex="0">
<% ex "cat /tmp/sysinfo.txt" %>
</div>
<div id="t2-tab-pane" role="tabpanel" class="tab-pane fade" aria-labelledby="t2-tab" tabindex="0">
<% ex "env | sort" %>
</div>
<div id="t3-tab-pane" role="tabpanel" class="tab-pane fade" aria-labelledby="t3-tab" tabindex="0">
<% [ -f /etc/imp.conf ] && ex "cat /etc/imp.conf" %>
<% [ -f /tmp/imp.conf ] && ex "cat /tmp/imp.conf" %>
<b>in memory values</b>
<pre><% for i in $commands; do eval "echo $i = \$$i"; done %></pre>
<b>commands to fix</b>
<pre><% for i in $commands_do_not_work; do echo -e "$i\n\t$(/usr/sbin/imp-control $i)"; done %></pre>
</div>
<div id="t4-tab-pane" role="tabpanel" class="tab-pane fade" aria-labelledby="t4-tab" tabindex="0">
<% ex "fw_printenv | sort" %>
</div>
</div>
</div>
</div>
<% fi %>

</body>
</html>
