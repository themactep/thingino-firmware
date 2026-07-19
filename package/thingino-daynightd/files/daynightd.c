/*
 * daynightd.c - Automatic Day/Night Mode Switching Daemon for Thingino
 *
 * Copyright (C) 2025 Thingino Project
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * Single source of truth for day/night photosensing on Thingino.
 * Supports T31/T23/T21/T30 (via /proc/jz/isp/isp-m0) and
 * T20 (via /proc/jz/isp/isp_info).
 * Uses ISP total_gain as primary signal when available (T20),
 * falling back to EV log2 (T31).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <syslog.h>
#include <stdarg.h>
#include <stdbool.h>
#include <getopt.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <json_config.h>
#include <ctype.h>
#include <math.h>

/* =========================================================================
 * Configuration defaults
 * ========================================================================= */

#define DEFAULT_CONFIG_FILE       "/etc/thingino.json"
#define DEFAULT_PID_FILE          "/run/daynightd.pid"
#define DEFAULT_SAMPLE_INTERVAL_MS 1000
#define DEFAULT_TRANSITION_DELAY_S 5
#define DEFAULT_HYSTERESIS_FACTOR  0.15f

/* EV log2 thresholds — for /proc/jz/isp/isp-m0 on T31/T23.
 * Day scenes: ~200K-500K, Night scenes: ~600K-2M+.
 * Default: switch to night > 550000, switch to day < 350000 */
#define DEFAULT_EV_NIGHT_THRESHOLD  550000
#define DEFAULT_EV_DAY_THRESHOLD    350000

/* Total-gain thresholds — for platforms that expose ISP total gain directly
 * (T20 via /proc/jz/isp/isp_info has "ISP total gain" field).
 * Day scenes: ~200-1000, Night scenes: ~2000-6000+.
 * Default: switch to night > 2000, switch to day < 800 */
#define DEFAULT_TG_NIGHT_THRESHOLD  2000
#define DEFAULT_TG_DAY_THRESHOLD    800
#define DEFAULT_NIGHT_COUNT         6
#define DEFAULT_DAY_COUNT           4

/* Thingino paths */
#define THINGINO_DAYNIGHT_SCRIPT   "/sbin/daynight"
#define ISP_M0_PATH                "/proc/jz/isp/isp-m0"   /* T31/T23/T21/T30 */
#define ISP_INFO_PATH              "/proc/jz/isp/isp_info" /* T20 */

/* Run dir */
#define RUN_DIR                    "/run/thingino"
#define MODE_FILE                  "/run/thingino/daynight_mode"
#define BRIGHTNESS_FILE            "/run/thingino/daynight_brightness"
#define SENSORS_FILE               "/run/thingino/daynight_sensors"
#define VALUE_FILE                 "/run/thingino/daynight_value"
#define HISTORY_FILE               "/run/thingino/daynight_history"

/* Ring buffer */
#define HISTORY_MAX_ENTRIES        300

/* Misc */
#define MAX_COMMAND_LEN            256
#define MAX_LINE_LEN               256
#define MAX_PATH_LEN               256
#define BRIGHTNESS_SAMPLES         10

/* =========================================================================
 * Types
 * ========================================================================= */

typedef enum {
    MODE_DAY = 0,
    MODE_NIGHT = 1,
    MODE_UNKNOWN = -1
} daynight_mode_t;

/* Raw sensor sample — platform-agnostic, fields parsed if available.
 * T31/T23: /proc/jz/isp/isp-m0
 * T20:     /proc/jz/isp/isp_info */
typedef struct {
    int64_t  time_now;
    int      ev;
    int      ev_log2;           /* T31: ISP EV value log2; T20: ISP exposure log2 id */
    int      ev_us;
    int      total_gain;        /* T20: ISP total gain (direct); T31: approximated from gains */
    int      integration_time;
    int      max_integration_time;
    int      analog_gain;
    int      max_analog_gain;
    int      digital_gain;
    int      isp_digital_gain;
    int      max_isp_digital_gain;
    int      gain_log2;         /* T20 only */
    int      wb_rgain;
    int      wb_bgain;
    int      wb_color_temp;
    int      brightness_pct;
    int      primary_signal;    /* the value used for decision (total_gain or ev_log2) */
    int      night_threshold;   /* active night threshold */
    int      day_threshold;     /* active day threshold */
    char     isp_mode[32];
    char     daynight_mode[16];
    char     platform[8];       /* "t31" or "t20" */
} sensor_sample_t;

/* Ring buffer */
typedef struct {
    sensor_sample_t samples[HISTORY_MAX_ENTRIES];
    int             head;
    int             count;
} history_buffer_t;

/* Daynight configuration */
typedef struct {
    char     config_file[MAX_PATH_LEN];
    char     pid_file[MAX_PATH_LEN];
    char     script_path[MAX_PATH_LEN];

    /* Algorithm thresholds — EV log2 based (T31/T23) */
    int      ev_night_threshold;
    int      ev_day_threshold;
    /* Algorithm thresholds — total_gain based (T20) */
    int      tg_night_threshold;
    int      tg_day_threshold;
    int      night_count_threshold;
    int      day_count_threshold;

    /* Timing */
    int      sample_interval_ms;
    int      transition_delay_s;
    float    hysteresis_factor;

    /* Schedule */
    bool     schedule_enabled;
    char     schedule_start_at[8];
    char     schedule_stop_at[8];

    /* Controls — which hardware to toggle on mode change */
    bool     controls_color;
    bool     controls_ircut;
    bool     controls_ir850;
    bool     controls_ir940;
    bool     controls_white;

    /* System */
    bool     enabled;           /* master enable for photosensing */
    bool     daemon_mode;
    bool     enable_syslog;
    int      log_level;         /* 0=FATAL..5=TRACE */

    /* Force mode */
    char     force_mode[16];    /* "day", "night", or "" for auto */
} daynight_config_t;

/* Runtime state */
typedef struct {
    daynight_mode_t current_mode;
    struct timeval  last_transition;
    float           brightness_history[BRIGHTNESS_SAMPLES];
    int             brightness_index;
    bool            running;
    int             night_count;
    int             day_count;
    bool            initial_mode_set;
    int             anti_flap_cooldown;
    int             initial_night_confirm;
    int             initial_day_confirm;
    int             initial_fallback_countdown;
    sensor_sample_t latest_sample;
    bool            use_total_gain;  /* true if platform provides total_gain (T20) */
} daynight_state_t;

/* =========================================================================
 * Globals
 * ========================================================================= */

static daynight_config_t g_config;
static daynight_state_t  g_state;
static history_buffer_t  g_history;
static volatile sig_atomic_t g_terminate_flag = 0;
static volatile sig_atomic_t g_reload_flag    = 0;
static volatile sig_atomic_t g_force_day_flag  = 0;
static volatile sig_atomic_t g_force_night_flag = 0;

/* =========================================================================
 * Forward declarations
 * ========================================================================= */

