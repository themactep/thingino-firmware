</div>
</main>

<footer class="x-small">
<div class="container pt-3">
<div class="row">
<div class="col col-12 col-sm-5 mb-2">
<div id="uptime" class="text-secondary"></div>
</div>
<div class="col col-12 col-sm-7 mb-2">
<div class="text-sm-end">Powered by <a href="https://github.com/themactep/thingino-firmware">thingino</a>.</div>
</div>
</div>
</div>
</footer>

<% if [ "$debug" -gt 0 ]; then %>
<%in _debug.cgi %>
<% fi %>

</body>
</html>
