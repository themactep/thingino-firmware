/*
 * Telegram Bot
 * (c) 2025 Thingino Project
 */
#include "json_config.h"

#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h> /* strcasecmp */
#include <syslog.h>
#include <time.h>
#include <unistd.h>

#include <curl/curl.h>
#include <sys/stat.h>
#include <sys/wait.h>


#ifndef TELEGRAM_TEXT_MAX
#define TELEGRAM_TEXT_MAX 4096
#endif

// Forward decl from jct (not in header)
extern JsonValue* parse_json_string(const char* json_str);

static volatile sig_atomic_t g_running = 1;

static void handle_signal(int sig)
{
    (void) sig;
    g_running = 0;
}

typedef struct {
    char* data;
    size_t size;
} Memory;

static size_t write_cb(void* contents, size_t size, size_t nmemb, void* userp)
{
    size_t realsize = size * nmemb;
    Memory* mem = (Memory*) userp;
    char* ptr = realloc(mem->data, mem->size + realsize + 1);
    if (!ptr)
        return 0;
    mem->data = ptr;
    memcpy(&(mem->data[mem->size]), contents, realsize);
    mem->size += realsize;
    mem->data[mem->size] = '\0';
    return realsize;
}

static int http_get(const char* url, long timeout_s, Memory* out)
{
    CURL* curl = curl_easy_init();
    if (!curl)
        return -1;
    out->data = NULL;
    out->size = 0;

    char err[CURL_ERROR_SIZE];
    err[0] = '\0';
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, err);
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void*) out);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, timeout_s);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 10L);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
#ifdef CURLOPT_TCP_KEEPALIVE
    curl_easy_setopt(curl, CURLOPT_TCP_KEEPALIVE, 1L);
#endif
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "telegrambot/1.0");

    long code = 0;
    CURLcode res = curl_easy_perform(curl);
    if (res == CURLE_OK) {
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &code);
    }
    if (res != CURLE_OK) {
        syslog(LOG_WARNING, "HTTP GET %s failed: %s", url, err[0] ? err : curl_easy_strerror(res));
    } else if (code != 200) {
        syslog(LOG_WARNING, "HTTP GET %s failed: HTTP %ld", url, code);
    }
    curl_easy_cleanup(curl);
    if (res != CURLE_OK || code != 200) {
        free(out->data);
        out->data = NULL;
        out->size = 0;
        return -1;
    }
    return 0;
}

static int http_post_json(const char* url, const char* json, long timeout_s, Memory* out)
{
    CURL* curl = curl_easy_init();
    if (!curl)
        return -1;
    out->data = NULL;
    out->size = 0;

    char err[CURL_ERROR_SIZE];
    err[0] = '\0';
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, err);

    struct curl_slist* headers = NULL;
    headers = curl_slist_append(headers, "Content-Type: application/json");

    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, json);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void*) out);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, timeout_s);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 10L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "telegrambot/1.0");

    long code = 0;
    CURLcode res = curl_easy_perform(curl);
    if (res == CURLE_OK) {
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &code);
    }
    if (res != CURLE_OK) {
        syslog(LOG_WARNING, "HTTP POST %s failed: %s", url, err[0] ? err : curl_easy_strerror(res));
    } else if (code != 200) {
        syslog(LOG_WARNING, "HTTP POST %s failed: HTTP %ld", url, code);
    }

    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);

    if (res != CURLE_OK || code != 200) {
        free(out->data);
        out->data = NULL;
        out->size = 0;
        return -1;
    }
    return 0;
}