static void signal_handler(int sig);
static int  read_config(const char *config_file);
static int  parse_isp(sensor_sample_t *s);
static int  parse_isp_m0(sensor_sample_t *s);
static int  parse_isp_info(sensor_sample_t *s);
static int  execute_command(const char *command, char *output, size_t output_size);
static int  apply_mode(daynight_mode_t new_mode);
static void log_message(int level, const char *format, ...) __attribute__((format(printf, 2, 3)));
static int  create_pid_file(void);
static void remove_pid_file(void);
static void daemonize(void);
static int  parse_log_level_string(const char *s);
static const char *log_level_name(int level);
static int  main_loop(void);
static void write_state_files(const sensor_sample_t *s, daynight_mode_t mode);
static void history_push(const sensor_sample_t *s);
static bool is_within_schedule(void);
static int  compute_brightness_pct(const sensor_sample_t *s);
static void write_mode_file(daynight_mode_t mode);
static void write_sensors_json(const sensor_sample_t *s);
static void write_history_json(void);
static int  load_force_mode_from_config(void);

/* =========================================================================
 * Signal handler
 * ========================================================================= */

static void signal_handler(int sig) {
    switch (sig) {
        case SIGTERM:
        case SIGINT:
            g_terminate_flag = 1;
            g_state.running = false;
            break;
        case SIGUSR1:
            g_force_day_flag = 1;
            break;
        case SIGUSR2:
            g_force_night_flag = 1;
            break;
        case SIGHUP:
            g_reload_flag = 1;
            break;
    }
}

/* =========================================================================
 * Log level parsing
 * ========================================================================= */

static int parse_log_level_string(const char *s) {
    if (!s) return -1;
    const char *start = s;
    while (*start && isspace((unsigned char)*start)) start++;
    const char *end = start + strlen(start);
    while (end > start && isspace((unsigned char)end[-1])) end--;
    size_t len = (size_t)(end - start);
    if (len == 0 || len > 16) return -1;

    char buf[17];
    for (size_t i = 0; i < len; ++i)
        buf[i] = (char)toupper((unsigned char)start[i]);
    buf[len] = '\0';

    if (!strcmp(buf, "FATAL"))   return 0;
    if (!strcmp(buf, "ERROR"))   return 1;
    if (!strcmp(buf, "WARN") || !strcmp(buf, "WARNING")) return 2;
    if (!strcmp(buf, "INFO"))    return 3;
    if (!strcmp(buf, "DEBUG"))   return 4;
    if (!strcmp(buf, "TRACE"))   return 5;
    return -1;
}

static const char *log_level_name(int level) {
    switch (level) {
        case 0: return "FATAL";
        case 1: return "ERROR";
        case 2: return "WARN";
        case 3: return "INFO";
        case 4: return "DEBUG";
        case 5: return "TRACE";
        default: return "UNKNOWN";
    }
}

/* =========================================================================
 * Logging
 * ========================================================================= */

static void log_message(int level, const char *format, ...) {
    int msg_level_num;
    switch (level) {
        case LOG_EMERG:  case LOG_ALERT: case LOG_CRIT:
            msg_level_num = 0; break;
        case LOG_ERR:    msg_level_num = 1; break;
        case LOG_WARNING: msg_level_num = 2; break;
        case LOG_INFO:   msg_level_num = 3; break;
        case LOG_DEBUG:  msg_level_num = 4; break;
        default:         msg_level_num = 4; break;
    }

    if (msg_level_num > g_config.log_level) return;

    const char *level_str;
    switch (level) {
        case LOG_EMERG: case LOG_ALERT: case LOG_CRIT:
            level_str = "FATAL"; break;
        case LOG_ERR:    level_str = "ERROR"; break;
        case LOG_WARNING: level_str = "WARN"; break;
        case LOG_INFO:   level_str = "INFO"; break;
        case LOG_DEBUG:
            level_str = (g_config.log_level >= 5) ? "TRACE" : "DEBUG"; break;
        default: level_str = "UNKNOWN"; break;
    }

    va_list args;
    char buffer[512];
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);

    if (g_config.enable_syslog)
        syslog(level, "[%s] %s", level_str, buffer);

    if (!g_config.daemon_mode || g_config.log_level > 0) {
        struct timeval tv;
        gettimeofday(&tv, NULL);
        fprintf(stderr, "[%lld.%03lld] %s: %s\n",
                (long long)tv.tv_sec, (long long)(tv.tv_usec / 1000),
                level_str, buffer);
    }
}

/* =========================================================================
 * Configuration loading
 * ========================================================================= */

static void set_config_defaults(void) {
    strncpy(g_config.config_file, DEFAULT_CONFIG_FILE, sizeof(g_config.config_file) - 1);
    strncpy(g_config.pid_file, DEFAULT_PID_FILE, sizeof(g_config.pid_file) - 1);
    strncpy(g_config.script_path, THINGINO_DAYNIGHT_SCRIPT, sizeof(g_config.script_path) - 1);

    g_config.ev_night_threshold     = DEFAULT_EV_NIGHT_THRESHOLD;
    g_config.ev_day_threshold       = DEFAULT_EV_DAY_THRESHOLD;
    g_config.tg_night_threshold     = DEFAULT_TG_NIGHT_THRESHOLD;
    g_config.tg_day_threshold       = DEFAULT_TG_DAY_THRESHOLD;
    g_config.night_count_threshold  = DEFAULT_NIGHT_COUNT;
    g_config.day_count_threshold    = DEFAULT_DAY_COUNT;
    g_config.sample_interval_ms     = DEFAULT_SAMPLE_INTERVAL_MS;
    g_config.transition_delay_s     = DEFAULT_TRANSITION_DELAY_S;
    g_config.hysteresis_factor      = DEFAULT_HYSTERESIS_FACTOR;

    g_config.schedule_enabled = false;
    g_config.schedule_start_at[0] = '\0';
    g_config.schedule_stop_at[0]  = '\0';

    g_config.controls_color = true;
    g_config.controls_ircut = true;
    g_config.controls_ir850 = true;
    g_config.controls_ir940 = true;
    g_config.controls_white = false;

    g_config.enabled       = true;
    g_config.daemon_mode   = true;
    g_config.enable_syslog = true;
    g_config.log_level     = 3;  /* INFO */

    g_config.force_mode[0] = '\0';
}

