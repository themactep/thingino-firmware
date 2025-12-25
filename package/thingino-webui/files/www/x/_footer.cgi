</div>
</main>

<footer class="x-small text-secondary">
<div class="container pt-3">
<div class="row">
<div class="col col-sm-5 mb-2">
<div><%= $network_hostname %></div>
<div><%= $network_macaddr %></div>
<div id="uptime"></div>
</div>
<div class="col col-sm-7 mb-2">
<div class="text-sm-end">
<div>Powered by <a href="https://thingino.com/">Thingino</a></div>
<div><%= $BUILD_ID %></div>
<div><%= $IMAGE_ID %></div>
</p>
</div>
</div>
</div>
</div>
</footer>

<div id="debug-wrap">
<input type="checkbox" class="btn-check" id="debug">
<label class="btn btn-sm btn-dark border" for="debug" title="debug"><img src="/a/debug.svg" alt="debug" class="img-fluid"></label>
</div>

</body>
</html>
