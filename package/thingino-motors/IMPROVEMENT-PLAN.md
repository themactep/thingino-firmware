# thingino-motors — Improvement Plan

Status: proposal. Not implemented. Nothing here is committed to a schedule.

This revision folds in the architecture review of the former `IDEAL-DRIVER.md`
(now archived at `trash/package/thingino-motors/IDEAL-DRIVER.md`; see §7 for the
item-by-item verdict). The headline is still motion quality; the change
is that the various motion features collapse into **one** generic profiler, and
that the genuinely useful parts of `IDEAL-DRIVER.md` are adopted as an
*internal* refactor rather than a rewrite.

## 0. Scope and non-goals

The `thingino-motors` Buildroot package (`package/thingino-motors/`) is the
packaging, init, WebUI and config layer around the external daemon source in
`thingino/thingino-motors` (`src/motor.c`, `src/motor-daemon.c`). All motion
logic lives in that daemon; the package only builds, installs and configures it.
References to daemon code are to the upstream source; references to `files/*`
and `thingino-motors.mk` are to this repo.

Priority order:

1. Motion quality — a single generic velocity profiler, instantiated as a
   SixPoint ramp (A1 + AMAX / DMAX + D1), following ADI/Trinamic's PTZ article
   <https://ez.analog.com/ez-blogs/b/engineerzone-spotlight/posts/intruders-forget-the-dog-instead-beware-ptz-security-cameras-using-trinamic-motor-control>.
2. Internal architecture: a driver backend interface, a calibration module, and
   an explicit coordinate manager — taken from `IDEAL-DRIVER.md` (§7).
3. Config / WebUI / API surface.
4. Driver and hardware constraints.
5. Validation and rollout.

Non-goals (see §7 for why):

- A greenfield rewrite of the daemon or a new process/repo.
- Limit switches, encoders, closed-loop or PID control, visual tracking.
- Kernel-side ramp generation; touching the `ingenic-sdk` / U-Boot boundaries.
- Changing the ioctl ABI, IPC protocol, CLI flags, or config schema.

## 1. Current state

### 1.1 Motion path

- `motors` (client) sends a `struct request` over the UNIX socket `/dev/md`.
- `motors-daemon` has a single kernel fd to `/dev/motor` and drives it with
  ioctls: `MOTOR_MOVE` (start a fixed-speed step burst), `MOTOR_SPEED` /
  `MOTOR_SPEED_AXIS` (`0x5` / `0x8`), `MOTOR_STOP`, `MOTOR_RESET`.
- Three driver paths already exist in-tree behind that fd: the legacy
  `motor.ko` from `ingenic-sdk` (TCU 4-phase, GPIO), the `spi-tmi8152` external
  driver IC, and the 5.15 open-path T31 TCU driver. Which one is live is
  smeared across `g_cfg.hw.is_spi`, the modprobe args assembled in `S59motor`,
  and per-driver ioctl fallbacks in the daemon.
- No driver exposes a ramp, accel register, or jerk control. So ramping must be
  synthesized by chopping a move into fixed-speed segments, each started with
  `MOTOR_MOVE` and drained by polling `MOTOR_GET_STATUS` until idle.

### 1.2 What the daemon does today

`run_profiled_move()` (`src/motor-daemon.c`, ~L1040) computes a trapezoid and
splits it into three `execute_profile_phase()` calls (~L905):

- accel segment `[0, accel_steps)` at `phase_speed = (start_speed + max_speed)/2`
- cruise segment `[accel_steps, cruise_end)` at `max_speed`
- decel segment `[cruise_end, total)` at the same `phase_speed`

Config already parses `accel` per axis (`accel_pan` / `accel_tilt` in the
modern layout, `pan.accel` / `tilt.accel` in the legacy layout, ~L388, ~L428),
and `get_effective_accel()` (~L987) collapses both axes to the smaller value.

### 1.3 Why this is not enough

- **The "ramp" is two speed steps, not a ramp.** Each `execute_profile_phase`
  runs at one constant speed, so the velocity profile is a staircase:
  `0 -> phase_speed -> max_speed -> phase_speed -> 0`. Each corner is a step
  change in velocity — infinite jerk, the exact thing a ramp exists to avoid.
- **Ramping is off by default.** `files/motors.json` ships `accel_pan`/
  `accel_tilt` = 0, and `run_profiled_move()` takes the `accel <= 0` branch,
  i.e. a single full-speed burst. Every default install moves jerkily.
- **One profile for two axes.** `accel` is collapsed with `min()` across axes
  and `phase_speed` is derived from the smaller `max_speed`, so a slow tilt
  corrupts the pan profile.