static int read_config(const char *config_file) {
    set_config_defaults();
    strncpy(g_config.config_file, config_file, sizeof(g_config.config_file) - 1);
    g_config.config_file[sizeof(g_config.config_file) - 1] = '\0';

    JsonValue *root = load_config(config_file);
    if (!root) {
        log_message(LOG_WARNING, "Config file %s not found, using defaults", config_file);
        return 0;
    }

    JsonValue *v;

    /* --- daynight section --- */
    v = get_nested_item(root, "daynight.enabled");
    if (v && v->type == JSON_BOOL) g_config.enabled = v->value.boolean;

    v = get_nested_item(root, "daynight.ev_night_threshold");
    if (v && v->type == JSON_NUMBER)
        g_config.ev_night_threshold = (int)v->value.number.integer;

    v = get_nested_item(root, "daynight.ev_day_threshold");
    if (v && v->type == JSON_NUMBER)
        g_config.ev_day_threshold = (int)v->value.number.integer;

    v = get_nested_item(root, "daynight.tg_night_threshold");
    if (v && v->type == JSON_NUMBER)
        g_config.tg_night_threshold = (int)v->value.number.integer;

    v = get_nested_item(root, "daynight.tg_day_threshold");
    if (v && v->type == JSON_NUMBER)
        g_config.tg_day_threshold = (int)v->value.number.integer;

    v = get_nested_item(root, "daynight.night_count_threshold");
    if (v && v->type == JSON_NUMBER)
        g_config.night_count_threshold = (int)v->value.number.integer;

    v = get_nested_item(root, "daynight.day_count_threshold");
    if (v && v->type == JSON_NUMBER)
        g_config.day_count_threshold = (int)v->value.number.integer;

    v = get_nested_item(root, "daynight.sample_interval_ms");
    if (v && v->type == JSON_NUMBER)
        g_config.sample_interval_ms = (int)v->value.number.integer;

    v = get_nested_item(root, "daynight.transition_delay_s");
    if (v && v->type == JSON_NUMBER)
        g_config.transition_delay_s = (int)v->value.number.integer;

    v = get_nested_item(root, "daynight.script_path");
    if (v && v->type == JSON_STRING && v->value.string) {
        strncpy(g_config.script_path, v->value.string, sizeof(g_config.script_path) - 1);
        g_config.script_path[sizeof(g_config.script_path) - 1] = '\0';
    }

    v = get_nested_item(root, "daynight.loglevel");
    if (v && v->type == JSON_STRING && v->value.string) {
        int lvl = parse_log_level_string(v->value.string);
        if (lvl >= 0) g_config.log_level = lvl;
    }

    /* Controls */
    v = get_nested_item(root, "daynight.controls.color");
    if (v && v->type == JSON_BOOL) g_config.controls_color = v->value.boolean;
    v = get_nested_item(root, "daynight.controls.ircut");
    if (v && v->type == JSON_BOOL) g_config.controls_ircut = v->value.boolean;
    v = get_nested_item(root, "daynight.controls.ir850");
    if (v && v->type == JSON_BOOL) g_config.controls_ir850 = v->value.boolean;
    v = get_nested_item(root, "daynight.controls.ir940");
    if (v && v->type == JSON_BOOL) g_config.controls_ir940 = v->value.boolean;
    v = get_nested_item(root, "daynight.controls.white");
    if (v && v->type == JSON_BOOL) g_config.controls_white = v->value.boolean;

    /* Schedule */
    v = get_nested_item(root, "daynight.schedule.enabled");
    if (v && v->type == JSON_BOOL) g_config.schedule_enabled = v->value.boolean;
    v = get_nested_item(root, "daynight.schedule.start_at");
    if (v && v->type == JSON_STRING && v->value.string) {
        strncpy(g_config.schedule_start_at, v->value.string,
                sizeof(g_config.schedule_start_at) - 1);
    }
    v = get_nested_item(root, "daynight.schedule.stop_at");
    if (v && v->type == JSON_STRING && v->value.string) {
        strncpy(g_config.schedule_stop_at, v->value.string,
                sizeof(g_config.schedule_stop_at) - 1);
    }

    /* Force mode */
    v = get_nested_item(root, "daynight.force_mode");
    if (v && v->type == JSON_STRING && v->value.string) {
        strncpy(g_config.force_mode, v->value.string, sizeof(g_config.force_mode) - 1);
        g_config.force_mode[sizeof(g_config.force_mode) - 1] = '\0';
    }

    /* System section */
    v = get_nested_item(root, "system.enable_syslog");
    if (v && v->type == JSON_BOOL) g_config.enable_syslog = v->value.boolean;
    v = get_nested_item(root, "system.daemon_mode");
    if (v && v->type == JSON_BOOL) g_config.daemon_mode = v->value.boolean;
    v = get_nested_item(root, "system.debug_level");
    if (v && v->type == JSON_STRING && v->value.string) {
        int lvl = parse_log_level_string(v->value.string);
        if (lvl >= 0) g_config.log_level = lvl;
    }
    v = get_nested_item(root, "system.pid_file");
    if (v && v->type == JSON_STRING && v->value.string) {
        strncpy(g_config.pid_file, v->value.string, sizeof(g_config.pid_file) - 1);
        g_config.pid_file[sizeof(g_config.pid_file) - 1] = '\0';
    }

    /* Backward compat: flat threshold keys */
    v = get_nested_item(root, "ev_night_threshold");
    if (v && v->type == JSON_NUMBER)
        g_config.ev_night_threshold = (int)v->value.number.integer;
    v = get_nested_item(root, "ev_day_threshold");
    if (v && v->type == JSON_NUMBER)
        g_config.ev_day_threshold = (int)v->value.number.integer;
    v = get_nested_item(root, "tg_night_threshold");
    if (v && v->type == JSON_NUMBER)
        g_config.tg_night_threshold = (int)v->value.number.integer;
    v = get_nested_item(root, "tg_day_threshold");
    if (v && v->type == JSON_NUMBER)
        g_config.tg_day_threshold = (int)v->value.number.integer;

    free_json_value(root);

    /* Validate */
    if (g_config.ev_day_threshold >= g_config.ev_night_threshold) {
        log_message(LOG_ERR, "Invalid EV thresholds: day=%d >= night=%d",
                    g_config.ev_day_threshold, g_config.ev_night_threshold);
        return -1;
    }
    if (g_config.tg_day_threshold >= g_config.tg_night_threshold) {
        log_message(LOG_ERR, "Invalid total_gain thresholds: day=%d >= night=%d",
                    g_config.tg_day_threshold, g_config.tg_night_threshold);
        return -1;
    }
    if (g_config.sample_interval_ms < 100 || g_config.sample_interval_ms > 60000) {
        log_message(LOG_WARNING, "Sample interval %d ms out of range, using %d",
                    g_config.sample_interval_ms, DEFAULT_SAMPLE_INTERVAL_MS);
        g_config.sample_interval_ms = DEFAULT_SAMPLE_INTERVAL_MS;
    }

    log_message(LOG_INFO, "Config loaded: platform thresholds ev=%d/%d tg=%d/%d",
                g_config.ev_day_threshold, g_config.ev_night_threshold,
                g_config.tg_day_threshold, g_config.tg_night_threshold);

    return 0;
}

