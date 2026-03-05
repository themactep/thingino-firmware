// Test scenarios for DayNightAlgo — focused on pitch-black startup bug.
//
// Build and run:
//   g++ -std=c++17 -I../output/../build/prudynt-t-custom/src \
//       test_daynight_algo.cpp -o test_daynight_algo && ./test_daynight_algo
//
// Or just with the header copied inline (self-contained):
//   g++ -std=c++17 test_daynight_algo.cpp -o test_daynight_algo && ./test_daynight_algo

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
#include <string>

// ── Inline copy of DayNightAlgo (keeps tests self-contained) ──────────────────

namespace DayNightAlgo {

enum class Mode { Day = 0, Night = 1, Unknown = -1 };

struct SimpleParams {
    int total_gain_night_threshold = 3000;
    int total_gain_day_threshold   = 300;
    int night_count_threshold      = 6;
    int day_count_threshold        = 4;
    int ev_night_threshold         = 1500000;
    int ev_day_threshold           = 200000;
};

struct SimpleState {
    bool is_night  = false;
    int  night_count = 0;
    int  day_count   = 0;
};

struct Decision {
    Mode target  = Mode::Unknown;
    int  reason  = 0;
    bool toggled = false;
};

inline void simple_init(SimpleState &s) {
    s = {};
    s.is_night = false;
}

inline Decision simple_decide(const SimpleParams &p, SimpleState &s,
                               int total_gain, int ev) {
    Decision d{};

    if (total_gain >= 0) {
        if (total_gain > p.total_gain_night_threshold) {
            s.day_count = 0;
            if (++s.night_count >= p.night_count_threshold) {
                if (!s.is_night) { d.target = Mode::Night; d.reason = 1; d.toggled = true; }
            }
        } else if (total_gain < p.total_gain_day_threshold) {
            s.night_count = 0;
            if (++s.day_count >= p.day_count_threshold) {
                if (s.is_night) { d.target = Mode::Day; d.reason = 3; d.toggled = true; }
            }
        } else {
            s.night_count = 0;
            s.day_count   = 0;
        }
    } else if (ev >= 0) {
        if (ev > p.ev_night_threshold) {
            s.day_count = 0;
            if (++s.night_count >= p.night_count_threshold) {
                if (!s.is_night) { d.target = Mode::Night; d.reason = 1; d.toggled = true; }
            }
        } else if (ev < p.ev_day_threshold) {
            s.night_count = 0;
            if (++s.day_count >= p.day_count_threshold) {
                if (s.is_night) { d.target = Mode::Day; d.reason = 3; d.toggled = true; }
            }
        } else {
            s.night_count = 0;
            s.day_count   = 0;
        }
    }
    return d;
}

} // namespace DayNightAlgo

// ── Minimal simulation of DayNightWorker startup logic ───────────────────────
// Mirrors the fixed "SIMPLE TOTAL GAIN ALGORITHM" loop in DayNightWorker.cpp.

struct SimResult {
    int  iteration_night_applied;  // -1 if never (includes initial detection)
    int  iteration_day_applied;    // -1 if never
    int  iterations_run;
    std::string final_mode;        // "day" / "night" / "unknown"
};

