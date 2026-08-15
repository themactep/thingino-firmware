#!/usr/bin/env python3
"""
Test daynightd initial mode detection across different brightness levels.

Simulates the exact algorithm from daynightd.c:
- compute_brightness_pct() — ev_log2 → 0-100% brightness
- initial mode detection — needs 2 consecutive confirmations
- hysteresis zone between day_threshold and night_threshold
- fallback timeout after night_count_threshold * 3 iterations

Usage:
  ./test_daynight_init.py                    # default thresholds
  ./test_daynight_init.py --step 5           # coarser sweep
  ./test_daynight_init.py --night 40 --day 60  # custom brightness thresholds
"""

import argparse, math, sys

# ── Constants (matching daynightd.c) ──────────────────────────────────
EV_LOG2_BRIGHT = 200_000     # ev_log2 value → 100% brightness
EV_LOG2_DARK   = 2_000_000   # ev_log2 value → 0% brightness
DEFAULT_NIGHT_THRESHOLD_EV  = 550_000  # ev_log2 value for night threshold
DEFAULT_DAY_THRESHOLD_EV    = 350_000  # ev_log2 value for day threshold
DEFAULT_NIGHT_COUNT = 6     # consecutive samples to confirm night (main hysteresis)
DEFAULT_DAY_COUNT   = 4     # consecutive samples to confirm day (main hysteresis)
INITIAL_CONFIRM_COUNT = 2   # consecutive samples to confirm initial mode
BRIGHTNESS_SAMPLES = 10     # moving average window

# ── Brightness ↔ ev_log2 conversion (matching compute_brightness_pct) ─

def ev_to_brightness(ev_log2: int) -> int:
    """Convert raw ev_log2 signal to brightness percentage (0-100)."""
    if ev_log2 <= 0:
        return -1
    lo, hi = float(EV_LOG2_BRIGHT), float(EV_LOG2_DARK)
    ev = float(ev_log2)
    if ev <= lo:
        return 100
    if ev >= hi:
        return 0
    log_ev = math.log(ev)
    log_lo = math.log(lo)
    log_hi = math.log(hi)
    pct = 100.0 * (1.0 - (log_ev - log_lo) / (log_hi - log_lo))
    return max(0, min(100, int(pct + 0.5)))

def brightness_to_ev(pct: int) -> int:
    """Convert brightness percentage to raw ev_log2 value (inverse)."""
    if pct <= 0:
        return EV_LOG2_DARK
    if pct >= 100:
        return EV_LOG2_BRIGHT
    lo, hi = float(EV_LOG2_BRIGHT), float(EV_LOG2_DARK)
    log_val = math.log(lo) + (1.0 - pct / 100.0) * (math.log(hi) - math.log(lo))
    return int(math.exp(log_val) + 0.5)

# ── Simulated daynightd ────────────────────────────────────────────────

class DaynightSim:
    def __init__(self, night_pct: int, day_pct: int):
        """night_pct/day_pct are brightness-% thresholds (0-100)."""
        self.night_thr_ev = brightness_to_ev(night_pct)
        self.day_thr_ev   = brightness_to_ev(day_pct)
        self.current_mode = None  # None = UNKNOWN
        self.mode_set = False
        self.night_confirm = 0
        self.day_confirm = 0
        self.fallback_countdown = DEFAULT_NIGHT_COUNT * 3
        self.history = []

    def step(self, ev_log2: int) -> dict:
        """Feed one sensor sample, return state."""
        brightness = ev_to_brightness(ev_log2)
        sig = ev_log2

        result = {
            "ev_log2": ev_log2,
            "brightness_pct": brightness,
            "night_thr_ev": self.night_thr_ev,
            "day_thr_ev": self.day_thr_ev,
            "night_thr_pct": ev_to_brightness(self.night_thr_ev),
            "day_thr_pct": ev_to_brightness(self.day_thr_ev),
            "mode": "unknown",
            "action": "",
        }

        if self.mode_set:
            result["mode"] = "night" if self.current_mode == 1 else "day"
            return result

        # ── Initial mode detection (matching daynightd.c lines 1209-1269) ─
        initial = None  # None = hysteresis dead zone
        if sig > self.night_thr_ev:
            initial = "night"
        elif sig > 0 and sig < self.day_thr_ev:
            initial = "day"
        # else: hysteresis dead zone → initial stays None

        commit = False
        if initial == "night":
            self.day_confirm = 0
            self.night_confirm += 1
            commit = self.night_confirm >= INITIAL_CONFIRM_COUNT
        elif initial == "day":
            self.night_confirm = 0
            self.day_confirm += 1
            commit = self.day_confirm >= INITIAL_CONFIRM_COUNT
        else:
            # In hysteresis zone
            if self.current_mode is not None:
                self.mode_set = True
                result["action"] = f"kept {result['mode']} (hysteresis, already set)"
            if self.night_confirm > 0:
                self.night_confirm -= 1
            if self.day_confirm > 0:
                self.day_confirm -= 1
            self.fallback_countdown -= 1

        if commit:
            mode_int = 1 if initial == "night" else 0
            self.current_mode = mode_int
            self.mode_set = True
            result["mode"] = initial
            result["action"] = f"COMMIT → {initial.upper()} (confirmed {INITIAL_CONFIRM_COUNT}x)"
        elif self.fallback_countdown <= 0:
            self.current_mode = 1  # night
            self.mode_set = True
            result["mode"] = "night"
            result["action"] = "TIMEOUT → NIGHT (fallback)"
        else:
            result["mode"] = "unknown"
            if initial:
                result["action"] = f"candidate={initial} confirm={self.night_confirm if initial=='night' else self.day_confirm}/{INITIAL_CONFIRM_COUNT}"
            else:
                result["action"] = f"hysteresis zone, fallback={self.fallback_countdown}"

        return result