static int load_force_mode_from_config(void) {
    JsonValue *root = load_config(g_config.config_file);
    if (!root) return -1;

    JsonValue *v = get_nested_item(root, "daynight.force_mode");
    if (v && v->type == JSON_STRING && v->value.string) {
        strncpy(g_config.force_mode, v->value.string, sizeof(g_config.force_mode) - 1);
        g_config.force_mode[sizeof(g_config.force_mode) - 1] = '\0';
    } else {
        g_config.force_mode[0] = '\0';
    }

    v = get_nested_item(root, "daynight.schedule.enabled");
    if (v && v->type == JSON_BOOL) g_config.schedule_enabled = v->value.boolean;
    v = get_nested_item(root, "daynight.enabled");
    if (v && v->type == JSON_BOOL) g_config.enabled = v->value.boolean;

    v = get_nested_item(root, "daynight.controls.color");
    if (v && v->type == JSON_BOOL) g_config.controls_color = v->value.boolean;
    v = get_nested_item(root, "daynight.controls.ircut");
    if (v && v->type == JSON_BOOL) g_config.controls_ircut = v->value.boolean;
    v = get_nested_item(root, "daynight.controls.ir850");
    if (v && v->type == JSON_BOOL) g_config.controls_ir850 = v->value.boolean;
    v = get_nested_item(root, "daynight.controls.ir940");
    if (v && v->type == JSON_BOOL) g_config.controls_ir940 = v->value.boolean;
    v = get_nested_item(root, "daynight.controls.white");
    if (v && v->type == JSON_BOOL) g_config.controls_white = v->value.boolean;

    free_json_value(root);

    log_message(LOG_INFO, "Config reloaded: force=%s sched=%s enabled=%s",
                g_config.force_mode[0] ? g_config.force_mode : "auto",
                g_config.schedule_enabled ? "on" : "off",
                g_config.enabled ? "yes" : "no");
    return 0;
}

/* =========================================================================
 * ISP data parsing — platform-specific
 * ========================================================================= */

static void init_sample(sensor_sample_t *s) {
    memset(s, 0, sizeof(*s));
    s->time_now = (int64_t)time(NULL);
    s->ev = -1;
    s->ev_log2 = -1;
    s->ev_us = -1;
    s->total_gain = -1;
    s->integration_time = -1;
    s->max_integration_time = -1;
    s->analog_gain = -1;
    s->max_analog_gain = -1;
    s->digital_gain = -1;
    s->isp_digital_gain = -1;
    s->max_isp_digital_gain = -1;
    s->gain_log2 = -1;
    s->wb_rgain = -1;
    s->wb_bgain = -1;
    s->wb_color_temp = -1;
    s->brightness_pct = -1;
    s->primary_signal = -1;
    s->isp_mode[0] = '\0';
    s->daynight_mode[0] = '\0';
    s->platform[0] = '\0';
}

/* Parse /proc/jz/isp/isp-m0 — T31, T23, T21, T30 */
static int parse_isp_m0(sensor_sample_t *s) {
    FILE *fp = fopen(ISP_M0_PATH, "r");
    if (!fp) return -1;

    char line[MAX_LINE_LEN];
    strncpy(s->platform, "t31", sizeof(s->platform) - 1);

    while (fgets(line, sizeof(line), fp)) {
        if (strstr(line, "ISP Runing Mode :"))
            sscanf(line, "ISP Runing Mode : %31s", s->isp_mode);
        else if (strstr(line, "SENSOR Integration Time :"))
            sscanf(line, "SENSOR Integration Time : %d lines", &s->integration_time);
        else if (strstr(line, "SENSOR Max Integration Time :"))
            sscanf(line, "SENSOR Max Integration Time : %d lines", &s->max_integration_time);
        else if (strstr(line, "MAX SENSOR analog gain :"))
            sscanf(line, "MAX SENSOR analog gain : %d", &s->max_analog_gain);
        else if (strstr(line, "SENSOR analog gain :"))
            sscanf(line, "SENSOR analog gain : %d", &s->analog_gain);
        else if (strstr(line, "SENSOR digital gain :"))
            sscanf(line, "SENSOR digital gain : %d", &s->digital_gain);
        else if (strstr(line, "MAX ISP digital gain :"))
            sscanf(line, "MAX ISP digital gain : %d", &s->max_isp_digital_gain);
        else if (strstr(line, "ISP digital gain :"))
            sscanf(line, "ISP digital gain : %d", &s->isp_digital_gain);
        else if (strstr(line, "ISP EV value log2:"))
            sscanf(line, "ISP EV value log2: %d", &s->ev_log2);
        else if (strstr(line, "ISP EV value us:"))
            sscanf(line, "ISP EV value us: %d", &s->ev_us);
        else if (strstr(line, "ISP EV value:"))
            sscanf(line, "ISP EV value: %d", &s->ev);
        else if (strstr(line, "ISP WB weighted rgain:"))
            sscanf(line, "ISP WB weighted rgain: %d", &s->wb_rgain);
        else if (strstr(line, "ISP WB weighted bgain:"))
            sscanf(line, "ISP WB weighted bgain: %d", &s->wb_bgain);
        else if (strstr(line, "ISP WB color temperature:"))
            sscanf(line, "ISP WB color temperature: %d", &s->wb_color_temp);
    }
    fclose(fp);

    /* T31 does not expose ISP total gain; approximate from available gains.
     * Use EV log2 as the primary decision signal. */
    s->total_gain = -1;  /* not available in isp-m0 */
    if (s->ev_log2 > 0) {
        s->primary_signal = s->ev_log2;
    }

    return 0;
}

/* Parse /proc/jz/isp/isp_info — T20 */
static int parse_isp_info(sensor_sample_t *s) {
    FILE *fp = fopen(ISP_INFO_PATH, "r");
    if (!fp) return -1;

    char line[MAX_LINE_LEN];
    strncpy(s->platform, "t20", sizeof(s->platform) - 1);

    while (fgets(line, sizeof(line), fp)) {
        if (strstr(line, "ISP Runing Mode :"))
            sscanf(line, "ISP Runing Mode : %31s", s->isp_mode);
        else if (strstr(line, "SENSOR Integration Time :"))
            sscanf(line, "SENSOR Integration Time : %d lines", &s->integration_time);
        else if (strstr(line, "MAX SENSOR analog gain :"))
            sscanf(line, "MAX SENSOR analog gain : %d", &s->max_analog_gain);
        else if (strstr(line, "SENSOR analog gain :"))
            sscanf(line, "SENSOR analog gain : %d", &s->analog_gain);
        else if (strstr(line, "SENSOR digital gain :"))
            sscanf(line, "SENSOR digital gain : %d", &s->digital_gain);
        else if (strstr(line, "MAX ISP digital gain :"))
            sscanf(line, "MAX ISP digital gain : %d", &s->max_isp_digital_gain);
        else if (strstr(line, "ISP digital gain :"))
            sscanf(line, "ISP digital gain : %d", &s->isp_digital_gain);
        /* T20-specific fields */
        else if (strstr(line, "ISP total gain :"))
            sscanf(line, "ISP total gain : %d", &s->total_gain);
        else if (strstr(line, "ISP gain log2 id :"))
            sscanf(line, "ISP gain log2 id : %d", &s->gain_log2);
        else if (strstr(line, "ISP exposure log2 id:"))
            sscanf(line, "ISP exposure log2 id: %d", &s->ev_log2);
        else if (strstr(line, "ISP WB rg :"))
            sscanf(line, "ISP WB rg : %d", &s->wb_rgain);
        else if (strstr(line, "ISP WB bg :"))
            sscanf(line, "ISP WB bg : %d", &s->wb_bgain);
        else if (strstr(line, "ISP WB Temperature :"))
            sscanf(line, "ISP WB Temperature : %d", &s->wb_color_temp);
    }
    fclose(fp);

    /* T20: use total_gain as primary signal when available */
    if (s->total_gain > 0) {
        s->primary_signal = s->total_gain;
    } else if (s->ev_log2 > 0) {
        s->primary_signal = s->ev_log2;
    }

    return 0;
}

