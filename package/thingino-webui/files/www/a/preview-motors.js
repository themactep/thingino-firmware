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

async function moveMotor(dir, steps = 100, d = 'g') {
  // Use motor parameters loaded from backend
  const motorParams = window.motorParams || {steps_pan: 0, steps_tilt: 0, pos_0_x: 0, pos_0_y: 0};
  const x_max = motorParams.steps_pan;
  const y_max = motorParams.steps_tilt;
  const x0 = Number(motorParams.pos_0_x);
  const y0 = Number(motorParams.pos_0_y);
  const step = x_max / steps;
  if (dir == 'homing') {
    await runMotorCmd("d=r");
    if (Number.isFinite(x0) && Number.isFinite(y0)) {
      await sleep(800);
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

// Initialize motor controls when DOM is ready
document.addEventListener('DOMContentLoaded', function() {
  const uiConfig = window.thinginoUIConfig || {};
  const hasMotors = uiConfig.device && uiConfig.device.motors === true;

  if (!hasMotors) {
    return;
  }

  const motorOverlay = $('#motor-overlay');
  if (motorOverlay) {
    motorOverlay.style.display = '';
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
});
