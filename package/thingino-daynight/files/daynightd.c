/*
 * daynightd.c - Automatic Day/Night Mode Switching Daemon for Thingino
 *
 * Copyright (C) 2025 Thingino Project
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
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

/* Configuration defaults optimized for Thingino/Ingenic systems */
#define DEFAULT_DEVICE "/dev/isp-m0"
#define DEFAULT_CONFIG_FILE "/etc/daynightd.json"
#define DEFAULT_PID_FILE "/run/daynightd.pid"
#define DEFAULT_THRESHOLD_LOW 30.0f
#define DEFAULT_THRESHOLD_HIGH 70.0f
#define DEFAULT_SAMPLE_INTERVAL_MS 500
#define DEFAULT_TRANSITION_DELAY_S 5
#define DEFAULT_HYSTERESIS_FACTOR 0.1f

/* Thingino-specific paths and commands */
#define THINGINO_DAYNIGHT_SCRIPT "/sbin/daynight"

/* Ingenic ISP proc filesystem paths */
#define ISP_M0_PATH "/proc/jz/isp/isp-m0"
#define ISP_FS_PATH "/proc/jz/isp/isp-fs"

/* Test paths for development */
#ifdef DEBUG
#define TEST_ISP_M0_PATH "/tmp/test-isp-m0"
#else
#define TEST_ISP_M0_PATH ISP_M0_PATH
#endif

/* Thingino system integration */
#define BRIGHTNESS_SAMPLES 10
#define MAX_COMMAND_LEN 256
#define MAX_OUTPUT_LEN 1024

/* Day/Night modes */
typedef enum {
    MODE_DAY = 0,
    MODE_NIGHT = 1,
    MODE_UNKNOWN = -1
} daynight_mode_t;

/* Configuration structure */
typedef struct {
    char device_path[256];
    char config_file[256];
    char pid_file[256];
    float threshold_low;
    float threshold_high;
    int sample_interval_ms;
    int transition_delay_s;
    float hysteresis_factor;

    bool enable_syslog;
    bool daemon_mode;
    int log_level;  /* 0=FATAL,1=ERROR,2=WARN,3=INFO,4=DEBUG,5=TRACE */
} daynight_config_t;

/* Runtime state for Thingino system */
typedef struct {
    daynight_mode_t current_mode;
    daynight_mode_t pending_mode;
    struct timeval last_transition;
    float brightness_history[BRIGHTNESS_SAMPLES];
    int brightness_index;
    bool running;

} daynight_state_t;

/* Global variables */
static daynight_config_t g_config;
static daynight_state_t g_state;
static volatile sig_atomic_t g_terminate_flag = 0;

/* Function prototypes */
static void signal_handler(int sig);
static int read_config(const char *config_file);
static int init_thingino_system(void);
static int execute_command(const char *command, char *output, size_t output_size);
static float calculate_brightness_from_isp(void);
static float calculate_brightness_thingino(void);
static int trigger_mode_change(daynight_mode_t new_mode, float level_value, float threshold_value, bool is_forced);
static int apply_day_settings_thingino(void);
static int apply_night_settings_thingino(void);
static void log_message(int level, const char *format, ...);
static int create_pid_file(void);
static void remove_pid_file(void);
static void daemonize(void);
static int parse_debug_level_string(const char *s);
static const char* log_level_name(int level);

static int main_loop(void);
static int write_brightness_value(float brightness, float avg_brightness, daynight_mode_t mode);

/*
 * Signal handler for graceful shutdown
 */
static void signal_handler(int sig) {
    switch (sig) {
        case SIGTERM:
        case SIGINT:
            g_terminate_flag = 1;
            g_state.running = false;
            break;
        case SIGUSR1:
            /* Force day mode */
            g_state.pending_mode = MODE_DAY;
            break;
        case SIGUSR2:
            /* Force night mode */
            g_state.pending_mode = MODE_NIGHT;
            break;
        case SIGHUP:
            /* Reload configuration */
            read_config(g_config.config_file);

            break;
    }
}
/* Parse case-insensitive debug level string to numeric 0..5; returns -1 if invalid */
static int parse_debug_level_string(const char *s) {
    if (!s) return -1;
    /* Trim leading/trailing whitespace */
    const char *start = s; while (*start && isspace((unsigned char)*start)) start++;
    const char *end = start + strlen(start);
    while (end > start && isspace((unsigned char)end[-1])) end--;
    size_t len = (size_t)(end - start);
    if (len == 0 || len > 16) return -1;
    char buf[17];
    for (size_t i = 0; i < len; ++i) buf[i] = (char)toupper((unsigned char)start[i]);
    buf[len] = '\0';
    if (!strcmp(buf, "FATAL")) return 0;
    if (!strcmp(buf, "ERROR")) return 1;
    if (!strcmp(buf, "WARN") || !strcmp(buf, "WARNING")) return 2;
    if (!strcmp(buf, "INFO")) return 3;
    if (!strcmp(buf, "DEBUG")) return 4;
    if (!strcmp(buf, "TRACE")) return 5;
    return -1;
}

