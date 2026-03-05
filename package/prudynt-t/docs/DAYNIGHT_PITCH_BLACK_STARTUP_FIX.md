# Day/Night Pitch-Black Startup Fix

## Problem

When a camera boots in a completely dark (pitch-black) environment, prudynt could
get stuck in **Day mode** — IR-cut filter engaged, no IR LEDs, ISP in colour mode —
producing a black or nearly-black image until the user manually toggled the mode.

Four related bugs in the simple total-gain day/night algorithm were identified:

| ID | File | Symptom |
|----|------|---------|
| TC-2 | `DayNightWorker.cpp` | A single under-settled AE sample (total_gain < 300) on the very first ISP read locked `initial_mode = Day` before the sensor had time to respond to the dark scene. |
| TC-3 | `DayNightAlgo.hpp` | `night_count` was **hard-reset to 0** every time the gain crossed back into the 300–3000 hysteresis zone during AE oscillation, preventing the counter from ever reaching the 6-sample threshold. |
| TC-4 | `DayNightWorker.cpp` | If `total_gain` stayed permanently inside 300–3000 (e.g. twilight / borderline scenes), `initial_mode_applied` was never set and the ISP remained in the hardcoded `IMPISP_RUNNING_MODE_DAY` it was given at `IMPSystem::init()`. |
| TC-8b | `DayNightWorker.cpp` | After initial Night detection, `anti_flap_cooldown` was not set. A brief bright flash (torch, status LED sweep) immediately after boot could flip the camera back to Day mode. |

## Root Cause

`IMPSystem::init()` unconditionally calls:

```cpp
IMP_ISP_Tuning_SetISPRunningMode(IMPISP_RUNNING_MODE_DAY);
```

This is correct — it is the safe ISP hardware default. The bugs are all in
`DayNightWorker`'s simple-algorithm startup path, which did not defend against
the transient sensor readings that occur in the first few milliseconds after the
ISP is enabled.

## Fixes Applied

### Fix A — Hysteresis zone: counter decay (`DayNightAlgo.hpp`)

**Before:**
```cpp
// In between thresholds - reset counters (hysteresis zone)
else {
  s.night_count = 0;
  s.day_count = 0;
}
```

**After:**
```cpp
// Decay counters slowly to tolerate brief AE oscillation.
else {
  if (s.night_count > 0) --s.night_count;
  if (s.day_count > 0) --s.day_count;
}
```

Applied to both the `total_gain` and `EV` branches of `simple_decide`.

**Effect:** A momentary dip into the hysteresis zone loses 1 count rather than
resetting all accumulated evidence. Six dark samples still trigger the switch, but
they no longer need to be strictly consecutive — they can be interrupted by
occasional brief hysteresis crossings.

---

### Fix B — 2-sample confirmation before committing initial mode (`DayNightWorker.cpp`)

Two new counters (`initial_night_confirm`, `initial_day_confirm`) require **2
consecutive same-direction readings** before `initial_mode` is committed. The first
anomalous reading is absorbed without consequence.

```
i=0  total_gain=100 (<300)  → day_confirm=1      (not committed yet)
i=1  total_gain=5000 (>3000) → day_confirm reset,
                                night_confirm=1   (not committed yet)
i=2  total_gain=5000 (>3000) → night_confirm=2   → Night committed ✓
```

Additionally, when initial Night is committed, `anti_flap_cooldown` is set to
`anti_flap_iterations / 2` (15 s). This prevents a brief bright event immediately
after boot from flipping the camera back to Day.

---

### Fix C — Fallback timeout when gain is stuck in hysteresis (`DayNightWorker.cpp`)

```cpp
int initial_mode_fallback_countdown = simple_params.night_count_threshold * 3; // 18 s
```

Each sample where the gain is in the hysteresis zone (and neither confirm counter
advances) decrements the countdown. When it reaches zero the camera defaults to
**Night** and logs a warning:

```
DayNight: initial detection timeout, defaulting to Night
          (gain stuck in hysteresis zone, total_gain=1500)
```

**Rationale:** In a genuinely bright scene the sensor gain falls well below 300
within 1–2 samples, so the Day confirm path fires long before the countdown
expires. Only a truly borderline or dark scene reaches the timeout — and Night is
the safer default for that case.

## Timing Impact

| Scenario | Before | After |
|----------|--------|-------|
| Pitch black, gain stable | Up to 6 s (counter path) or immediate (if first sample > 3000) | ~2 s (2-confirm at i=0,1) |
| AE settling oscillation | Indefinitely stuck (counter kept resetting) | ~11 s worst case (decay survives crossings) |
| Gain permanently in 300–3000 | Stuck forever (ISP stayed in Day) | 18 s (fallback timeout) |
| Brief bright flash after boot in Night | Immediate Day flip | Blocked by 15-sample anti_flap |

## Test Coverage

`package/prudynt-t/tests/test_daynight_algo.cpp` — 10 self-contained test cases
(21 assertions) that exercise all four bug scenarios and their fixes. The
simulation mirrors the `DayNightWorker` loop exactly, including the new confirm
counters and fallback countdown.

Build and run on the host (no cross-compile required):

```sh
cd package/prudynt-t/tests
g++ -std=c++17 test_daynight_algo.cpp -o test_daynight_algo && ./test_daynight_algo
```

## Files Changed

| File | Change |
|------|--------|
| `src/DayNightAlgo.hpp` | Fix A: hysteresis zone counter decay |
| `src/DayNightWorker.cpp` | Fix B: 2-confirm initial mode; Fix C: fallback timeout; Fix B: anti_flap on initial Night |
| *(thingino)* `package/prudynt-t/tests/test_daynight_algo.cpp` | New: host-runnable test suite |
| *(thingino)* `package/prudynt-t/docs/DAYNIGHT_PITCH_BLACK_STARTUP_FIX.md` | This document |