/* Try both platform proc paths; prefer isp-m0 (T31), fallback to isp_info (T20) */
static int parse_isp(sensor_sample_t *s) {
    init_sample(s);

    if (parse_isp_m0(s) == 0) {
        log_message(LOG_DEBUG, "Parsed isp-m0 (T31)");
        return 0;
    }

    if (parse_isp_info(s) == 0) {
        log_message(LOG_DEBUG, "Parsed isp_info (T20)");
        return 0;
    }

    log_message(LOG_DEBUG, "No ISP proc file found");
    return -1;
}

/* =========================================================================
 * Brightness percentage calculation
 * ========================================================================= */

static int compute_brightness_pct(const sensor_sample_t *s) {
    /* T20 with total_gain: map total_gain 0..8000 → 100%..0% */
    if (s->total_gain > 0) {
        int lo = 100;    /* bright */
        int hi = 8000;   /* dark */
        int val = s->total_gain;
        if (val <= lo) return 100;
        if (val >= hi) return 0;
        return 100 - ((val - lo) * 100 / (hi - lo));
    }

    /* T31 with ev_log2: use logarithmic mapping */
    if (s->ev_log2 > 0) {
        double lo = 200000.0;   /* bright: 100% */
        double hi = 2000000.0;  /* dark: 0% */
        double ev = (double)s->ev_log2;
        if (ev <= lo) return 100;
        if (ev >= hi) return 0;
        double log_ev = log(ev);
        double log_lo = log(lo);
        double log_hi = log(hi);
        double pct = 100.0 * (1.0 - (log_ev - log_lo) / (log_hi - log_lo));
        int result = (int)(pct + 0.5);
        if (result < 0) result = 0;
        if (result > 100) result = 100;
        return result;
    }

    /* Fallback: integration time ratio */
    if (s->integration_time >= 0 && s->max_integration_time > 0) {
        float ratio = (float)s->integration_time / (float)s->max_integration_time;
        int pct = (int)((1.0f - ratio) * 100.0f);
        if (pct < 0) pct = 0;
        if (pct > 100) pct = 100;
        return pct;
    }

    return -1;
}

/* =========================================================================
 * Schedule check
 * ========================================================================= */

static bool is_within_schedule(void) {
    if (!g_config.schedule_enabled) return true;
    if (g_config.schedule_start_at[0] == '\0' || g_config.schedule_stop_at[0] == '\0')
        return true;

    int start_h = 0, start_m = 0, stop_h = 0, stop_m = 0;
    if (sscanf(g_config.schedule_start_at, "%d:%d", &start_h, &start_m) != 2 ||
        sscanf(g_config.schedule_stop_at, "%d:%d", &stop_h, &stop_m) != 2)
        return true;

    time_t now = time(NULL);
    struct tm *lt = localtime(&now);
    int cur_mins = lt->tm_hour * 60 + lt->tm_min;
    int start_mins = start_h * 60 + start_m;
    int stop_mins = stop_h * 60 + stop_m;

    if (start_mins <= stop_mins)
        return cur_mins >= start_mins && cur_mins < stop_mins;
    else
        return cur_mins >= start_mins || cur_mins < stop_mins;
}

/* =========================================================================
 * Command execution
 * ========================================================================= */

static int execute_command(const char *command, char *output, size_t output_size) {
    if (output) output[0] = '\0';
    log_message(LOG_DEBUG, "Exec: %s", command);

    FILE *fp = popen(command, "r");
    if (!fp) {
        log_message(LOG_ERR, "popen failed: %s", command);
        return -1;
    }

    if (output && output_size > 0) {
        if (fgets(output, output_size, fp) != NULL) {
            size_t len = strlen(output);
            if (len > 0 && output[len - 1] == '\n')
                output[len - 1] = '\0';
        }
    }

    int status = pclose(fp);
    if (status != 0) {
        log_message(LOG_DEBUG, "Command returned %d: %s", status, command);
        return -1;
    }
    return 0;
}

/* =========================================================================
 * Mode application
 * ========================================================================= */

static int apply_mode(daynight_mode_t new_mode) {
    char command[MAX_COMMAND_LEN];
    const char *arg = (new_mode == MODE_DAY) ? "day" : "night";
    const char *label = (new_mode == MODE_DAY) ? "DAY" : "NIGHT";

    log_message(LOG_INFO, "Applying %s mode via %s", label, g_config.script_path);

    snprintf(command, sizeof(command), "%s %s", g_config.script_path, arg);
    if (execute_command(command, NULL, 0) != 0) {
        log_message(LOG_ERR, "Failed to execute: %s", command);
        return -1;
    }

    write_mode_file(new_mode);
    log_message(LOG_INFO, "%s mode applied successfully", label);
    return 0;
}

/* =========================================================================
 * State file writers
 * ========================================================================= */

static void ensure_run_dir(void) {
    if (mkdir(RUN_DIR, 0755) != 0 && errno != EEXIST) {
        log_message(LOG_WARNING, "Cannot create %s: %s", RUN_DIR, strerror(errno));
    }
}

static void write_mode_file(daynight_mode_t mode) {
    ensure_run_dir();
    const char *str = (mode == MODE_DAY) ? "day" : "night";
    FILE *fp = fopen(MODE_FILE, "w");
    if (fp) { fprintf(fp, "%s\n", str); fclose(fp); }
}

static void write_brightness_file(int pct) {
    ensure_run_dir();
    static int last_pct = -999;
    if (pct == last_pct) return;
    last_pct = pct;

    FILE *fp = fopen(BRIGHTNESS_FILE, "w");
    if (fp) { fprintf(fp, "%d\n", pct); fclose(fp); }
}

static void write_sensors_json(const sensor_sample_t *s) {
    ensure_run_dir();
    /* Dedup: skip if same second and same brightness */
    static int64_t last_time = 0;
    static int last_pct = -1;
    if (s->time_now == last_time && s->brightness_pct == last_pct)
        return;
    last_time = s->time_now;
    last_pct = s->brightness_pct;

    FILE *fp = fopen(SENSORS_FILE, "w");
    if (!fp) return;
    /* Single fprintf to minimise syscalls */
    fprintf(fp,
        "{\"time_now\":%lld,\"platform\":\"%s\",\"ev_log2\":%d,"
        "\"ev_us\":%d,\"total_gain\":%d,\"gain_log2\":%d,"
        "\"integration_time\":%d,\"max_integration_time\":%d,"
        "\"analog_gain\":%d,\"max_analog_gain\":%d,\"digital_gain\":%d,"
        "\"isp_digital_gain\":%d,\"max_isp_digital_gain\":%d,"
        "\"wb_rgain\":%d,\"wb_bgain\":%d,\"wb_color_temp\":%d,"
        "\"daynight_brightness\":%d,"
        "\"primary_signal\":%d,\"night_threshold\":%d,"
        "\"day_threshold\":%d,\"mode\":\"%s\","
        "\"isp_mode\":\"%s\"}\n",
        (long long)s->time_now, s->platform,
        s->ev_log2, s->ev_us, s->total_gain, s->gain_log2,
        s->integration_time, s->max_integration_time,
        s->analog_gain, s->max_analog_gain,
        s->digital_gain, s->isp_digital_gain, s->max_isp_digital_gain,
        s->wb_rgain, s->wb_bgain, s->wb_color_temp,
        s->brightness_pct,
        s->primary_signal, s->night_threshold, s->day_threshold,
        s->daynight_mode, s->isp_mode);
    fclose(fp);
}