static const char* log_level_name(int level) {
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


/*
 * Load configuration from JSON file with safe defaults
 */
static int read_config(const char *config_file) {
    int result = 0;

    /* Set defaults */
    strncpy(g_config.device_path, DEFAULT_DEVICE, sizeof(g_config.device_path) - 1);
    strncpy(g_config.config_file, DEFAULT_CONFIG_FILE, sizeof(g_config.config_file) - 1);
    strncpy(g_config.pid_file, DEFAULT_PID_FILE, sizeof(g_config.pid_file) - 1);
    g_config.threshold_low = DEFAULT_THRESHOLD_LOW;
    g_config.threshold_high = DEFAULT_THRESHOLD_HIGH;
    g_config.sample_interval_ms = DEFAULT_SAMPLE_INTERVAL_MS;
    g_config.transition_delay_s = DEFAULT_TRANSITION_DELAY_S;
    g_config.hysteresis_factor = DEFAULT_HYSTERESIS_FACTOR;

    g_config.enable_syslog = true;
    g_config.daemon_mode = true;
    g_config.log_level = 3; /* default INFO */

    /* Load JSON using jct */
    JsonValue *root = load_config(config_file);
    if (!root) {
        log_message(LOG_WARNING, "Config file %s not found or invalid, using defaults", config_file);
        return 0;
    }

    /* Extract configuration values from nested JSON structure */

    /* Device path */
    JsonValue *v;
    v = get_nested_item(root, "device_path");
    if (v && v->type == JSON_STRING && v->value.string) {
        strncpy(g_config.device_path, v->value.string, sizeof(g_config.device_path) - 1);
        g_config.device_path[sizeof(g_config.device_path) - 1] = '\0';
    }

    /* Brightness thresholds */
    v = get_nested_item(root, "brightness_thresholds.threshold_low");
    if (v && v->type == JSON_NUMBER) {
        g_config.threshold_low = (float)v->value.number;
    }
    v = get_nested_item(root, "brightness_thresholds.threshold_high");
    if (v && v->type == JSON_NUMBER) {
        g_config.threshold_high = (float)v->value.number;
    }
    v = get_nested_item(root, "brightness_thresholds.hysteresis_factor");
    if (v && v->type == JSON_NUMBER) {
        g_config.hysteresis_factor = (float)v->value.number;
    }

    /* Timing configuration */
    v = get_nested_item(root, "timing.sample_interval_ms");
    if (v && v->type == JSON_NUMBER) {
        g_config.sample_interval_ms = (int)v->value.number;
    }
    v = get_nested_item(root, "timing.transition_delay_s");
    if (v && v->type == JSON_NUMBER) {
        g_config.transition_delay_s = (int)v->value.number;
    }

    /* System configuration */
    v = get_nested_item(root, "system.enable_syslog");
    if (v && v->type == JSON_BOOL) {
        g_config.enable_syslog = v->value.boolean;
    }
    v = get_nested_item(root, "system.daemon_mode");
    if (v && v->type == JSON_BOOL) {
        g_config.daemon_mode = v->value.boolean;
    }

    /* Log level from string debug_level only; default INFO when absent/invalid */
    v = get_nested_item(root, "system.debug_level");
    if (v) {
        if (v->type == JSON_STRING && v->value.string) {
            int lvl = parse_debug_level_string(v->value.string);
            if (lvl >= 0) {
                g_config.log_level = lvl;
            } else {
                static int warned_invalid = 0;
                if (!warned_invalid) {
                    log_message(LOG_WARNING, "Invalid debug_level '%s' in %s; defaulting to INFO", v->value.string, g_config.config_file);
                    warned_invalid = 1;
                }
                g_config.log_level = 3;
            }
        } else {
            static int warned_type = 0;
            if (!warned_type) {
                log_message(LOG_WARNING, "debug_level must be a string in %s; defaulting to INFO", g_config.config_file);
                warned_type = 1;
            }
            g_config.log_level = 3;
        }
    } else {
        g_config.log_level = 3; /* Absent -> default INFO */
    }

    v = get_nested_item(root, "system.pid_file");
    if (v && v->type == JSON_STRING && v->value.string) {
        strncpy(g_config.pid_file, v->value.string, sizeof(g_config.pid_file) - 1);
        g_config.pid_file[sizeof(g_config.pid_file) - 1] = '\0';
    }

    /* Cleanup */
    free_json_value(root);

    /* Validate configuration */
    if (g_config.threshold_low >= g_config.threshold_high) {
        log_message(LOG_ERR, "Invalid thresholds: low=%.1f >= high=%.1f",
                   g_config.threshold_low, g_config.threshold_high);
        return -1;
    }

    if (g_config.sample_interval_ms < 100 || g_config.sample_interval_ms > 60000) {
        log_message(LOG_WARNING, "Sample interval %d ms out of range, using default",
                   g_config.sample_interval_ms);
        g_config.sample_interval_ms = DEFAULT_SAMPLE_INTERVAL_MS;
    }

    log_message(LOG_INFO, "Configuration loaded: thresholds=%.1f/%.1f, interval=%dms",
               g_config.threshold_low, g_config.threshold_high, g_config.sample_interval_ms);

    return result;
}

/*
 * Initialize Thingino system integration
 */
static int init_thingino_system(void) {
    log_message(LOG_INFO, "Initializing Thingino system integration");

    /* Test basic system functionality */
    char output[MAX_OUTPUT_LEN];
    if (execute_command("echo 'System test'", output, sizeof(output)) != 0) {
        log_message(LOG_ERR, "Basic system command execution failed");
        return -1;
    }

    // Initialize IR cut filter
    execute_command("ircut off", NULL, 0);
    usleep(500000);
    execute_command("ircut on", NULL, 0);

    log_message(LOG_INFO, "Thingino system initialized successfully");
    return 0;
}

/*
 * Execute system command and capture output
 */
static int execute_command(const char *command, char *output, size_t output_size) {
    FILE *fp;
    int status;

    if (output) {
        output[0] = '\0';
    }

    log_message(LOG_DEBUG, "Executing command: %s", command);

    fp = popen(command, "r");
    if (!fp) {
        log_message(LOG_ERR, "Failed to execute command: %s", command);
        return -1;
    }

    if (output && output_size > 0) {
        if (fgets(output, output_size, fp) != NULL) {
            /* Remove trailing newline */
            size_t len = strlen(output);
            if (len > 0 && output[len-1] == '\n') {
                output[len-1] = '\0';
            }
        }
    }

    status = pclose(fp);
    if (status != 0) {
        log_message(LOG_DEBUG, "Command failed with status: %d", status);
        return -1;
    }

    return 0;
}

/*
 * Calculate brightness from Ingenic ISP parameters
 * Uses direct ISP data for accurate brightness detection
 */
static float calculate_brightness_from_isp(void) {
    FILE *fp;
    char line[256];
    float brightness = -1.0f;

    /* ISP parameters for brightness calculation */
    int integration_time = -1;
    int max_integration_time = -1;
    int analog_gain = -1;
    int digital_gain = -1;
    int isp_digital_gain = -1;
    int ev_value = -1;
    int current_brightness = -1;
    char current_mode[32] = {0};

    fp = fopen(TEST_ISP_M0_PATH, "r");
    if (!fp) {
        log_message(LOG_DEBUG, "Cannot read ISP parameters from %s: %s", TEST_ISP_M0_PATH, strerror(errno));
        return -1.0f;
    }

    /* Parse ISP parameters */
    while (fgets(line, sizeof(line), fp)) {
        if (strstr(line, "ISP Runing Mode :")) {
            sscanf(line, "ISP Runing Mode : %31s", current_mode);
        } else if (strstr(line, "SENSOR Integration Time :")) {
            sscanf(line, "SENSOR Integration Time : %d lines", &integration_time);
        } else if (strstr(line, "SENSOR Max Integration Time :")) {
            sscanf(line, "SENSOR Max Integration Time : %d lines", &max_integration_time);
        } else if (strstr(line, "SENSOR analog gain :")) {
            sscanf(line, "SENSOR analog gain : %d", &analog_gain);
        } else if (strstr(line, "SENSOR digital gain :")) {
            sscanf(line, "SENSOR digital gain : %d", &digital_gain);
        } else if (strstr(line, "ISP digital gain :")) {
            sscanf(line, "ISP digital gain : %d", &isp_digital_gain);
        } else if (strstr(line, "ISP EV value:")) {
            sscanf(line, "ISP EV value: %d", &ev_value);
        } else if (strstr(line, "Brightness :")) {
            sscanf(line, "Brightness : %d", &current_brightness);
        }
    }

    fclose(fp);

    /* Calculate brightness based on ISP parameters */
    if (integration_time >= 0 && max_integration_time > 0) {
        /* Primary method: Use integration time ratio */
        float exposure_ratio = (float)integration_time / (float)max_integration_time;

        /* Lower integration time = brighter scene */
        brightness = (1.0f - exposure_ratio) * 100.0f;

        /* Adjust for gain - higher gain indicates darker scene */
        if (analog_gain >= 0) {
            float gain_factor = 1.0f + (analog_gain / 160.0f); /* Max gain is 160 */
            brightness = brightness / gain_factor;
        }

        if (isp_digital_gain > 0) {
            float digital_gain_factor = 1.0f + (isp_digital_gain / 80.0f); /* Max is 80 */
            brightness = brightness / digital_gain_factor;
        }

        /* Clamp to valid range */
        if (brightness < 0) brightness = 0;
        if (brightness > 100.0f) brightness = 100.0f;

        log_message(LOG_DEBUG, "ISP brightness: %.1f%% (int_time: %d/%d, gain: %d, mode: %s)",
                   brightness, integration_time, max_integration_time, analog_gain, current_mode);

    } else if (current_brightness >= 0) {
        /* Fallback: Use ISP brightness setting */
        brightness = ((float)current_brightness / 255.0f) * 100.0f;
        log_message(LOG_DEBUG, "ISP brightness from setting: %.1f%% (raw: %d)", brightness, current_brightness);

    } else if (strlen(current_mode) > 0) {
        /* Last resort: Use current mode */
        if (strcmp(current_mode, "Day") == 0) {
            brightness = 75.0f;
        } else if (strcmp(current_mode, "Night") == 0) {
            brightness = 25.0f;
        }
        log_message(LOG_DEBUG, "ISP brightness from mode: %.1f%% (mode: %s)", brightness, current_mode);
    }

    return brightness;
}

/*
 * Calculate brightness using Thingino-specific methods
 * This function uses multiple approaches to determine scene brightness
 */
static float calculate_brightness_thingino(void) {
    char output[MAX_OUTPUT_LEN];
    float brightness = -1.0f;

    /* Method 1: Try reading ISP parameters directly (most accurate) */
    brightness = calculate_brightness_from_isp();
    if (brightness >= 0) {
        /* Update brightness history for smoothing */
        g_state.brightness_history[g_state.brightness_index] = brightness;
        g_state.brightness_index = (g_state.brightness_index + 1) % BRIGHTNESS_SAMPLES;
        return brightness;
    }

    /* Method 2: Simple Thingino script fallback (if ISP unavailable) */
    if (brightness < 0) {
        if (execute_command(THINGINO_DAYNIGHT_SCRIPT " status", output, sizeof(output)) == 0) {
            if (strstr(output, "day") != NULL) {
                brightness = 80.0f;
            } else if (strstr(output, "night") != NULL) {
                brightness = 20.0f;
            }
            log_message(LOG_DEBUG, "Brightness from daynight script: %.1f%%", brightness);
        }
    }

    /* Method 3: Fallback - use time-based heuristic */
    if (brightness < 0) {
        time_t now = time(NULL);
        struct tm *tm_info = localtime(&now);
        int hour = tm_info->tm_hour;

        /* Simple time-based brightness estimation */
        if (hour >= 6 && hour <= 18) {
            brightness = 70.0f; /* Assume day time */
        } else {
            brightness = 25.0f; /* Assume night time */
        }

        log_message(LOG_DEBUG, "Using time-based brightness estimation: %.1f%% (hour: %d)",
                   brightness, hour);
    }

    /* Update brightness history for smoothing */
    if (brightness >= 0) {
        g_state.brightness_history[g_state.brightness_index] = brightness;
        g_state.brightness_index = (g_state.brightness_index + 1) % BRIGHTNESS_SAMPLES;

        log_message(LOG_DEBUG, "Calculated brightness: %.1f%%", brightness);
    }

    return brightness;
}

/*
 * Trigger mode change with hysteresis and transition delay
 */
static int trigger_mode_change(daynight_mode_t new_mode, float level_value, float threshold_value, bool is_forced) {
    struct timeval now, diff;

    if (new_mode == g_state.current_mode) {
        return 0;  /* No change needed */
    }

    gettimeofday(&now, NULL);

    /* Check transition delay */
    if (g_state.current_mode != MODE_UNKNOWN) {
        timersub(&now, &g_state.last_transition, &diff);
        if (diff.tv_sec < g_config.transition_delay_s) {
            log_message(LOG_DEBUG, "Transition delay not met, waiting...");
            return 0;
        }
    }

    if (is_forced) {
        log_message(LOG_INFO, "Mode change (forced): %s -> %s",
                   (g_state.current_mode == MODE_DAY) ? "DAY" :
                   (g_state.current_mode == MODE_NIGHT) ? "NIGHT" : "UNKNOWN",
                   (new_mode == MODE_DAY) ? "DAY" : "NIGHT");
    } else {
        log_message(LOG_INFO, "Mode change: %s -> %s (level=%.1f%%, threshold=%.1f%%)",
                   (g_state.current_mode == MODE_DAY) ? "DAY" :
                   (g_state.current_mode == MODE_NIGHT) ? "NIGHT" : "UNKNOWN",
                   (new_mode == MODE_DAY) ? "DAY" : "NIGHT",
                   level_value, threshold_value);
    }

    /* Apply mode-specific settings */
    int result = 0;
    if (new_mode == MODE_DAY) {
        result = apply_day_settings_thingino();
    } else {
        result = apply_night_settings_thingino();
    }

    if (result == 0) {
        g_state.current_mode = new_mode;
        g_state.last_transition = now;
    }

    return result;
}

/*
 * Apply day mode camera settings using Thingino daynight script
 */
static int apply_day_settings_thingino(void) {
    char command[MAX_COMMAND_LEN];

    log_message(LOG_DEBUG, "Applying day mode settings");

    snprintf(command, sizeof(command), "%s day", THINGINO_DAYNIGHT_SCRIPT);
    if (execute_command(command, NULL, 0) != 0) {
        log_message(LOG_ERR, "Failed to execute: %s", command);
        return -1;
    }

    log_message(LOG_DEBUG, "Day mode applied successfully");
    return 0;
}

/*
 * Apply night mode camera settings using Thingino daynight script
 */
static int apply_night_settings_thingino(void) {
    char command[MAX_COMMAND_LEN];

    log_message(LOG_DEBUG, "Applying night mode settings");

    snprintf(command, sizeof(command), "%s night", THINGINO_DAYNIGHT_SCRIPT);
    if (execute_command(command, NULL, 0) != 0) {
        log_message(LOG_ERR, "Failed to execute: %s", command);
        return -1;
    }

    log_message(LOG_DEBUG, "Night mode applied successfully");
    return 0;
}

/*
 * Logging function with syslog support
 */
static void log_message(int level, const char *format, ...) {
    /* Map syslog levels to numeric severity: 0=FATAL,1=ERROR,2=WARN,3=INFO,4=DEBUG,5=TRACE */
    int msg_level_num;
    switch (level) {
        case LOG_EMERG:
        case LOG_ALERT:
        case LOG_CRIT:
            msg_level_num = 0; /* FATAL */
            break;
        case LOG_ERR:
            msg_level_num = 1; /* ERROR */
            break;
        case LOG_WARNING:
            msg_level_num = 2; /* WARN */
            break;
        case LOG_INFO:
            msg_level_num = 3; /* INFO */
            break;
        case LOG_DEBUG:
            msg_level_num = 4; /* DEBUG (TRACE would be 5) */
            break;
        default:
            msg_level_num = 4; /* Treat unknown as DEBUG */
            break;
    }

    /* Drop messages more verbose than configured threshold */
    if (msg_level_num > g_config.log_level) {
        return;
    }

    /* Human-readable label for both console and syslog */
    const char *level_str;
    switch (level) {
        case LOG_EMERG:
        case LOG_ALERT:
        case LOG_CRIT: level_str = "FATAL"; break;
        case LOG_ERR: level_str = "ERROR"; break;
        case LOG_WARNING: level_str = "WARN"; break;
        case LOG_INFO: level_str = "INFO"; break;
        case LOG_DEBUG: level_str = (g_config.log_level >= 5) ? "TRACE" : "DEBUG"; break;
        default: level_str = "UNKNOWN"; break;
    }

    va_list args;
    char buffer[512];

    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);

    if (g_config.enable_syslog) {
        syslog(level, "[%s] %s", level_str, buffer);
    }

    if (!g_config.daemon_mode || g_config.log_level > 0) {
        struct timeval tv;
        gettimeofday(&tv, NULL);
        fprintf(stderr, "[%lld.%03lld] %s: %s\n",
                (long long)tv.tv_sec, (long long)(tv.tv_usec / 1000), level_str, buffer);
    }
}

