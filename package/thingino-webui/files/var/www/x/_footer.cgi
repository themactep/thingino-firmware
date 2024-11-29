</div>
</main>

<footer class="x-small">
<div class="container pt-3">
<div class="row">
<div class="col col-sm-5 mb-2">
<div id="uptime" class="text-secondary"></div>
</div>
<div class="col col-sm-7 mb-2">
<div class="text-sm-end">Powered by <a href="https://thingino.com/">thingino</a>.</div>
</div>
</div>
</div>
</footer>

<div id="debug-wrap">
<input type="checkbox" class="btn-check" id="debug">
<label class="btn btn-sm btn-dark border" for="debug" title="debug"><img src="/a/debug.svg" alt="debug" class="img-fluid"></label>
</div>

<script>
$('#debug').addEventListener('change', ev => {
	ev.target.checked ?
		$('.ui-debug').classList.remove('d-none') :
		$('.ui-debug').classList.add('d-none') ;
});
</script>

<%in _debug.cgi %>
</body>
</html>