# ── Test runner ─────────────────────────────────────────────────────────

def run_sweep(night_pct: int, day_pct: int, step_pct: int = 2):
    """Sweep brightness from 100→0, running initial mode detection at each level."""
    sim = DaynightSim(night_pct, day_pct)
    night_thr_pct = ev_to_brightness(brightness_to_ev(night_pct))
    day_thr_pct   = ev_to_brightness(brightness_to_ev(day_pct))

    print(f"{'='*70}")
    print(f"Daynightd initial mode sweep")
    print(f"  Night threshold: {night_pct}% → ev={brightness_to_ev(night_pct):,} (computed brightness: {night_thr_pct}%)")
    print(f"  Day threshold:   {day_pct}% → ev={brightness_to_ev(day_pct):,} (computed brightness: {day_thr_pct}%)")
    print(f"  Hysteresis zone: {night_thr_pct}% to {day_thr_pct}% brightness")
    print(f"  Initial confirm count: {INITIAL_CONFIRM_COUNT}")
    print(f"  Fallback timeout: {DEFAULT_NIGHT_COUNT * 3} samples")
    print(f"{'='*70}")
    print(f"{'Bright%':>8} {'ev_log2':>10} {'NightThr':>10} {'DayThr':>10} {'Decision':>12} {'Action'}")
    print(f"{'-'*8} {'-'*10} {'-'*10} {'-'*10} {'-'*12} {'-'*40}")

    for pct in range(100, -1, -step_pct):
        ev = brightness_to_ev(pct)
        r = sim.step(ev)
        print(f"{r['brightness_pct']:>8}% {r['ev_log2']:>10,} "
              f"{r['night_thr_pct']:>10}% {r['day_thr_pct']:>10}% "
              f"{r['mode']:>12} {r['action']}")

    # Show the final mode
    print(f"\n→ Result: camera would boot in {sim.current_mode and 'NIGHT' or 'DAY'} mode "
          f"(settled after {INITIAL_CONFIRM_COUNT} confirmations)")


def run_single(night_pct: int, day_pct: int, brightness_pct: int, samples: int = 10):
    """Run initial mode detection at a single brightness level with multiple samples."""
    sim = DaynightSim(night_pct, day_pct)
    ev = brightness_to_ev(brightness_pct)

    print(f"Testing {samples} samples at {brightness_pct}% brightness "
          f"(ev={ev:,}, night_thr={night_pct}%, day_thr={day_pct}%)")
    print(f"{'Sample':>6} {'Mode':>8} {'Action'}")

    for i in range(samples):
        r = sim.step(ev)
        print(f"{i+1:>6} {r['mode']:>8} {r['action']}")
        if sim.mode_set:
            print(f"  → Settled in {i+1} samples")
            break
    else:
        print(f"  → Did not settle after {samples} samples (fallback would trigger)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Test daynightd initial mode detection")
    parser.add_argument("--night", type=int, default=None,
                        help="Night threshold brightness %% (default: compute from DEFAULT_EV_NIGHT_THRESHOLD)")
    parser.add_argument("--day", type=int, default=None,
                        help="Day threshold brightness %% (default: compute from DEFAULT_EV_DAY_THRESHOLD)")
    parser.add_argument("--step", type=int, default=2,
                        help="Brightness step for sweep (default: 2)")
    parser.add_argument("--single", type=int, default=None,
                        help="Test a single brightness level instead of sweeping")
    parser.add_argument("--samples", type=int, default=10,
                        help="Number of samples for --single test (default: 10)")
    parser.add_argument("--list-thresholds", action="store_true",
                        help="Show the brightness%% ↔ ev_log2 mapping table")
    args = parser.parse_args()

    if args.list_thresholds:
        print("Brightness% ↔ ev_log2 mapping:")
        print(f"{'%':>6} {'ev_log2':>12}")
        for pct in range(100, -1, -5):
            print(f"{pct:>6} {brightness_to_ev(pct):>12,}")
        sys.exit(0)

    night_pct = args.night if args.night is not None else ev_to_brightness(DEFAULT_NIGHT_THRESHOLD_EV)
    day_pct   = args.day   if args.day   is not None else ev_to_brightness(DEFAULT_DAY_THRESHOLD_EV)

    if args.single is not None:
        run_single(night_pct, day_pct, args.single, args.samples)
    else:
        run_sweep(night_pct, day_pct, args.step)
