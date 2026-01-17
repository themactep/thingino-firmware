<div id="motor">
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
  </div>
</div>

<script>
function runMotorCmd(args) {
  return fetch(`/x/json-motor.cgi?${args}`)
     .then(res => res.json())
     .then(({message}) => {
      const {xpos, ypos} = message || {};
      if (xpos !== undefined && ypos !== undefined) {
        console.log("Position:" + xpos + "," + ypos);
      }
      return message;
    });
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

<%
steps_pan=$(jct /etc/motors.json get motors.steps_pan); [ -z "$steps_pan" ] && steps_pan=0;
steps_tilt=$(jct /etc/motors.json get motors.steps_tilt); [ -z "$steps_tilt" ] && steps_tilt=0;
pos_0=$(jct /etc/motors.json get motors.pos_0);
pos_0_x=$(echo $pos_0 | awk -F',' '{print $1}'); [ -z "$pos_0_x" ] && pos_0_x=0;
pos_0_y=$(echo $pos_0 | awk -F',' '{print $2}'); [ -z "$pos_0_y" ] && pos_0_y=0;
%>
async function moveMotor(dir, steps = 100, d = 'g') {
  const x_max=<%= $steps_pan %>;
  const y_max=<%= $steps_tilt %>;
  const x0=Number(<%= $pos_0_x %>);
  const y0=Number(<%= $pos_0_y %>);
  const step = x_max / steps;
  if (dir == 'homing') {
    await runMotorCmd("d=r");
    if (Number.isFinite(x0) && Number.isFinite(y0)) {
      await sleep(800); // allow homing to finish before moving to saved pose
      await runMotorCmd("d=x&x=" + x0 + "&y=" + y0);
    }
  } else if (dir == 'cc') {
    runMotorCmd("d=x&x=" + x_max / 2 + "&y=" + y_max / 2);
  } else {
    let y = dir.includes("d") ? -step : dir.includes("u") ? step : 0;
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
#motor { width: 300px; height: 300px; margin: 0 auto; }
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