// Minimal JSON string escaper for Telegram sendMessage
static void json_escape(const char* src, char* dst, size_t dstsz)
{
    size_t j = 0;
    if (!dstsz)
        return;
    if (!src) {
        dst[0] = '\0';
        return;
    }
    for (size_t i = 0; src[i] && j + 2 < dstsz; ++i) {
        unsigned char c = (unsigned char) src[i];
        switch (c) {
        case '"':
            if (j + 2 < dstsz) {
                dst[j++] = '\\';
                dst[j++] = '"';
            }
            break;
        case '\\':
            if (j + 2 < dstsz) {
                dst[j++] = '\\';
                dst[j++] = '\\';
            }
            break;
        case '\n':
            if (j + 2 < dstsz) {
                dst[j++] = '\\';
                dst[j++] = 'n';
            }
            break;
        case '\r':
            if (j + 2 < dstsz) {
                dst[j++] = '\\';
                dst[j++] = 'r';
            }
            break;
        case '\t':
            if (j + 2 < dstsz) {
                dst[j++] = '\\';
                dst[j++] = 't';
            }
            break;
        default:
            if (c < 0x20) {
                /* skip other control chars */
            } else {
                dst[j++] = (char) c;
            }
        }
        if (j >= dstsz - 1)
            break;
    }
    dst[j] = '\0';
}

typedef struct {
    char token[128];
    char api_url[64];
    int polling_timeout;
    int daemonize;
    char state_file[128];
    long allowed_ids[8];
    int allowed_count;
    char allowed_users[16][32];
    int allowed_users_count;
    struct {
        char handle[32];
        char description[128];
        char exec[160];
    } commands[16];
    int cmd_count;
    int log_priority; /* syslog priority threshold, e.g., LOG_INFO */
    int publish_menu; /* 1=publish Telegram bot menu at startup */
} Config;

/* forward declaration */
static void make_url(char* buf, size_t bufsz, const Config* cfg, const char* method, const char* qs);

static long read_long(JsonValue* obj, const char* key, long def)
{
    JsonValue* it = get_nested_item(obj, key);
    if (it && it->type == JSON_NUMBER) {
        return (long) it->value.number;
    }
    return def;
}

static int read_bool(JsonValue* obj, const char* key, int def)
{
    JsonValue* it = get_nested_item(obj, key);
    if (it && it->type == JSON_BOOL) {
        return it->value.boolean;
    }
    return def;
}

static void read_string(JsonValue* obj, const char* key, const char* def, char* dst, size_t dstsz)
{
    JsonValue* it = get_nested_item(obj, key);
    const char* s = (it && it->type == JSON_STRING) ? it->value.string : def;
    if (!s)
        s = "";
    snprintf(dst, dstsz, "%s", s);
}

static int parse_log_level(const char* s)
{
    if (!s)
        return LOG_INFO;
    if (!strcasecmp(s, "DEBUG"))
        return LOG_DEBUG;
    if (!strcasecmp(s, "INFO"))
        return LOG_INFO;
    if (!strcasecmp(s, "WARNING"))
        return LOG_WARNING;
    if (!strcasecmp(s, "WARN"))
        return LOG_WARNING;
    if (!strcasecmp(s, "ERROR"))
        return LOG_ERR;
    if (!strcasecmp(s, "CRITICAL"))
        return LOG_CRIT;
    if (!strcasecmp(s, "NOTICE"))
        return LOG_NOTICE;
    return LOG_INFO;
}

static int user_allowed(const Config* cfg, const char* username)
{
    if (cfg->allowed_users_count == 0) {
        return 1; // no username filter
    }
    if (!username || !*username) {
        return 0;
    }
    for (int i = 0; i < cfg->allowed_users_count; ++i) {
        if (strcmp(cfg->allowed_users[i], username) == 0)
            return 1;
    }
    return 0;
}

static int find_command(const Config* cfg, const char* text)
{
    if (!text)
        return -1;
    for (int i = 0; i < cfg->cmd_count; ++i) {
        const char* h = cfg->commands[i].handle;
        if (!h || !*h)
            continue;
        if (strcmp(text, h) == 0)
            return i; // exact match
        if (text[0] == '/' && strcmp(text + 1, h) == 0)
            return i; // allow "/" prefix
    }
    return -1;
}

// forward declaration
static int reply_text(const Config* cfg, long chat_id, const char* text);