- **Segment boundaries re-introduce the problem.** `execute_profile_phase()`
  waits for full idle between segments, so each boundary is a stop/start, not a
  continuous velocity crossing. More segments add more boundaries.
- **The client can't request it.** The WebUI (`files/www/a/preview-motors-settings.js`)
  exposes only `speed_pan` / `speed_tilt`; `accel` is config-file-only.
- **No calibration.** No backlash compensation, no steps↔degrees mapping, no
  persisted per-unit calibration. Homing stalls against mechanical stops and
  eats the resulting step loss (there are no limit switches — see
  `motor-daemon.c:1615`).

## 2. Proposed work

### 2.1 One profiler, shaped as a SixPoint ramp — headline

The separate features in the previous draft (trapezoid, six-point, per-axis
reconciliation, segment cap) are all the same mechanism: **emit a move as a
sequence of constant-speed segments along a velocity-versus-progress curve.**
Implement *that* once, as a breakpoint list, and get every shape by choosing
breakpoints. This is simpler than three code paths and makes the constraints
below (segment budget, per-axis) parameters rather than features.

- `off` = one breakpoint (single burst; today's `accel <= 0`).
- `trapezoid` = three breakpoints (AMAX, cruise, DMAX).
- `sixpoint` = six breakpoints (adds A1 and D1 at the ends).

SixPoint, per the ADI article and `docs/ptz-sixpoint.avif`: accelerate gently
at the start (A1, low acceleration), then harder (AMAX, the trapezoidal slope),
cruise, decelerate harder (DMAX), then gently (D1) before stopping. The gentle
low-speed segments at the two ends are what remove the visible jerk.

![Trapezoidal vs. SixPoint ramping](../../docs/ptz-sixpoint.avif)

*Figure: top is the classic trapezoid (`a_max`, `Δv`, then constant velocity).
Bottom is the SixPoint `VACTUAL` profile: gentle `A1` from `VSTART` to `V1`,
steeper `AMAX` to `VMAX`, cruise, steeper `DMAX` back to `V1`, gentle `D1` to
`VSTOP`, with a `ZEROWAIT` hold at rest. The two gentle segments (`A1`, `D1`)
are the ones SixPoint adds over the trapezoid.*

Breakpoints (one list; both axes evaluate it against a shared progress):

| # | Phase | Slope | Velocity |
|---|-------|-------|----------|
| P0 | start | — | `VSTART` (small non-zero start speed) |
| P1 | end of A1 | `a_soft` | `V1` |
| P2 | end of AMAX = cruise | `a_hard` | `VMAX` |
| P3 | start of DMAX | `a_hard` | `VMAX` (cruise held P2..P3) |
| P4 | end of DMAX | `a_hard` | `V1` |
| P5 | end of D1 = stop | `a_soft` | `VSTOP` (small, then stop) |

Distances between breakpoints use `s = (v_b^2 - v_a^2) / (2a)`, sized so the
segments sum to `total`; clamp for short moves (a move shorter than the ramp
never reaches `VMAX` — a short tap runs A1/D1 only).

**Simpler than the last draft.** Rather than maintaining a breakpoint list per
axis and partitioning the union of their distances, drive both axes from a
single progress parameter: each segment advances a shared `progress` fraction,
and each axis's target speed is its own breakpoint function evaluated at that
progress, clamped to that axis's `speed_pan`/`speed_tilt`. One timeline, no
union-merge bookkeeping, and it composes correctly with the shared-data-channel
serialization already in `uses_shared_motor_data_channel()`.

**Simpler config.** Do not add `accel_soft_*` / `accel_hard_*` keys. Keep the
single `accel_pan|tilt` already parsed, add one enum `ramp_profile`
(`off|trapezoid|sixpoint`), and derive `a_soft` from a fixed ratio of `accel`
(e.g. A1/D1 slope = accel/3) with an optional `ramp_soft_ratio` override only
if tuning shows it is needed. Fewer keys means less UI, less back-compat, and
less to keep in sync with the upstream README.

**Segment budget.** Each `execute_profile_phase()` ends in `wait_until_idle()`,
a real discontinuity and latency cost, so more breakpoints is not automatically
smoother. Bound the segment count as a function of `total` (never more than N
segments, or one segment per K steps) and record the measured jerk/latency
tradeoff in the daemon source or `docs/` as a constant, not a runtime knob.

### 2.2 Anti-resonance — keep it conditional

Steppers have a mid-band resonance that shows as buzz/step loss at certain step
rates. The previous draft proposed a configurable resonance-window dwell. Drop
that as a first-class feature: it is speculative, needs per-model measurement,
and the soft A1/D1 segments already lower the speed through the low-range
resonance region on every start and stop. Keep as a fallback: the ability to
floor the profile at a minimum step rate, and to cap the small-nudge speed
(today hard-coded as 2/3 for `total < 32`) via config if field units show the
"quick tap" is too aggressive. Add window scheduling only if a specific model
is measured to need it.

### 2.3 Calibration module — the real gap

`IDEAL-DRIVER.md`'s calibration section maps to a genuine absence here. Adopt
it incrementally, without a new storage subsystem — the calibration lives in
`thingino.json` like every other motor setting:

- **Soft limits**: already partly present (`max_steps`, `limitless`); make the
  behaviour explicit and per-axis.
- **Backlash compensation**: a `backlash_pan|tilt` value applied by the planner
  on direction reversal (add the slack steps when the sign of travel flips).
  This is a pure planner feature and does not touch the driver.
- **Steps↔degrees scaling**: `deg_per_step_pan|tilt` for the UI and ONVIF, so
  callers speak degrees without knowing the gear ratio.
- **Persistence / trigger**: values persist in `thingino.json`; expose a
  `motors calibrate` entry point for the WebUI/CGI to call. No EEPROM path —
  the config store is the persistence layer already.
- **Homing** stays as-is: hard-stop homing is correct for hardware with no
  limit switches; do not pretend otherwise.

### 2.4 Driver backend interface — internal only

Replace the scattered `is_spi` / modprobe-args / ioctl-fallback branching with
a small internal `struct` of function pointers (open, set-speed, move, stop,
reset, get-status, read-max) with one implementation per existing path (legacy
TCU, TMI8152, 5.15 TCU). This is the useful core of `IDEAL-DRIVER.md`'s HAL,
kept inside the daemon — not a new `/hal/` layer, and with the ioctl ABI
unchanged. It is also the seam where a future closed-loop / hardware-ramp
driver would plug in.

## 3. Config, WebUI and API surface

- Config (`files/motors.json` defaults; daemon parse in `src/motor-daemon.c`):
  add `ramp_profile` and (if needed) `ramp_soft_ratio`, plus the calibration
  keys `backlash_pan|tilt` and `deg_per_step_pan|tilt`. Keep `accel_pan|tilt`
  as-is; it is the single acceleration input.
- Ship a non-zero default `accel` (and `ramp_profile: sixpoint`) so new installs
  are smooth out of the box. This is the highest-value single change and is
  independent of the rest — it can land first.
- WebUI (`files/www/a/preview-motors-settings.js`, `config-motors.html`):
  expose acceleration and a ramp-profile selector next to the existing speed
  fields; keep the numeric-input + validation pattern already used for
  `speed_pan` / `speed_tilt`. Calibration fields go on the config page.
- CGI (`files/www/x/json-motor-params.cgi`, `json-motors-config.cgi`): persist
  and return the new keys, and make sure the existing `motors -R` reload path
  (`S59motor reload`) applies them without a reboot. Accel/ramp/calibration are
  userspace-only and must not require a module reload; kernel-param keys still
  do.

## 4. Driver and hardware constraints

- The legacy TCU module clamps speed (historical ceiling ~900); the daemon
  allows up to `MOTOR1_MAX_SPEED` = 2000. A ramp that asks above the ceiling is
  silently flattened at the top. Read the real ceiling back from the driver or
  `/sys/module/motor/` and shape the profile to it rather than trusting config.
- The `spi-tmi8152` driver maps speed through a 142-entry table
  (`speed_profile_table`), so velocity is quantized; round each breakpoint to a
  representable speed and report the achieved value.
- No hardware ramping on any current path, so the daemon paces segments and
  polls status itself: a smooth profile trades CPU cycles against the
  segment-boundary cost in §2.1. If a board ever carries a Trinamic-class
  driver, defer to its hardware ramp through the §2.4 backend.
- SpreadCycle full-step current hysteresis (the article's second point) is not
  reachable from userspace; it needs microstep/current control in the kernel
  driver or hardware. Out of scope here, but the place to look if jerk remains
  after ramping.
- `motor.ko` lacks `.owner = THIS_MODULE` (see the long comment in
  `files/S59motor` and themactep/ingenic-sdk#45); module lifetime/ownership must
  not change as part of this work.

## 5. Validation

- No firmware CI beyond compilation. Validate on hardware.
- Step-rate trace: log each segment's `(speed, steps)` and reconstruct the
  velocity profile; assert the staircase approximates the intended ramp and the
  top speed matches the driver ceiling.
- Subjective A/B on a real camera: default vs. ramp, on both the TCU and
  TMI8152 paths — listen for buzz and watch for missed steps / drift.
- Regression: homing (`-r`), absolute (`-d h`), relative (`-d g`), presets,
  continuous preview move, `motors -R` reload, and (new) `motors calibrate`
  must all preserve final positions. Backlash compensation is the highest-risk
  addition to position repeatability — test direction reversals specifically.
- Drift over many moves with ramping on: a ramp that exceeds the module max
  speed or mis-accounts a segment boundary will lose steps.

## 6. Rollout

1. Ship a non-zero default `accel` and `ramp_profile: sixpoint` (small, safe,
   independent of the refactor).
2. Refactor to the single generic profiler; land it behind `ramp_profile`,
   default `sixpoint` once validated on both driver paths.
3. Introduce the §2.4 driver backend struct (mechanical change, no behaviour
   change) and move the three existing paths onto it.
4. Add the calibration keys and `motors calibrate`; wire the config page.
5. Improve config-page/WebUI exposure for acceleration and ramp selection.
6. Update the upstream `thingino/thingino-motors` README and this package's
   config docs together, since the keys are shared.

## 7. `IDEAL-DRIVER.md` — item-by-item verdict

Source archived at `trash/package/thingino-motors/IDEAL-DRIVER.md`.

| `IDEAL-DRIVER.md` item | Verdict | Note |
|---|---|---|
| HAL (GPIO/timer/I²C/SPI mappings) | **Adapt** | The mapping is the kernel driver + `S59motor` modprobe args. Take the idea as the internal backend struct (§2.4); do not add a `/hal/` layer. |
| Motor driver layer | **Adapt** | Exists as the ioctl layer. Backend struct unifies the three paths. |
| Limit switch handler / end stops | **Reject (for now)** | No limit switches on these cameras; homing is hard-stop based. Would need new board support. |
| Current / torque control | **Reject** | Not exposed by any current driver path. |
| Motion controller (trapezoid/S-curve) | **Take** | Already present; the ramp work (§2.1) is the improvement. |
| Bresenham coordinated moves | **Reject** | The kernel takes X+Y counts atomically; shared-channel serialization already handled. Only relevant for a future single-pulse driver. |
| Calibration module (homing, soft limits, backlash, scaling, storage) | **Take** | Real gap. Adopt incrementally; persist in `thingino.json` (§2.3). |
| Position feedback → calibration corrections | **Reject (except soft limits/backlash)** | No encoders; corrections are open-loop. |
| Coordinate system manager (steps↔degrees, abs/rel) | **Take (partly)** | Inversion/raw-vs-logical already exists; add degrees mapping (§2.3). |
| Preset manager | **Already have** | `motors.presets` in `thingino.json` + WebUI + `ptz_presets`. |
| Protocol handler (ONVIF/Pelco/VISCA) | **Already have (ONVIF)** | ONVIF PTZ lives in the streamer; Pelco/VISCA would be new, out of scope. |
| Auto-tracking (PID, visual) | **Reject** | Belongs in the streamer/ISP; a separate project. |
| RTOS task model | **Reject** | Linux userspace daemon with pthreads; not applicable. |
| GPIO pin location conventions | **N/A** | Pin config arrives via modprobe args / config, not board pinmux files here. |

**Why not from scratch.** The kernel ioctl ABI is fixed and quirky; a rewrite
must match it or change kernel drivers. The external contract is large (CLI
flags used by `S59motor`/`ptz-ctrl`/`ptz_presets`, the `/dev/md` protocol, the
`thingino.json` schema, the CGI/WS endpoints, the WebUI plugin manifest, and
the WS-fork gating in `thingino-motors.mk`). There is no firmware CI, so the
cost is per-camera hardware validation across hundreds of defconfigs — and a
clean abstraction does not reduce that cost. Refactor internally behind the
unchanged contracts, and only split out a new process/repo if that proves to be
the real bottleneck. The one strategic pull toward a clean HAL is future
closed-loop / hardware-ramp drivers, which is exactly what §2.4 prepares for.

## 8. Open questions

- True max step rate the TCU module accepts before clamping, and does it vary
  by SoC (T31 vs T23/T21)?
- Does the TMI8152 table's quantization make SixPoint visibly better than a
  well-tuned 3-segment trapezoid on that path?
- What `a_soft:a_hard` ratio reads as "smooth" without adding travel time?
- Is per-model backlash large enough to matter, or is it dominated by homing
  repeatability (hard-stop stall)?