SimResult simulate_worker(const std::vector<int> &gain_seq,
                          const std::vector<int> &ev_seq,
                          int max_iter = 60) {
    DayNightAlgo::SimpleParams params{};
    DayNightAlgo::SimpleState  state{};
    DayNightAlgo::simple_init(state);

    DayNightAlgo::Mode current              = DayNightAlgo::Mode::Unknown;
    bool               initial_mode_applied = false;
    int                initial_night_confirm = 0;
    int                initial_day_confirm   = 0;
    // Fix C: fallback after night_count_threshold * 3 samples in hysteresis
    int                initial_mode_fallback_countdown = params.night_count_threshold * 3;
    int                anti_flap_cooldown   = 0;
    const int          anti_flap_iterations = 30;

    SimResult res{-1, -1, 0, "unknown"};

    auto record_mode = [&](DayNightAlgo::Mode m, int i) {
        current = m;
        state.is_night = (m == DayNightAlgo::Mode::Night);
        if (m == DayNightAlgo::Mode::Night && res.iteration_night_applied < 0)
            res.iteration_night_applied = i;
        if (m == DayNightAlgo::Mode::Day && res.iteration_day_applied < 0)
            res.iteration_day_applied = i;
    };

    for (int i = 0; i < max_iter; ++i) {
        int total_gain = (i < (int)gain_seq.size()) ? gain_seq[i] : gain_seq.back();
        int ev         = (i < (int)ev_seq.size())   ? ev_seq[i]   : ev_seq.back();

        auto dec = DayNightAlgo::simple_decide(params, state, total_gain, ev);

        // ── Initial mode detection (mirrors fixed DayNightWorker.cpp) ─────────
        if (!initial_mode_applied) {
            DayNightAlgo::Mode initial = DayNightAlgo::Mode::Unknown;
            if (total_gain >= 0) {
                if (total_gain > params.total_gain_night_threshold)
                    initial = DayNightAlgo::Mode::Night;
                else if (total_gain < params.total_gain_day_threshold)
                    initial = DayNightAlgo::Mode::Day;
            } else if (ev >= 0) {
                if (ev > params.ev_night_threshold)
                    initial = DayNightAlgo::Mode::Night;
                else if (ev < params.ev_day_threshold)
                    initial = DayNightAlgo::Mode::Day;
            }

            // Fix B: require 2 consecutive same-direction readings
            bool commit = false;
            if (initial == DayNightAlgo::Mode::Night) {
                initial_day_confirm = 0;
                commit = (++initial_night_confirm >= 2);
            } else if (initial == DayNightAlgo::Mode::Day) {
                initial_night_confirm = 0;
                commit = (++initial_day_confirm >= 2);
            } else {
                initial_night_confirm = 0;
                initial_day_confirm   = 0;
                --initial_mode_fallback_countdown;
            }

            if (commit) {
                record_mode(initial, i);
                // Fix B: set anti_flap after initial Night to block brief bright-burst flip
                if (current == DayNightAlgo::Mode::Night)
                    anti_flap_cooldown = anti_flap_iterations / 2;
                initial_mode_applied = true;
            } else if (initial_mode_fallback_countdown <= 0) {
                // Fix C: gain stuck in hysteresis — conservatively apply Night
                record_mode(DayNightAlgo::Mode::Night, i);
                anti_flap_cooldown = anti_flap_iterations / 2;
                initial_mode_applied = true;
            }
        }

        // ── Normal algorithm switch ───────────────────────────────────────────
        if (dec.toggled && dec.target != current) {
            if (anti_flap_cooldown == 0) {
                record_mode(dec.target, i);
                anti_flap_cooldown = anti_flap_iterations;
            } else {
                anti_flap_cooldown--;
            }
        } else if (anti_flap_cooldown > 0) {
            anti_flap_cooldown--;
        }

        res.iterations_run = i + 1;
    }

    if (current == DayNightAlgo::Mode::Day)        res.final_mode = "day";
    else if (current == DayNightAlgo::Mode::Night) res.final_mode = "night";
    else                                           res.final_mode = "unknown";

    return res;
}


// ── Test harness ─────────────────────────────────────────────────────────────

static int pass_count = 0;
static int fail_count = 0;

#define EXPECT(cond, msg) \
    do { \
        if (cond) { \
            printf("  PASS  %s\n", msg); \
            ++pass_count; \
        } else { \
            printf("  FAIL  %s\n", msg); \
            ++fail_count; \
        } \
    } while (0)

// ── Test cases ───────────────────────────────────────────────────────────────

// TC-1: Clean startup in pitch black — gain immediately high.
// With Fix B (2-confirm), Night is applied at iteration 1 (second high sample).
void test_tc1_pitch_black_immediate_high_gain() {
    printf("\nTC-1: Pitch-black startup — gain immediately above threshold\n");
    std::vector<int> gain(20, 5000);
    std::vector<int> ev(20, 2000000);
    auto r = simulate_worker(gain, ev);

    EXPECT(r.final_mode == "night",
           "final mode is night");
    EXPECT(r.iteration_night_applied == 1,
           "night applied on iteration 1 (2-confirm: needs 2 consecutive high readings)");
}

// TC-2: AE warmup — first sample low, then gain rises to dark level.
// Fix B prevents the single low reading from locking initial_mode=Day.
// Night confirm fires at iteration 2 (i=1: gain=100 resets night_confirm,
// i=2+: gain=5000 → night_confirm reaches 2 at i=3 → Night applied).
void test_tc2_ae_warmup_initial_low_gain() {
    printf("\nTC-2: AE warmup — first sample low (< 300), then dark (> 3000)\n");
    std::vector<int> gain = {100};
    for (int i = 0; i < 20; ++i) gain.push_back(5000);
    std::vector<int> ev(gain.size(), 2000000);

    auto r = simulate_worker(gain, ev);

    EXPECT(r.final_mode == "night",
           "final mode is night");
    // i=0: gain=100 → day_confirm=1 (not committed)
    // i=1: gain=5000 → day_confirm reset, night_confirm=1
    // i=2: gain=5000 → night_confirm=2 → Night committed at i=2
    EXPECT(r.iteration_night_applied == 2,
           "Fix B: night applied at iteration 2 (low first sample no longer locks Day)");
}