static int run_command(const Config* cfg, int idx, long chat_id)
{
    if (idx < 0 || idx >= cfg->cmd_count) {
        return -1;
    }
    const char* cmd = cfg->commands[idx].exec;
    if (!cmd || !*cmd) {
        return -1;
    }

    /* Capture both stdout and stderr like the legacy shell bot (2>&1) */
    char cmdline[256];
    snprintf(cmdline, sizeof cmdline, "%s 2>&1", cmd);

    FILE* p = popen(cmdline, "r");
    if (!p)
        return -1;
    char buf[TELEGRAM_TEXT_MAX + 1];
    size_t n = fread(buf, 1, sizeof(buf) - 1, p);
    buf[n] = '\0';
    int status = pclose(p);

    int exitcode = -1;
#ifdef WIFEXITED
    if (status >= 0) {
        if (WIFEXITED(status))
            exitcode = WEXITSTATUS(status);
        else if (WIFSIGNALED(status))
            exitcode = 128 + WTERMSIG(status);
    }
#endif

    // Trim trailing newlines
    while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) {
        buf[--n] = '\0';
    }

    if (exitcode != 0) {
        syslog(LOG_WARNING, "Command failed: %s (code %d)", cmd, exitcode);
        char msg[TELEGRAM_TEXT_MAX + 128];
        snprintf(msg, sizeof msg, "Execution failed! Please review the command:\n%s\n\nOutput:\n%s", cmd, (n ? buf : ""));
        return reply_text(cfg, chat_id, msg);
    }

    syslog(LOG_DEBUG, "Command succeeded: %s (%zu bytes)", cmd, (size_t) n);
    if (n == 0) {
        return reply_text(cfg, chat_id, "OK");
    }
    return reply_text(cfg, chat_id, buf);
}

static int id_allowed(Config* cfg, long chat_id)
{
    if (cfg->allowed_count == 0)
        return 1; // no filter
    for (int i = 0; i < cfg->allowed_count; ++i)
        if (cfg->allowed_ids[i] == chat_id)
            return 1;
    return 0;
}

static int load_config_file(const char* path, Config* cfg)
{
    memset(cfg, 0, sizeof(*cfg));
    snprintf(cfg->api_url, sizeof(cfg->api_url), "%s", "https://api.telegram.org");
    snprintf(cfg->state_file, sizeof(cfg->state_file), "%s", "/run/telegrambot.state");
    cfg->polling_timeout = 30;
    cfg->daemonize = 1;
    cfg->log_priority = LOG_INFO;
    cfg->publish_menu = 1;

    JsonValue* root = load_config(path);
    if (!root)
        return -1;

    read_string(root, "token", "", cfg->token, sizeof(cfg->token));
    read_string(root, "api_url", cfg->api_url, cfg->api_url, sizeof(cfg->api_url));
    read_string(root, "state_file", cfg->state_file, cfg->state_file, sizeof(cfg->state_file));
    cfg->polling_timeout = (int) read_long(root, "polling_timeout", cfg->polling_timeout);
    cfg->daemonize = read_bool(root, "daemon", cfg->daemonize);
    /* logging level */
    {
        char lvl[16];
        read_string(root, "log_level", "INFO", lvl, sizeof lvl);
        cfg->log_priority = parse_log_level(lvl);
    }
    /* menu publishing enable */
    cfg->publish_menu = read_bool(root, "publish_menu", cfg->publish_menu);

    // allowed_chat_ids array
    JsonValue* arr = get_nested_item(root, "allowed_chat_ids");
    if (arr && arr->type == JSON_ARRAY) {
        int n = get_array_size(arr);
        for (int i = 0; i < n && cfg->allowed_count < (int) (sizeof(cfg->allowed_ids) / sizeof(cfg->allowed_ids[0])); ++i) {
            JsonValue* el = get_array_item(arr, i);
            if (el && el->type == JSON_NUMBER)
                cfg->allowed_ids[cfg->allowed_count++] = (long) el->value.number;
        }
    }

    // allowed_usernames array
    JsonValue* arru = get_nested_item(root, "allowed_usernames");
    if (arru && arru->type == JSON_ARRAY) {
        int n = get_array_size(arru);
        for (int i = 0; i < n && cfg->allowed_users_count < (int) (sizeof(cfg->allowed_users) / sizeof(cfg->allowed_users[0])); ++i) {
            JsonValue* el = get_array_item(arru, i);
            if (el && el->type == JSON_STRING) {
                snprintf(cfg->allowed_users[cfg->allowed_users_count++], sizeof(cfg->allowed_users[0]), "%s", el->value.string);
            }
        }
    }

    // commands array
    JsonValue* cmds = get_nested_item(root, "commands");
    if (cmds && cmds->type == JSON_ARRAY) {
        int n = get_array_size(cmds);
        for (int i = 0; i < n && cfg->cmd_count < (int) (sizeof(cfg->commands) / sizeof(cfg->commands[0])); ++i) {
            JsonValue* c = get_array_item(cmds, i);
            if (!c || c->type != JSON_OBJECT)
                continue;
            JsonValue* h = get_object_item(c, "handle");
            JsonValue* d = get_object_item(c, "description");
            JsonValue* e = get_object_item(c, "exec");
            if (!h || h->type != JSON_STRING || !e || e->type != JSON_STRING)
                continue;
            snprintf(cfg->commands[cfg->cmd_count].handle, sizeof(cfg->commands[cfg->cmd_count].handle), "%s", h->value.string);
            snprintf(cfg->commands[cfg->cmd_count].description,
                     sizeof(cfg->commands[cfg->cmd_count].description),
                     "%s",
                     (d && d->type == JSON_STRING) ? d->value.string : "");
            snprintf(cfg->commands[cfg->cmd_count].exec, sizeof(cfg->commands[cfg->cmd_count].exec), "%s", e->value.string);
            cfg->cmd_count++;
        }
    }

    free_json_value(root);
    if (cfg->token[0] == '\0') {
        syslog(LOG_ERR, "Missing token in config");
        return -1;
    }
    return 0;
}