static void write_value_file(const sensor_sample_t *s, daynight_mode_t mode) {
    ensure_run_dir();
    static int last_bright = -1;
    static int last_signal = -1;
    static int last_tg = -1;
    static daynight_mode_t last_mode = MODE_UNKNOWN;
    if (s->brightness_pct == last_bright && s->primary_signal == last_signal &&
        s->total_gain == last_tg && mode == last_mode)
        return;
    last_bright = s->brightness_pct;
    last_signal = s->primary_signal;
    last_tg = s->total_gain;
    last_mode = mode;

    const char *mode_str = (mode == MODE_DAY) ? "day" :
                           (mode == MODE_NIGHT) ? "night" : "unknown";
    FILE *fp = fopen(VALUE_FILE, "w");
    if (fp) {
        fprintf(fp, "%d %d %d %s\n", s->brightness_pct, s->primary_signal,
                s->total_gain, mode_str);
        fclose(fp);
    }
}

static void write_history_json(void) {
    ensure_run_dir();
    FILE *fp = fopen(HISTORY_FILE, "w");
    if (!fp) return;

    fprintf(fp, "[");
    int total = g_history.count;
    for (int i = 0; i < total; i++) {
        int idx = (g_history.head - total + i + HISTORY_MAX_ENTRIES) % HISTORY_MAX_ENTRIES;
        const sensor_sample_t *s = &g_history.samples[idx];
        if (i > 0) fprintf(fp, ",");
        fprintf(fp, "{");
        fprintf(fp, "\"time_now\":%lld", (long long)s->time_now);
        fprintf(fp, ",\"ev_log2\":%d", s->ev_log2);
        fprintf(fp, ",\"analog_gain\":%d", s->analog_gain);
        fprintf(fp, ",\"isp_digital_gain\":%d", s->isp_digital_gain);
        fprintf(fp, ",\"wb_rgain\":%d", s->wb_rgain);
        fprintf(fp, ",\"wb_bgain\":%d", s->wb_bgain);
        fprintf(fp, ",\"wb_color_temp\":%d", s->wb_color_temp);
        fprintf(fp, ",\"daynight_brightness\":%d", s->brightness_pct);
        fprintf(fp, ",\"primary_signal\":%d", s->primary_signal);
        fprintf(fp, ",\"night_threshold\":%d", s->night_threshold);
        fprintf(fp, ",\"day_threshold\":%d", s->day_threshold);
        fprintf(fp, ",\"daynight_mode\":\"%s\"", s->daynight_mode);
        fprintf(fp, ",\"isp_mode\":\"%s\"", s->isp_mode);
        fprintf(fp, "}");
    }
    fprintf(fp, "]\n");
    fclose(fp);
}

static void write_state_files(const sensor_sample_t *s, daynight_mode_t mode) {
    write_brightness_file(s->brightness_pct);
    write_sensors_json(s);
    write_value_file(s, mode);
}

/* =========================================================================
 * History ring buffer
 * ========================================================================= */

static void history_push(const sensor_sample_t *s) {
    g_history.samples[g_history.head] = *s;
    g_history.head = (g_history.head + 1) % HISTORY_MAX_ENTRIES;
    if (g_history.count < HISTORY_MAX_ENTRIES)
        g_history.count++;
}

/* =========================================================================
 * PID file
 * ========================================================================= */

static int create_pid_file(void) {
    FILE *fp = fopen(g_config.pid_file, "w");
    if (!fp) {
        log_message(LOG_ERR, "Cannot create PID file %s: %s",
                    g_config.pid_file, strerror(errno));
        return -1;
    }
    fprintf(fp, "%d\n", getpid());
    fclose(fp);
    return 0;
}

static void remove_pid_file(void) {
    unlink(g_config.pid_file);
}

/* =========================================================================
 * Daemonize
 * ========================================================================= */

static void daemonize(void) {
    pid_t pid = fork();
    if (pid < 0) { log_message(LOG_ERR, "fork failed"); exit(EXIT_FAILURE); }
    if (pid > 0) exit(EXIT_SUCCESS);
    if (setsid() < 0) { log_message(LOG_ERR, "setsid failed"); exit(EXIT_FAILURE); }
    pid = fork();
    if (pid < 0) { log_message(LOG_ERR, "fork2 failed"); exit(EXIT_FAILURE); }
    if (pid > 0) exit(EXIT_SUCCESS);
    chdir("/");
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);
    open("/dev/null", O_RDONLY);
    open("/dev/null", O_WRONLY);
    open("/dev/null", O_WRONLY);
}

/* =========================================================================
 * Main loop
 * ========================================================================= */