/*
 * Create PID file for daemon management
 */
static int create_pid_file(void) {
    FILE *fp;

    fp = fopen(g_config.pid_file, "w");
    if (!fp) {
        log_message(LOG_ERR, "Failed to create PID file %s: %s",
                   g_config.pid_file, strerror(errno));
        return -1;
    }

    fprintf(fp, "%d\n", getpid());
    fclose(fp);

    return 0;
}

/*
 * Remove PID file on exit
 */
static void remove_pid_file(void) {
    unlink(g_config.pid_file);
}

/*
 * Daemonize process
 */
static void daemonize(void) {
    pid_t pid;

    /* Fork off the parent process */
    pid = fork();
    if (pid < 0) {
        log_message(LOG_ERR, "Fork failed: %s", strerror(errno));
        exit(EXIT_FAILURE);
    }

    /* Exit parent process */
    if (pid > 0) {
        exit(EXIT_SUCCESS);
    }

    /* Create new session */
    if (setsid() < 0) {
        log_message(LOG_ERR, "setsid failed: %s", strerror(errno));
        exit(EXIT_FAILURE);
    }

    /* Fork again to prevent acquiring controlling terminal */
    pid = fork();
    if (pid < 0) {
        log_message(LOG_ERR, "Second fork failed: %s", strerror(errno));
        exit(EXIT_FAILURE);
    }

    if (pid > 0) {
        exit(EXIT_SUCCESS);
    }

    /* Change working directory to root */
    if (chdir("/") < 0) {
        log_message(LOG_ERR, "chdir failed: %s", strerror(errno));
        exit(EXIT_FAILURE);
    }

    /* Close standard file descriptors */
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);

    /* Redirect to /dev/null */
    open("/dev/null", O_RDONLY);  /* stdin */
    open("/dev/null", O_WRONLY);  /* stdout */
    open("/dev/null", O_WRONLY);  /* stderr */
}