static long load_offset(const char* path)
{
    FILE* f = fopen(path, "r");
    if (!f)
        return 0;
    long off = 0;
    fscanf(f, "%ld", &off);
    fclose(f);
    return off;
}

static void save_offset(const char* path, long off)
{
    FILE* f = fopen(path, "w");
    if (!f) {
        return;
    }
    fprintf(f, "%ld\n", off);
    fclose(f);
}

static void build_commands_json(const Config* cfg, char* out, size_t outsz)
{
    size_t off = 0;
    if (outsz == 0)
        return;
    out[0] = '\0';
    off += snprintf(out + off, outsz > off ? outsz - off : 0, "[");
    for (int i = 0; i < cfg->cmd_count && off < outsz - 1; ++i) {
        char h[64];
        char d[256];
        json_escape(cfg->commands[i].handle, h, sizeof h);
        json_escape(cfg->commands[i].description, d, sizeof d);
        off += snprintf(out + off, outsz > off ? outsz - off : 0, "{\"command\":\"%s\",\"description\":\"%s\"},", h, d);
    }
    /* Always add built-in help */
    off += snprintf(out + off, outsz > off ? outsz - off : 0, "{\"command\":\"help\",\"description\":\"Help\"}]");
    if (off >= outsz) {
        out[outsz - 1] = '\0';
    }
}

static int api_delete_my_commands(const Config* cfg)
{
    char url[512];
    make_url(url, sizeof url, cfg, "deleteMyCommands", NULL);
    Memory m;
    if (http_post_json(url, "{}", 20, &m) != 0)
        return -1;
    free(m.data);
    return 0;
}

static int api_set_my_commands(const Config* cfg)
{
    char url[512];
    make_url(url, sizeof url, cfg, "setMyCommands", NULL);
    char cmds[4096];
    build_commands_json(cfg, cmds, sizeof cmds);
    char body[4600];
    snprintf(body, sizeof body, "{\"commands\":%s}", cmds);
    Memory m;
    if (http_post_json(url, body, 20, &m) != 0)
        return -1;
    free(m.data);
    return 0;
}

static void publish_bot_menu(const Config* cfg)
{
    if (api_delete_my_commands(cfg) == 0) {
        syslog(LOG_INFO, "Cleared previous bot commands");
    } else {
        syslog(LOG_WARNING, "Failed to clear previous bot commands");
    }
    if (api_set_my_commands(cfg) == 0) {
        syslog(LOG_INFO, "Published %d bot commands (+help)", cfg->cmd_count);
    } else {
        syslog(LOG_WARNING, "Failed to publish bot commands");
    }
}