static int main_loop(void) {
    int i;

    /* Determine platform signal on first parse */
    sensor_sample_t probe;
    g_state.use_total_gain = false;
    if (parse_isp(&probe) == 0 && probe.total_gain > 0) {
        g_state.use_total_gain = true;
    }

    log_message(LOG_INFO, "Starting main loop (platform=%s, signal=%s)",
                g_state.use_total_gain ? "T20" : "T31",
                g_state.use_total_gain ? "total_gain" : "ev_log2");

    g_state.running = true;
    g_state.current_mode = MODE_UNKNOWN;
    g_state.brightness_index = 0;
    g_state.night_count = 0;
    g_state.day_count = 0;
    g_state.initial_mode_set = false;
    g_state.anti_flap_cooldown = 0;
    g_state.initial_night_confirm = 0;
    g_state.initial_day_confirm = 0;
    g_state.initial_fallback_countdown = g_config.night_count_threshold * 3;

    for (i = 0; i < BRIGHTNESS_SAMPLES; i++)
        g_state.brightness_history[i] = 50.0f;

    const int anti_flap_iterations = 30;

    /* Log suppression */
    int last_primary_d10 = -1;
    int last_bright_pct = -1;
    daynight_mode_t last_logged_mode = MODE_UNKNOWN;
    int log_counter = 0;

    while (g_state.running && !g_terminate_flag) {
        /* Handle signals */
        if (g_reload_flag) {
            g_reload_flag = 0;
            load_force_mode_from_config();
        }
        if (g_force_day_flag) {
            g_force_day_flag = 0;
            log_message(LOG_INFO, "Signal: force DAY");
            if (g_state.current_mode != MODE_DAY) {
                apply_mode(MODE_DAY);
                g_state.current_mode = MODE_DAY;
                g_state.night_count = 0;
                g_state.day_count = 0;
                g_state.anti_flap_cooldown = anti_flap_iterations / 2;
                g_state.initial_mode_set = true;
            }
        }
        if (g_force_night_flag) {
            g_force_night_flag = 0;
            log_message(LOG_INFO, "Signal: force NIGHT");
            if (g_state.current_mode != MODE_NIGHT) {
                apply_mode(MODE_NIGHT);
                g_state.current_mode = MODE_NIGHT;
                g_state.night_count = 0;
                g_state.day_count = 0;
                g_state.anti_flap_cooldown = anti_flap_iterations / 2;
                g_state.initial_mode_set = true;
            }
        }

        /* Read sensor data */
        sensor_sample_t s;
        if (parse_isp(&s) != 0) {
            log_message(LOG_ERR, "Failed to read ISP data");
            usleep(g_config.sample_interval_ms * 1000);
            continue;
        }

        /* Re-detect platform if it changed (shouldn't, but be safe) */
        if (s.total_gain > 0 && !g_state.use_total_gain) {
            g_state.use_total_gain = true;
            log_message(LOG_INFO, "Switched to total_gain signal (T20 detected)");
        }

        /* Compute brightness */
        s.brightness_pct = compute_brightness_pct(&s);

        /* Set active thresholds based on platform */
        if (g_state.use_total_gain) {
            s.night_threshold = g_config.tg_night_threshold;
            s.day_threshold   = g_config.tg_day_threshold;
        } else {
            s.night_threshold = g_config.ev_night_threshold;
            s.day_threshold   = g_config.ev_day_threshold;
        }

        /* Update brightness history */
        g_state.brightness_history[g_state.brightness_index] = (float)s.brightness_pct;
        g_state.brightness_index = (g_state.brightness_index + 1) % BRIGHTNESS_SAMPLES;

        /* Compute average brightness */
        float avg_brightness = 0.0f;
        int sample_count = 0;
        for (i = 0; i < BRIGHTNESS_SAMPLES; i++) {
            if (g_state.brightness_history[i] >= 0) {
                avg_brightness += g_state.brightness_history[i];
                sample_count++;
            }
        }
        if (sample_count > 0) avg_brightness /= (float)sample_count;

        bool within_schedule = is_within_schedule();

        /* --- Initial mode detection --- */
        if (!g_state.initial_mode_set) {
            daynight_mode_t initial = MODE_UNKNOWN;
            int sig = s.primary_signal;
            int night_thr = s.night_threshold;
            int day_thr = s.day_threshold;

            if (sig > night_thr) {
                initial = MODE_NIGHT;
            } else if (sig > 0 && sig < day_thr) {
                initial = MODE_DAY;
            }

            bool commit = false;
            if (initial == MODE_NIGHT) {
                g_state.initial_day_confirm = 0;
                commit = (++g_state.initial_night_confirm >= 2);
            } else if (initial == MODE_DAY) {
                g_state.initial_night_confirm = 0;
                commit = (++g_state.initial_day_confirm >= 2);
            } else {
                if (g_state.initial_night_confirm > 0) --g_state.initial_night_confirm;
                if (g_state.initial_day_confirm > 0) --g_state.initial_day_confirm;
                --g_state.initial_fallback_countdown;
            }

            if (commit) {
                apply_mode(initial);
                g_state.current_mode = initial;
                g_state.initial_mode_set = true;
                if (initial == MODE_NIGHT)
                    g_state.anti_flap_cooldown = anti_flap_iterations / 2;

                log_message(LOG_INFO, "Initial mode: %s (sig=%d, thr_day=%d thr_night=%d)",
                            (initial == MODE_DAY) ? "DAY" : "NIGHT",
                            sig, day_thr, night_thr);
            } else if (g_state.initial_fallback_countdown <= 0) {
                apply_mode(MODE_NIGHT);
                g_state.current_mode = MODE_NIGHT;
                g_state.anti_flap_cooldown = anti_flap_iterations / 2;
                g_state.initial_mode_set = true;
                log_message(LOG_WARNING, "Initial detection timeout, defaulting to NIGHT");
            }

            strncpy(s.daynight_mode,
                    (g_state.current_mode == MODE_DAY) ? "day" :
                    (g_state.current_mode == MODE_NIGHT) ? "night" : "unknown",
                    sizeof(s.daynight_mode) - 1);

            history_push(&s);
            write_state_files(&s, g_state.current_mode);
            if (g_history.count % 60 == 0) write_history_json();

            usleep(g_config.sample_interval_ms * 1000);
            continue;
        }

        /* --- Force mode from config --- */
        static char last_force_mode[16] = "";
        bool was_forced = (last_force_mode[0] != '\0');
        bool now_forced = (g_config.force_mode[0] != '\0');

        if (now_forced) {
            daynight_mode_t forced = MODE_UNKNOWN;
            if (strcmp(g_config.force_mode, "day") == 0)
                forced = MODE_DAY;
            else if (strcmp(g_config.force_mode, "night") == 0)
                forced = MODE_NIGHT;

            if (forced != MODE_UNKNOWN && forced != g_state.current_mode) {
                log_message(LOG_INFO, "Force mode from config: %s", g_config.force_mode);
                apply_mode(forced);
                g_state.current_mode = forced;
                g_state.night_count = 0;
                g_state.day_count = 0;
                g_state.anti_flap_cooldown = anti_flap_iterations / 2;
            }
        } else if (was_forced && !now_forced) {
            /* Force mode cleared — re-enter photosensing */
            log_message(LOG_INFO, "Force mode cleared, resuming photosensing");
            g_state.initial_mode_set = false;
            g_state.night_count = 0;
            g_state.day_count = 0;
            g_state.initial_night_confirm = 0;
            g_state.initial_day_confirm = 0;
            g_state.initial_fallback_countdown = g_config.night_count_threshold * 3;
        }
        strncpy(last_force_mode, g_config.force_mode, sizeof(last_force_mode) - 1);

        /* --- Main hysteresis --- */
        int sig = s.primary_signal;
        int night_thr = s.night_threshold;
        int day_thr = s.day_threshold;
        daynight_mode_t target_mode = g_state.current_mode;

        if (g_state.current_mode == MODE_DAY) {
            if (sig > night_thr) {
                if (++g_state.night_count >= g_config.night_count_threshold)
                    target_mode = MODE_NIGHT;
            } else {
                if (g_state.night_count > 0) --g_state.night_count;
            }
        } else if (g_state.current_mode == MODE_NIGHT) {
            if (sig > 0 && sig < day_thr) {
                if (++g_state.day_count >= g_config.day_count_threshold)
                    target_mode = MODE_DAY;
            } else {
                if (g_state.day_count > 0) --g_state.day_count;
            }
        } else {
            if (sig > night_thr)
                target_mode = MODE_NIGHT;
            else if (sig > 0 && sig < day_thr)
                target_mode = MODE_DAY;
        }

        /* Apply mode change */
        if (target_mode != g_state.current_mode && target_mode != MODE_UNKNOWN) {
            struct timeval now, diff;
            gettimeofday(&now, NULL);
            if (g_state.current_mode != MODE_UNKNOWN) {
                timersub(&now, &g_state.last_transition, &diff);
                if (diff.tv_sec < g_config.transition_delay_s) {
                    log_message(LOG_DEBUG, "Transition delay: %ld/%ds",
                                (long)diff.tv_sec, g_config.transition_delay_s);
                    g_state.night_count = 0;
                    g_state.day_count = 0;
                    target_mode = g_state.current_mode;
                }
            }

            if (target_mode != g_state.current_mode) {
                if (!g_config.enabled) {
                    log_message(LOG_DEBUG, "Skip: photosensing disabled");
                } else if (!within_schedule) {
                    log_message(LOG_DEBUG, "Skip: outside schedule");
                } else if (g_state.anti_flap_cooldown > 0) {
                    log_message(LOG_DEBUG, "Skip: anti-flap cooldown %d",
                                g_state.anti_flap_cooldown);
                    g_state.anti_flap_cooldown--;
                } else {
                    log_message(LOG_INFO, "Switch: %s -> %s (sig=%d, nCnt=%d, dCnt=%d)",
                                (g_state.current_mode == MODE_DAY) ? "DAY" : "NIGHT",
                                (target_mode == MODE_DAY) ? "DAY" : "NIGHT",
                                sig, g_state.night_count, g_state.day_count);
                    apply_mode(target_mode);
                    g_state.current_mode = target_mode;
                    gettimeofday(&g_state.last_transition, NULL);
                    g_state.night_count = 0;
                    g_state.day_count = 0;
                    g_state.anti_flap_cooldown = anti_flap_iterations;
                }
            }
        } else {
            if (g_state.anti_flap_cooldown > 0)
                g_state.anti_flap_cooldown--;
        }

        /* Update sample with current mode */
        strncpy(s.daynight_mode,
                (g_state.current_mode == MODE_DAY) ? "day" :
                (g_state.current_mode == MODE_NIGHT) ? "night" : "unknown",
                sizeof(s.daynight_mode) - 1);

        /* Periodic logging */
        int p10 = s.primary_signal / (g_state.use_total_gain ? 100 : 10000);
        if (p10 != last_primary_d10 || s.brightness_pct != last_bright_pct ||
            g_state.current_mode != last_logged_mode || ++log_counter >= 30) {
            log_counter = 0;
            log_message(LOG_DEBUG, "%s=%d bright=%d%% mode=%s sched=%s nCnt=%d dCnt=%d",
                        g_state.use_total_gain ? "tg" : "evlog2",
                        s.primary_signal, s.brightness_pct, s.daynight_mode,
                        within_schedule ? "in" : "out",
                        g_state.night_count, g_state.day_count);
            last_primary_d10 = p10;
            last_bright_pct = s.brightness_pct;
            last_logged_mode = g_state.current_mode;
        }

        history_push(&s);
        write_state_files(&s, g_state.current_mode);
        if (g_history.count % 60 == 0) write_history_json();

        usleep(g_config.sample_interval_ms * 1000);
    }

    log_message(LOG_INFO, "Main loop terminated");
    return 0;
}