/*
 * Write current brightness value to /run/daynight/value for monitoring
 */
static int write_brightness_value(float brightness, float avg_brightness, daynight_mode_t mode) {

    FILE *fp;
    const char *mode_str;
    const char *dir_path = "/run/daynight";
    const char *file_path = "/run/daynight/value";

    /* Try /run/daynight first, fallback to /tmp/daynight if permission denied */
    if (mkdir(dir_path, 0755) != 0 && errno != EEXIST) {
        if (errno == EACCES || errno == EPERM) {
            dir_path = "/tmp/daynight";
            file_path = "/tmp/daynight/value";
            if (mkdir(dir_path, 0755) != 0 && errno != EEXIST) {
                log_message(LOG_WARNING, "Failed to create daynight directory: %s", strerror(errno));
                return -1;
            }
        } else {
            log_message(LOG_WARNING, "Failed to create %s directory: %s", dir_path, strerror(errno));
            return -1;
        }
    }

    /* Open value file for writing */
    fp = fopen(file_path, "w");
    if (!fp) {
        log_message(LOG_WARNING, "Failed to write brightness value to %s: %s", file_path, strerror(errno));
        return -1;
    }

    /* Convert mode to string */
    switch (mode) {
        case MODE_DAY: mode_str = "day"; break;
        case MODE_NIGHT: mode_str = "night"; break;
        default: mode_str = "unknown"; break;
    }

    /* Write brightness data in simple format */
    fprintf(fp, "%.1f %.1f %s\n", brightness, avg_brightness, mode_str);
    fclose(fp);

    return 0;
}