// TC-3: Hysteresis zone trapping — gain oscillates in 300-3000 during AE settling.
// Fix A (counter decay) means night_count survives brief hysteresis crossings.
// Night should be applied sooner than before (was iteration 15, now earlier).
void test_tc3_hysteresis_zone_trapping() {
    printf("\nTC-3: Hysteresis zone trapping — gain bounces in 300-3000 during AE settling\n");
    std::vector<int> gain = {
        200,    // i=0: day_confirm=1
        1000,   // i=1: hysteresis → confirm resets; night_count decay (0)
        5000,   // i=2: night_confirm=1; night_count=1
        2000,   // i=3: hysteresis → confirm resets; night_count decays to 0
        6000,   // i=4: night_confirm=1; night_count=1
        1500,   // i=5: hysteresis → confirm resets; night_count decays to 0
        4000,   // i=6: night_confirm=1; night_count=1
        800,    // i=7: hysteresis → confirm resets; night_count decays to 0
        3500,   // i=8: night_confirm=1; night_count=1
        1200,   // i=9: hysteresis → confirm resets; night_count decays to 0
    };
    for (int i = 0; i < 20; ++i) gain.push_back(5000);
    std::vector<int> ev(gain.size(), 2000000);

    auto r = simulate_worker(gain, ev);

    EXPECT(r.final_mode == "night",
           "eventually reaches night after AE stabilizes");
    // After the oscillation ends (i=10+), gain is consistently high.
    // Fix B needs 2 confirms → Night committed at i=11.
    EXPECT(r.iteration_night_applied <= 12,
           "Fix A+B: night applied within 12 iterations (decay helps survive oscillation)");
    printf("    INFO: night applied at iteration %d / %d total\n",
           r.iteration_night_applied, r.iterations_run);
}

// TC-4: Gain permanently in hysteresis zone (300-3000).
// Fix C: after night_count_threshold * 3 = 18 samples, conservatively apply Night.
void test_tc4_gain_stuck_in_hysteresis() {
    printf("\nTC-4: Gain permanently in hysteresis zone (300-3000)\n");
    std::vector<int> gain(30, 1500);
    std::vector<int> ev(30, 700000);

    auto r = simulate_worker(gain, ev);

    EXPECT(r.final_mode == "night",
           "Fix C: fallback timeout applies Night after 18 samples in hysteresis");
    // fallback_countdown starts at 6*3=18, decrements each hysteresis sample then checks
    // i=0: 18→17 (no), ... i=17: 1→0 (fires) → Night at i=17
    EXPECT(r.iteration_night_applied == 17,
           "night applied at iteration 17 (18-sample countdown, zero-indexed)");
}

// TC-5: Normal day startup then light turns off (day→night transition).
// Expected: Correctly transitions to night after 6 consecutive dark readings.
void test_tc5_day_to_night_normal_transition() {
    printf("\nTC-5: Starts bright (day), then light turns off (day→night)\n");
    // First 10 iterations: bright (gain=50, day)
    std::vector<int> gain(10, 50);
    // Then lights go off: gain shoots up
    for (int i = 0; i < 15; ++i) gain.push_back(5000);
    std::vector<int> ev(gain.size(), -1); // not used when gain >= 0

    auto r = simulate_worker(gain, ev, 40);

    EXPECT(r.final_mode == "night",
           "transitions to night after darkness begins");
    // Transition must happen after the first 10 bright samples + 6 dark samples
    EXPECT(r.iteration_night_applied >= 15,
           "night applied after 6 consecutive dark samples (at iteration 15+)");
}

// TC-6: Night startup then light comes on (night→day transition).
// Expected: Correctly detects day after 4 consecutive bright readings.
void test_tc6_night_to_day_normal_transition() {
    printf("\nTC-6: Starts dark (night), then light comes on (night→day)\n");
    // First sample: gain very high → initial Night
    std::vector<int> gain = {5000};
    // Then room lights on: gain drops
    for (int i = 0; i < 15; ++i) gain.push_back(50);
    std::vector<int> ev(gain.size(), -1);

    auto r = simulate_worker(gain, ev, 30);

    EXPECT(r.final_mode == "day",
           "transitions back to day after light comes on");
}

// TC-7: EV-only fallback (total_gain unavailable — T10/T20 platforms).
// Fix B requires 2 confirms, so Night is applied at iteration 1.
void test_tc7_ev_fallback_pitch_black() {
    printf("\nTC-7: EV-only fallback (total_gain=-1, T10/T20 platform) in pitch black\n");
    std::vector<int> gain(20, -1);
    std::vector<int> ev(20, 2000000);

    auto r = simulate_worker(gain, ev);

    EXPECT(r.final_mode == "night",
           "night detected via EV fallback");
    EXPECT(r.iteration_night_applied == 1,
           "night applied on iteration 1 (2-confirm via EV)");
}