/* =========================================================================
 * Usage
 * ========================================================================= */

static void print_usage(const char *prog) {
    printf("Usage: %s [OPTIONS]\n", prog);
    printf("\nOptions:\n");
    printf("  -c, --config FILE    Config file (default: %s)\n", DEFAULT_CONFIG_FILE);
    printf("  -f, --foreground     Run in foreground\n");
    printf("  -p, --pid-file FILE  PID file (default: %s)\n", DEFAULT_PID_FILE);
    printf("  -v, --verbose        Increase verbosity\n");
    printf("  -h, --help           Show this help\n");
    printf("  -V, --version        Show version\n");
    printf("\nSignals:\n");
    printf("  SIGUSR1              Force day mode\n");
    printf("  SIGUSR2              Force night mode\n");
    printf("  SIGHUP               Reload configuration\n");
    printf("  SIGTERM/SIGINT       Graceful shutdown\n");
}

/* =========================================================================
 * Main
 * ========================================================================= */

int main(int argc, char *argv[]) {
    int opt;
    const char *config_file = DEFAULT_CONFIG_FILE;
    bool foreground = false;

    static struct option long_options[] = {
        {"config",     required_argument, 0, 'c'},
        {"foreground", no_argument,       0, 'f'},
        {"pid-file",   required_argument, 0, 'p'},
        {"verbose",    no_argument,       0, 'v'},
        {"help",       no_argument,       0, 'h'},
        {"version",    no_argument,       0, 'V'},
        {0, 0, 0, 0}
    };

    memset(&g_config, 0, sizeof(g_config));
    memset(&g_state, 0, sizeof(g_state));
    memset(&g_history, 0, sizeof(g_history));
    g_state.current_mode = MODE_UNKNOWN;

    while ((opt = getopt_long(argc, argv, "c:fp:vhV", long_options, NULL)) != -1) {
        switch (opt) {
            case 'c': config_file = optarg; break;
            case 'f': foreground = true; break;
            case 'p':
                strncpy(g_config.pid_file, optarg, sizeof(g_config.pid_file) - 1);
                break;
            case 'v':
                if (g_config.log_level < 5) g_config.log_level++;
                break;
            case 'h': print_usage(argv[0]); exit(EXIT_SUCCESS);
            case 'V':
                printf("daynightd v2.0.0 for Thingino firmware\n");
                exit(EXIT_SUCCESS);
            default: print_usage(argv[0]); exit(EXIT_FAILURE);
        }
    }

    if (read_config(config_file) != 0) {
        fprintf(stderr, "Failed to load configuration\n");
        exit(EXIT_FAILURE);
    }

    if (foreground) {
        g_config.daemon_mode = false;
        g_config.enable_syslog = false;
    }

    if (g_config.enable_syslog)
        openlog("daynightd", LOG_PID | LOG_CONS, LOG_DAEMON);

    log_message(LOG_INFO, "Starting daynightd v2.0.0 [%s]",
                log_level_name(g_config.log_level));

    ensure_run_dir();

    /* PID file exclusivity is handled by start-stop-daemon */

    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    signal(SIGUSR1, signal_handler);
    signal(SIGUSR2, signal_handler);
    signal(SIGHUP, signal_handler);
    signal(SIGPIPE, SIG_IGN);

    if (g_config.daemon_mode) daemonize();

    if (create_pid_file() != 0) {
        log_message(LOG_ERR, "Cannot create PID file");
        exit(EXIT_FAILURE);
    }
    atexit(remove_pid_file);

    int result = main_loop();

    log_message(LOG_INFO, "Shutting down daynightd");
    unlink(VALUE_FILE);
    unlink(SENSORS_FILE);

    if (g_config.enable_syslog) closelog();
    return result;
}