static void make_url(char* buf, size_t bufsz, const Config* cfg, const char* method, const char* qs)
{
    // Build: <api_url>/bot<TOKEN>/<method>[?qs]
    // Use a larger buffer at call sites; this function still respects bufsz
    snprintf(buf, bufsz, "%s/bot%s/%s%s%s", cfg->api_url, cfg->token, method, (qs && qs[0]) ? "?" : "", (qs && qs[0]) ? qs : "");
}

static int reply_text(const Config* cfg, long chat_id, const char* text)
{
    char url[512];
    make_url(url, sizeof(url), cfg, "sendMessage", NULL);

    char esc[TELEGRAM_TEXT_MAX + 1];
    json_escape(text, esc, sizeof esc);
    char body[TELEGRAM_TEXT_MAX + 128];
    snprintf(body, sizeof(body), "{\"chat_id\":%ld,\"text\":\"%s\"}", chat_id, esc);

    Memory m;
    if (http_post_json(url, body, 20, &m) != 0)
        return -1;
    free(m.data);
    return 0;
}

static void process_update(const Config* cfg, JsonValue* upd)
{
    if (!upd || upd->type != JSON_OBJECT)
        return;

    JsonValue* msg = get_object_item(upd, "message");
    if (!msg || msg->type != JSON_OBJECT)
        return;

    JsonValue* chat = get_object_item(msg, "chat");
    JsonValue* text = get_object_item(msg, "text");
    if (!chat || chat->type != JSON_OBJECT || !text || text->type != JSON_STRING)
        return;

    JsonValue* cidv = get_object_item(chat, "id");
    if (!cidv || cidv->type != JSON_NUMBER)
        return;
    long chat_id = (long) cidv->value.number;

    // Username check
    const char* username = NULL;
    JsonValue* from = get_object_item(msg, "from");
    if (from && from->type == JSON_OBJECT) {
        JsonValue* uname = get_object_item(from, "username");
        if (uname && uname->type == JSON_STRING)
            username = uname->value.string;
    }
    if (!user_allowed(cfg, username)) {
        syslog(LOG_INFO, "Ignoring message from username '%s'", username ? username : "");
        return;
    }

    // Chat ID filter (if present)
    if (!id_allowed((Config*) cfg, chat_id)) {
        syslog(LOG_INFO, "Ignoring message from chat %ld (not allowed)", chat_id);
        return;
    }

    const char* t = text->value.string;
    if (username && *username) {
        syslog(LOG_INFO, "Message from %ld (@%s): %s", chat_id, username, t);
    } else {
        syslog(LOG_INFO, "Message from %ld: %s", chat_id, t);
    }

    // Configured commands take precedence
    int ci = find_command(cfg, t);
    if (ci >= 0) {
        const char* h = cfg->commands[ci].handle;
        const char* e = cfg->commands[ci].exec;
        if (username && *username) {
            syslog(LOG_INFO, "Executing '/%s' -> %s (chat %ld, @%s)", h, e, chat_id, username);
        } else {
            syslog(LOG_INFO, "Executing '/%s' -> %s (chat %ld)", h, e, chat_id);
        }
        run_command(cfg, ci, chat_id);
        return;
    }

    // Built-ins
    if (strcmp(t, "/ping") == 0) {
        reply_text(cfg, chat_id, "pong");
    } else if (strcmp(t, "/time") == 0) {
        char buf[64];
        time_t now = time(NULL);
        struct tm tm;
        localtime_r(&now, &tm);
        strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", &tm);
        reply_text(cfg, chat_id, buf);
    } else if (strcmp(t, "/help") == 0) {
        char buf[512];
        size_t off = 0;
        off += snprintf(buf + off, sizeof(buf) - off, "Commands:\n");
        for (int i = 0; i < cfg->cmd_count && off < sizeof(buf) - 1; ++i) {
            off += snprintf(buf + off, sizeof(buf) - off, "%s - %s\n", cfg->commands[i].handle, cfg->commands[i].description);
        }
        reply_text(cfg, chat_id, buf);
    } else {
        reply_text(cfg, chat_id, "Unknown command. Try /help");
    }
}