/*
 * Main processing loop with hysteresis logic
 */
static int main_loop(void) {
    float brightness, avg_brightness;
    float threshold_low_hyst, threshold_high_hyst;
    daynight_mode_t target_mode;
    int i, sample_count;

    /* Log suppression state: only report when values change */
    static int last_brightness_d10 = -1;
    static int last_avg_d10 = -1;
    static daynight_mode_t last_mode = MODE_UNKNOWN;

    /* Calculate hysteresis thresholds */
    float hyst_range = (g_config.threshold_high - g_config.threshold_low) * g_config.hysteresis_factor;
    threshold_low_hyst = g_config.threshold_low + hyst_range;
    threshold_high_hyst = g_config.threshold_high - hyst_range;

    log_message(LOG_INFO, "Starting main loop with thresholds: %.1f/%.1f (hysteresis: %.1f/%.1f)",
               g_config.threshold_low, g_config.threshold_high,
               threshold_low_hyst, threshold_high_hyst);

    g_state.running = true;
    g_state.current_mode = MODE_UNKNOWN;
    g_state.brightness_index = 0;

    /* Initialize brightness history */
    for (i = 0; i < BRIGHTNESS_SAMPLES; i++) {
        g_state.brightness_history[i] = 50.0f;  /* Neutral starting value */
    }

    while (g_state.running && !g_terminate_flag) {
        /* Calculate current brightness using Thingino methods */
        brightness = calculate_brightness_thingino();
        if (brightness < 0) {
            log_message(LOG_ERR, "Brightness calculation failed");
            usleep(g_config.sample_interval_ms * 1000);
            continue;
        }

        /* Calculate smoothed average brightness */
        avg_brightness = 0.0f;
        sample_count = 0;
        for (i = 0; i < BRIGHTNESS_SAMPLES; i++) {
            if (g_state.brightness_history[i] >= 0) {
                avg_brightness += g_state.brightness_history[i];
                sample_count++;
            }
        }

        if (sample_count > 0) {
            avg_brightness /= sample_count;
        } else {
            avg_brightness = brightness;
        }


        /* Track decision context for logging */
        float used_threshold = -1.0f;
        bool forced = false;

        /* Determine target mode with hysteresis */
        if (g_state.current_mode == MODE_DAY) {
            /* In day mode, switch to night only if below low threshold */
            if (avg_brightness < g_config.threshold_low) {
                target_mode = MODE_NIGHT;
                used_threshold = g_config.threshold_low;
            } else {
                target_mode = MODE_DAY;
            }
        } else if (g_state.current_mode == MODE_NIGHT) {
            /* In night mode, switch to day only if above high threshold */
            if (avg_brightness > g_config.threshold_high) {
                target_mode = MODE_DAY;
                used_threshold = g_config.threshold_high;
            } else {
                target_mode = MODE_NIGHT;
            }
        } else {
            /* Unknown mode, use hysteresis thresholds */
            if (avg_brightness < threshold_low_hyst) {
                target_mode = MODE_NIGHT;
                used_threshold = threshold_low_hyst;
            } else if (avg_brightness > threshold_high_hyst) {
                target_mode = MODE_DAY;
                used_threshold = threshold_high_hyst;
            } else {
                target_mode = g_state.current_mode;  /* Stay in current mode */
            }
        }

        /* Handle forced mode changes via signals */
        if (g_state.pending_mode != MODE_UNKNOWN) {
            target_mode = g_state.pending_mode;
            g_state.pending_mode = MODE_UNKNOWN;
            forced = true;
            log_message(LOG_INFO, "Forced mode change requested");
        }

        /* Apply mode change if needed */
        if (target_mode != g_state.current_mode && target_mode != MODE_UNKNOWN) {
            trigger_mode_change(target_mode, avg_brightness, used_threshold, forced);
        }

        int b10 = (int)(brightness * 10.0f + 0.5f);
        int avg10 = (int)(avg_brightness * 10.0f + 0.5f);
        if (b10 != last_brightness_d10 || avg10 != last_avg_d10 || g_state.current_mode != last_mode) {
            log_message(LOG_DEBUG, "Brightness: %.1f%% (avg: %.1f%%), Mode: %s",
                       brightness, avg_brightness,
                       (g_state.current_mode == MODE_DAY) ? "DAY" :
                       (g_state.current_mode == MODE_NIGHT) ? "NIGHT" : "UNKNOWN");
            last_brightness_d10 = b10;
            last_avg_d10 = avg10;
            last_mode = g_state.current_mode;
        }

        /* Write brightness value to /run/daynight/value for monitoring */
        write_brightness_value(brightness, avg_brightness, g_state.current_mode);

        /* Sleep until next sample */
        usleep(g_config.sample_interval_ms * 1000);
    }

    log_message(LOG_INFO, "Main loop terminated");
    return 0;
}

