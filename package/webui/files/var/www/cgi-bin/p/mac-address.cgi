<div class="alert alert-danger">
<h3>This camera uses MAC address <b>00:00:23:34:45:66</b> which is a placeholder.</h3>
<p>You need to replace it with the original MAC address from your stock firmware backup or <a href="#" id="generate-mac-address">generate a random valid MAC address</a>.</p>
<form action="network.cgi" method="POST" class="row gy-2 gx-3 align-items-center mb-3">
<input type="hidden" name="action" value="changemac">
<div class="col-auto"><label class="form-label" for="mac_address">New MAC Address</label></div>
<div class="col-auto"><input class="form-control" id="mac_address" name="mac_address"type="text"></div>
<div class="col-auto"><input class="btn btn-danger" type="submit" value="Change MAC address"></div>
</form>
<p class="mb-0">Please note that the new MAC address will most likely give the camera a new IP address assigned by the DHCP server!</p>
</div>

<script>
function generateMacAddress(ev) {
	ev.preventDefault();
	const el = document.querySelector('#mac_address');
	if (el.value == "") {
		let mac = "";
		for (let i = 1; i <= 6; i++) {
			let b = ((Math.random() * 255) >>> 0);
			if (i === 1) {
				b = b | 2;
				b = b & ~1;
			}
			mac += b.toString(16).toUpperCase().padStart(2, '0');
			if (i < 6) mac += ":";
		}
		el.value = mac;
	} else {
		alert("There's a value in MAC address field. Please empty the field and try again.");
	}
}

window.addEventListener('load', function() {
	document.querySelector('#generate-mac-address').addEventListener('click', generateMacAddress);
});
</script>