static int poll_once(const Config* cfg, long* offset_io)
{
    char qs[64] = {0};
    if (*offset_io > 0)
        snprintf(qs, sizeof(qs), "offset=%ld", *offset_io + 1);
    char url[512];
    char qs2[80];
    snprintf(qs2, sizeof(qs2), "%s%stimeout=%d", qs, (qs[0] ? "&" : ""), cfg->polling_timeout);
    make_url(url, sizeof(url), cfg, "getUpdates", qs2);

    Memory m;
    if (http_get(url, cfg->polling_timeout + 10, &m) != 0)
        return -1;

    JsonValue* root = parse_json_string(m.data);
    free(m.data);
    if (!root || root->type != JSON_OBJECT) {
        free_json_value(root);
        return -1;
    }

    JsonValue* ok = get_object_item(root, "ok");
    if (!ok || ok->type != JSON_BOOL || !ok->value.boolean) {
        free_json_value(root);
        return -1;
    }

    JsonValue* res = get_object_item(root, "result");
    if (!res || res->type != JSON_ARRAY) {
        free_json_value(root);
        return 0;
    }

    int n = get_array_size(res);
    for (int i = 0; i < n; ++i) {
        JsonValue* upd = get_array_item(res, i);
        // Track update_id
        JsonValue* uidv = upd && upd->type == JSON_OBJECT ? get_object_item(upd, "update_id") : NULL;
        long uid = (uidv && uidv->type == JSON_NUMBER) ? (long) uidv->value.number : 0;
        if (uid > *offset_io)
            *offset_io = uid;
        process_update(cfg, upd);
    }

    free_json_value(root);
    return n;
}

static void daemonize_self(void)
{
    pid_t pid = fork();
    if (pid < 0)
        exit(EXIT_FAILURE);
    if (pid > 0)
        exit(EXIT_SUCCESS);
    if (setsid() < 0)
        exit(EXIT_FAILURE);
    signal(SIGHUP, SIG_IGN);
    pid = fork();
    if (pid < 0)
        exit(EXIT_FAILURE);
    if (pid > 0)
        exit(EXIT_SUCCESS);
    umask(027);
    chdir("/");
    for (int fd = 0; fd < 3; ++fd)
        close(fd);
    int fd0 = open("/dev/null", O_RDWR);
    if (fd0 >= 0) {
        dup2(fd0, 0);
        dup2(fd0, 1);
        dup2(fd0, 2);
        if (fd0 > 2)
            close(fd0);
    }
}

int main(int argc, char** argv)
{
    const char* config_path = (argc > 1) ? argv[1] : "/etc/telegrambot.json";

    openlog("telegrambot", LOG_PID | LOG_CONS, LOG_DAEMON);
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    Config cfg;
    if (load_config_file(config_path, &cfg) != 0) {
        syslog(LOG_ERR, "Failed to load config: %s", config_path);
        return 2;
    }

    /* Apply log mask based on configured level */
    setlogmask(LOG_UPTO(cfg.log_priority));

    if (cfg.daemonize)
        daemonize_self();

    curl_global_init(CURL_GLOBAL_DEFAULT);

    /* Publish Telegram command menu from configured commands */
    if (cfg.publish_menu)
        publish_bot_menu(&cfg);

    long offset = load_offset(cfg.state_file);

    syslog(LOG_INFO, "Telegram bot started. Poll timeout=%d", cfg.polling_timeout);

    while (g_running) {
        int rc = poll_once(&cfg, &offset);
        if (rc >= 0) {
            if (offset > 0)
                save_offset(cfg.state_file, offset);
        } else {
            syslog(LOG_WARNING, "Polling failed; sleeping");
            sleep(5);
        }
    }

    curl_global_cleanup();
    syslog(LOG_INFO, "Telegram bot stopped");
    closelog();
    return 0;
}