/*
 * Print usage information
 */
static void print_usage(const char *program_name) {
    printf("Usage: %s [OPTIONS]\n", program_name);
    printf("\nOptions:\n");
    printf("  -c, --config FILE    Configuration file (default: %s)\n", DEFAULT_CONFIG_FILE);
    printf("  -d, --device DEVICE  Video device (default: %s)\n", DEFAULT_DEVICE);
    printf("  -f, --foreground     Run in foreground (don't daemonize)\n");
    printf("  -p, --pid-file FILE  PID file (default: %s)\n", DEFAULT_PID_FILE);
    printf("  -v, --verbose        Increase verbosity\n");
    printf("  -h, --help           Show this help message\n");
    printf("  -V, --version        Show version information\n");
    printf("\nSignals:\n");
    printf("  SIGUSR1              Force day mode\n");
    printf("  SIGUSR2              Force night mode\n");
    printf("  SIGHUP               Reload configuration\n");
    printf("  SIGTERM/SIGINT       Graceful shutdown\n");
    printf("\nExample configuration file:\n");
    printf("  threshold_low = 30.0\n");
    printf("  threshold_high = 70.0\n");
    printf("  sample_interval_ms = 1000\n");
    printf("  transition_delay_s = 5\n");
    printf("\n");
}

/*
 * Main function
 */