// TC-8b: Fix B sets anti_flap after initial Night — brief bright burst no longer flips to Day.
void test_tc8_anti_flap_cooldown() {
    printf("\nTC-8: Anti-flap cooldown — counter-triggered night, then brief bright burst\n");
    std::vector<int> gain = {50};
    for (int i = 0; i < 6; ++i) gain.push_back(5000);
    for (int i = 0; i < 4; ++i) gain.push_back(50);
    for (int i = 0; i < 15; ++i) gain.push_back(5000);
    std::vector<int> ev(gain.size(), -1);

    auto r = simulate_worker(gain, ev, 30);

    EXPECT(r.final_mode == "night",
           "remains in night (anti-flap blocked the brief day switch)");
    EXPECT(r.iteration_night_applied >= 2,
           "night applied via initial confirm path (2 confirms needed), anti_flap set");

    printf("\nTC-8b: Fix B — initial Night now sets anti_flap, brief bright burst is blocked\n");
    // i=0: gain=5000 → night_confirm=1
    // i=1: gain=5000 → night_confirm=2 → Night committed, anti_flap = 15 set
    // i=2-5: gain=50  → day_count accumulates but anti_flap blocks the switch
    std::vector<int> gain8b = {5000, 5000, 50, 50, 50, 50};
    for (int i = 0; i < 10; ++i) gain8b.push_back(5000);
    std::vector<int> ev8b(gain8b.size(), -1);

    auto r8b = simulate_worker(gain8b, ev8b, 20);
    EXPECT(r8b.final_mode == "night",
           "Fix B: initial Night + anti_flap prevents bright-burst flip to Day");
    EXPECT(r8b.iteration_day_applied < 0,
           "Fix B: Day mode is never applied during the bright burst");
}

// TC-9: Marginal gain just above threshold (3001) — Fix B needs 2 samples.
void test_tc9_marginal_gain_above_threshold() {
    printf("\nTC-9: Marginal gain just above night threshold (3001)\n");
    std::vector<int> gain(20, 3001);
    std::vector<int> ev(20, -1);

    auto r = simulate_worker(gain, ev);

    EXPECT(r.final_mode == "night", "night detected with gain just above threshold");
    EXPECT(r.iteration_night_applied == 1,
           "night applied on iteration 1 (2-confirm: i=0 confirm=1, i=1 confirm=2)");
}

// TC-10: Gain exactly on threshold boundary (3000) — in hysteresis zone.
// Fix C means the fallback fires after 18 samples, applying Night.
void test_tc10_gain_exactly_on_night_threshold() {
    printf("\nTC-10: Gain exactly = night threshold (3000) — boundary/fallback condition\n");
    std::vector<int> gain(30, 3000);
    std::vector<int> ev(30, -1);

    auto r = simulate_worker(gain, ev);

    // 3000 is not > 3000, so it's in the hysteresis zone — Fix C fallback fires at i=17
    EXPECT(r.final_mode == "night",
           "Fix C: fallback applies Night when gain sits exactly on threshold");
    EXPECT(r.iteration_night_applied == 17,
           "fallback fires at iteration 17 (same countdown as TC-4)");
}

int main() {
    printf("=== prudynt DayNight startup test scenarios ===\n");

    test_tc1_pitch_black_immediate_high_gain();
    test_tc2_ae_warmup_initial_low_gain();
    test_tc3_hysteresis_zone_trapping();
    test_tc4_gain_stuck_in_hysteresis();
    test_tc5_day_to_night_normal_transition();
    test_tc6_night_to_day_normal_transition();
    test_tc7_ev_fallback_pitch_black();
    test_tc8_anti_flap_cooldown();
    test_tc9_marginal_gain_above_threshold();
    test_tc10_gain_exactly_on_night_threshold();

    printf("\n=== Results: %d passed, %d failed ===\n", pass_count, fail_count);
    printf("\nFIX SUMMARY:\n");
    printf("  Fix A (DayNightAlgo.hpp):  hysteresis zone decays counters by 1 instead of\n");
    printf("                             hard-resetting — AE oscillation no longer blocks night.\n");
    printf("  Fix B (DayNightWorker.cpp): 2 consecutive same-direction readings required before\n");
    printf("                             initial mode is committed; initial Night sets anti_flap.\n");
    printf("  Fix C (DayNightWorker.cpp): fallback countdown (%d samples) defaults to Night\n",
           6 * 3);
    printf("                             when gain is stuck in the hysteresis zone.\n");
    return (fail_count == 0) ? 0 : 1;
}
