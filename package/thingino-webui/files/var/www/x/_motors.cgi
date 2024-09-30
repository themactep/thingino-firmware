<% if [ -f /bin/motors ]; then %>
<div id="motor" class="position-absolute top-50 start-50 translate-middle">
<div class="jst">
<a class="s" data-dir="uc"></a>
<a class="s" data-dir="ur"></a>
<a class="s" data-dir="cr"></a>
<a class="s" data-dir="dr"></a>
<a class="s" data-dir="dc"></a>
<a class="s" data-dir="dl"></a>
<a class="s" data-dir="cl"></a>
<a class="s" data-dir="ul"></a>
<a class="b" data-dir="h"></a>
<div id="ptzpos" class="position-absolute m-0 top-50 start-50 translate-middle small"></div>
</div>
</div>

<script>
function runMotorCmd(args) {
	fetch(`/x/json-motor.cgi?${args}`)
	.then(res => res.json())
	.then(({xpos, ypos}) => {
		$('#ptzpos').textContent = xpos + "," + ypos;
	});
}

function moveMotor(dir, steps = 100, d = 'g') {
	const x_max=<% echo -n $(get motor_maxstep_h) %>;
	const y_max=<% echo -n $(get motor_maxstep_v) %>;
	const step = x_max / steps;
	if (dir == 'homing') {
		runMotorCmd("d=r");
	} else if (dir == 'cc') {
		runMotorCmd("d=x&x=" + x_max / 2 + "&y=" + y_max / 2);
	} else {
		let y = dir.includes("u") ? -step : dir.includes("d") ? step : 0;
		let x = dir.includes("l") ? -step : dir.includes("r") ? step : 0;
		runMotorCmd("d=g&x=" + x + "&y=" + y);
	}
}

let timer;
$$(".jst a.s").forEach(el => {
	el.onclick = (ev) => {
		if (ev.detail === 1) {
			timer = setTimeout(() => { moveMotor(ev.target.dataset.dir, 100 )}, 200);
		}
	}
	el.ondblclick = (ev) => {
		if (ev.detail === 2) {
			clearTimeout(timer);
			moveMotor(ev.target.dataset.dir, 10);
		}
	}
});

$(".jst a.b").onclick = (ev) => {
	if (ev.detail === 1) {
		timer = setTimeout(() => { moveMotor('cc') }, 200);
	}
}

$(".jst a.b").ondblclick = (ev) => {
	clearTimeout(timer);
	moveMotor('homing');
}

runMotorCmd("d=j");
</script>

<style>
#motor { width: 25vh; height: 25vh; }
#motor:hover .jst { visibility: visible; }
.jst { width: 100%; height: 100%; border-radius: 50%; position: relative; overflow: hidden; visibility: hidden; }
.jst a { position: absolute; left: 50%; top: 50%; cursor: pointer; }
.jst a.s { transform-origin: 100% 100%; width: 5000px; height: 5000px; margin-top: -5000px; margin-left: -5000px; background-color: #88888833; }
.jst a.s:hover { background-color: #ff880088; }
.jst a.s:active { background-color: #ff8800ff; }
.jst a.s:nth-child(1) { transform: rotate( 67.5deg) skew(45deg); }
.jst a.s:nth-child(2) { transform: rotate(112.5deg) skew(45deg); }
.jst a.s:nth-child(3) { transform: rotate(157.5deg) skew(45deg); }
.jst a.s:nth-child(4) { transform: rotate(202.5deg) skew(45deg); }
.jst a.s:nth-child(5) { transform: rotate(247.5deg) skew(45deg); }
.jst a.s:nth-child(6) { transform: rotate(292.5deg) skew(45deg); }
.jst a.s:nth-child(7) { transform: rotate(-22.5deg) skew(45deg); }
.jst a.s:nth-child(8) { transform: rotate( 22.5deg) skew(45deg); }
.b { clip-path: circle(30%); width: 60%; height: 60%; margin-left: -30%; margin-top: -30%; background: #808080; }
.b:hover { background: #ff330088; }
.b:active { background: #ff3300ff; }
</style>
<% fi %>