int main(int argc, char *argv[]) {
    int opt;
    int option_index = 0;
    const char *config_file = DEFAULT_CONFIG_FILE;
    bool foreground = false;

    static struct option long_options[] = {
        {"config",     required_argument, 0, 'c'},
        {"device",     required_argument, 0, 'd'},
        {"foreground", no_argument,       0, 'f'},
        {"pid-file",   required_argument, 0, 'p'},
        {"verbose",    no_argument,       0, 'v'},
        {"help",       no_argument,       0, 'h'},
        {"version",    no_argument,       0, 'V'},
        {0, 0, 0, 0}
    };

    /* Initialize state */
    memset(&g_config, 0, sizeof(g_config));
    memset(&g_state, 0, sizeof(g_state));
    g_state.current_mode = MODE_UNKNOWN;
    g_state.pending_mode = MODE_UNKNOWN;

    /* Parse command line options */
    while ((opt = getopt_long(argc, argv, "c:d:fp:vhV", long_options, &option_index)) != -1) {
        switch (opt) {
            case 'c':
                config_file = optarg;
                break;
            case 'd':
                strncpy(g_config.device_path, optarg, sizeof(g_config.device_path) - 1);
                break;
            case 'f':
                foreground = true;
                break;
            case 'p':
                strncpy(g_config.pid_file, optarg, sizeof(g_config.pid_file) - 1);
                break;
            case 'v':
                if (g_config.log_level < 5) g_config.log_level++;
                break;
            case 'h':
                print_usage(argv[0]);
                exit(EXIT_SUCCESS);
            case 'V':
                printf("daynightd version 1.0.0 for Thingino firmware\n");
                printf("Built for MIPS Ingenic XBurst embedded systems\n");
                exit(EXIT_SUCCESS);
            default:
                print_usage(argv[0]);
                exit(EXIT_FAILURE);
        }
    }

    /* Load configuration */
    if (read_config(config_file) != 0) {
        fprintf(stderr, "Failed to load configuration\n");
        exit(EXIT_FAILURE);
    }

    /* Override daemon mode if foreground requested */
    if (foreground) {
        g_config.daemon_mode = false;
        g_config.enable_syslog = false;
    }

    /* Initialize logging */
    if (g_config.enable_syslog) {
        openlog("daynightd", LOG_PID | LOG_CONS, LOG_DAEMON);
    }

    log_message(LOG_INFO, "Starting daynightd v1.0.0");
    log_message(LOG_INFO, "Log level set to %s", log_level_name(g_config.log_level));


    /* Check if already running */
    FILE *pid_fp = fopen(g_config.pid_file, "r");
    if (pid_fp) {
        pid_t existing_pid;
        if (fscanf(pid_fp, "%d", &existing_pid) == 1) {
            if (kill(existing_pid, 0) == 0) {
                log_message(LOG_ERR, "Daemon already running with PID %d", existing_pid);
                fclose(pid_fp);
                exit(EXIT_FAILURE);
            }
        }
        fclose(pid_fp);
    }

    /* Initialize Thingino system */
    if (init_thingino_system() != 0) {
        log_message(LOG_ERR, "Failed to initialize Thingino system");
        exit(EXIT_FAILURE);
    }

    /* Setup signal handlers */
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    signal(SIGUSR1, signal_handler);
    signal(SIGUSR2, signal_handler);
    signal(SIGHUP, signal_handler);
    signal(SIGPIPE, SIG_IGN);

    /* Daemonize if requested */
    if (g_config.daemon_mode) {
        daemonize();
    }

    /* Create PID file */
    if (create_pid_file() != 0) {
        log_message(LOG_ERR, "Failed to create PID file");
        exit(EXIT_FAILURE);
    }

    /* Register cleanup function */
    atexit(remove_pid_file);

    /* Run main loop */
    int result = main_loop();

    /* Cleanup */
    log_message(LOG_INFO, "Shutting down daynightd");

    /* Remove brightness value file */
    unlink("/run/daynight/value");
    unlink("/tmp/daynight/value");
    rmdir("/run/daynight"); /* Remove directory if empty */
    rmdir("/tmp/daynight"); /* Remove directory if empty */

    if (g_config.enable_syslog) {
        closelog();
    }

    return result;
}
