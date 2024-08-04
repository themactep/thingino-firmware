function callImp(command, value) {
	if (command.startsWith("osd_")) {
		let i=command.split('_')[2];
		let a=command.split('_')[1];
		let g=document.querySelector('.group_osd[data-idx="'+i+'"]');
		if (command.startsWith("osd_pos_")) {
			document.getElementById("osd_pos_auto_"+i+"_ig").classList.toggle("d-none");
			document.getElementById("osd_pos_fixed_"+i+"_ig").classList.toggle("d-none");
		}
		let c=g.getAttribute("data-conf").split(" ");
		if(a == 'fgAlpha') c[1] = value
		if(a == 'show') c[2] = value
		if(a == 'posx') c[3] = value
		if(a == 'posy') c[4] = value
		if(a == 'pos') c[5] = (value==0?0:document.getElementById("osd_apos_"+i).value)
		if(a == 'apos') c[5] = value
		g.setAttribute('data-conf', c.join(' '));
		value = g.getAttribute("data-conf");
		command = 'setosd';
	} else if (["flip", "mirror"].includes(command)) {
		command = "flip"
		value = 0
		if (document.querySelector('#flip').checked) value = (1 << 1)
		if (document.querySelector('#mirror').checked) value += 1
	} else if (["aiaec", "aihpf"].includes(command)) {
		value = (value === 1) ? "on" : "off"
	} else if (["ains"].includes(command)) {
		if (value === -1) value = "off"
	} else if (["setosdpos_x", "setosdpos_y"].includes(command)) {
		command = 'setosdpos'
		value = '1' +
			'+' + document.querySelector('#setosdpos_x').value +
			'+' + document.querySelector('#setosdpos_y').value +
			'+1087+75';
	} else if (["whitebalance_mode", "whitebalance_rgain", "whitebalance_bgain"].includes(command)) {
		command = 'whitebalance'
		value = document.querySelector('#whitebalance_mode').value +
			'+' + document.querySelector('#whitebalance_rgain').value +
			'+' + document.querySelector('#whitebalance_bgain').value;
	}

	const xhr = new XMLHttpRequest();
	xhr.open('GET', '/x/j/imp.cgi?cmd=' + command + '&val=' + value);
	xhr.send();

	document.querySelector('#savechanges')?.classList.remove('d-none');
}

// numbers
document.querySelectorAll('input[type=number]').forEach(el => {
	el.autocomplete = "off"
	el.addEventListener('change', ev => callImp(ev.target.name, ev.target.value))
});

// checkboxes
document.querySelectorAll('input[type=checkbox]').forEach(el => {
	el.autocomplete = "off"
	el.addEventListener('change', ev => callImp(ev.target.name, ev.target.checked ? 1 : 0))
});

// radios
document.querySelectorAll('input[type=radio]').forEach(el => {
	el.autocomplete = "off"
	el.addEventListener('change', ev => callImp(ev.target.name, ev.target.value))
});

// ranges
document.querySelectorAll('input[type=range]').forEach(el => {
	el.addEventListener('change', ev => callImp(ev.target.id.replace('-range', ''), ev.target.value))
});

// selects
document.querySelectorAll('select').forEach(el => {
	el.addEventListener('change', ev => callImp(ev.target.id, ev.target.value))
});
