/*
 * doorbell_chime.c – Wyze Doorbell V1 Chime Controller
 *
 * Chime persistence (thingino.json):
 *   { "chime": {
 *       "units":  { "<MAC_ID>": {"name":"...","mac":"XX:XX:XX:XX"}, ... },
 *       "groups": { "groupname": ["<MAC_ID>","<MAC_ID>"], ... },
 *       "events": { "eventname": { "sound":"...", ... }, ... }
 *   } }
 *
 * MAC_ID is the 8-char hex MAC without colons (e.g. "77DA39F9").
 * Groups reference MAC_IDs, so renaming a chime never breaks groups.
 *
 * Built by Buildroot via wyze-accessory.mk.
 */

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>
#include <sys/select.h>
#include <time.h>

#ifndef CRTSCTS
#define CRTSCTS 020000000000
#endif

#define DEVICE          "/dev/ttyS0"
#define DEFAULT_VOLUME  5
#define DEFAULT_REPEAT  1
#define CONFIG_FILE     "/etc/thingino.json"
#define MAX_CHIMES      16
#define MAX_NAME        32
#define MAC_ID_LEN      8   /* MAC without colons, e.g. "77DA39F9" */

/* 16-byte challenge R (from WyzeSensePy Scan()) */
static const unsigned char CHALLENGE_R[16] = {
    'O','k','5','H','P','N','Q','4','l','f','7','7','u','7','5','4'
};

static int debug_mode = 0;
static int do_delete  = 0;

#define dbg(fmt, ...) do { if (debug_mode) printf(fmt, ##__VA_ARGS__); } while (0)

/* ──────────────────────────── MAC helpers ───────────────────────── */

static int parse_mac(const char *s, unsigned char *mac8)
{
    int j = 0;
    for (; *s && j < 8; s++) {
        if (*s == ':') continue;
        if (!isxdigit((unsigned char)*s)) return -1;
        mac8[j++] = (unsigned char)toupper((unsigned char)*s);
    }
    return (j == 8) ? 0 : -1;
}

/* Recognise colon-separated MAC or 8-char hex MAC-ID. */
static int looks_like_mac(const char *s)
{
    if (strchr(s, ':')) return 1;
    if (strlen(s) != 8) return 0;
    while (*s) { if (!isxdigit((unsigned char)*s)) return 0; s++; }
    return 1;
}

/* Convert "XX:XX:XX:XX" → "XXXXXXXX" (MAC ID).  Caller provides 9 bytes. */
static void mac_to_id(const char *mac_str, char *id)
{
    int j = 0;
    for (; *mac_str && j < MAC_ID_LEN; mac_str++) {
        if (*mac_str == ':') continue;
        id[j++] = (char)toupper((unsigned char)*mac_str);
    }
    id[j] = '\0';
}

static void mac8_to_str(const unsigned char *mac8, char *out)
{
    snprintf(out, 20, "%c%c:%c%c:%c%c:%c%c",
             mac8[0], mac8[1], mac8[2], mac8[3],
             mac8[4], mac8[5], mac8[6], mac8[7]);
}

/* ID "77DA39F9" → wire-format mac8.  Returns 0 on success. */
static int id_to_mac8(const char *id, unsigned char *mac8)
{
    int i;
    for (i = 0; i < 8; i++) {
        if (!isxdigit((unsigned char)id[i])) return -1;
        mac8[i] = (unsigned char)toupper((unsigned char)id[i]);
    }
    return 0;
}

/* ID "77DA39F9" → display string "77:DA:39:F9". */
static void id_to_mac_str(const char *id, char *out)
{
    snprintf(out, 20, "%c%c:%c%c:%c%c:%c%c",
             id[0], id[1], id[2], id[3],
             id[4], id[5], id[6], id[7]);
}

static void mac8_to_id(const unsigned char *mac8, char *id)
{
    snprintf(id, MAC_ID_LEN + 1, "%c%c%c%c%c%c%c%c",
             mac8[0], mac8[1], mac8[2], mac8[3],
             mac8[4], mac8[5], mac8[6], mac8[7]);
}

/* ──────────────────────────── jct helpers ──────────────────────── */

static int jct_config_read(const char *key, char *out, size_t out_size)
{
    char cmd[256];
    FILE *pipe;
    size_t len;

    snprintf(cmd, sizeof(cmd), "jct %s get %s 2>/dev/null", CONFIG_FILE, key);
    pipe = popen(cmd, "r");
    if (!pipe) return -1;
    if (!fgets(out, (int)out_size, pipe)) { pclose(pipe); return -1; }
    pclose(pipe);

    len = strlen(out);
    while (len > 0 && (out[len-1] == '\n' || out[len-1] == '\r'))
        out[--len] = '\0';
    if (len >= 2 && out[0] == '"' && out[len-1] == '"') {
        memmove(out, out + 1, len - 2);
        out[len - 2] = '\0';
    }
    return 0;
}

static int jct_config_set(const char *key, const char *value)
{
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "jct %s set %s '%s' 2>/dev/null",
             CONFIG_FILE, key, value);
    return system(cmd) == 0 ? 0 : -1;
}

/* Remove a key using jct del. */
static int jct_config_remove(const char *key)
{
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "jct %s del %s 2>/dev/null",
             CONFIG_FILE, key);
    return system(cmd) == 0 ? 0 : -1;
}

static int jct_val_is_empty(const char *val)
{
    return !val[0] || !strcmp(val, "null");
}

/*
 * Collect chime IDs (MAC IDs) from chime.units{} object keys.
 * Returns count, fills ids[] (caller must free each).
 */
static int jct_list_chime_ids(char **ids, int max_ids)
{
    char cmd[256], buf[4096], *p, *end;
    FILE *pipe;
    int count = 0;

    snprintf(cmd, sizeof(cmd),
             "jct %s path '$.chime.units.*~' --mode paths 2>/dev/null",
             CONFIG_FILE);
    pipe = popen(cmd, "r");
    if (!pipe) return 0;

    buf[0] = '\0';
    (void)!fread(buf, 1, sizeof(buf) - 1, pipe);
    pclose(pipe);

    p = buf;
    while (*p && count < max_ids) {
        p = strstr(p, "$.chime.units");
        if (!p) break;
        p += 13;  /* skip "$.chime.units" */

        /* Handle jct bracket notation: $.chime.units['77DA39F9'] */
        if (p[0] == '[' && p[1] == '\'') {
            p += 2;
            end = strchr(p, '\'');
        } else if (p[0] == '.') {
            /* Legacy dot notation: $.chime.units.77DA39F9" */
            p += 1;
            end = strchr(p, '"');
        } else {
            break;
        }
        if (!end) break;
        if (end - p == MAC_ID_LEN) {
            ids[count] = strndup(p, MAC_ID_LEN);
            if (ids[count]) count++;
        }
        p = end + 1;
    }
    return count;
}

static void free_id_list(char **ids, int count)
{
    int i;
    for (i = 0; i < count; i++) free(ids[i]);
}

/* Get chime name by MAC ID. Returns name in static buffer, or NULL. */
static const char *chime_get_name(const char *id)
{
    static char name[MAX_NAME];
    char key[64];
    snprintf(key, sizeof(key), "chime.units.%s.name", id);
    if (jct_config_read(key, name, sizeof(name)) < 0) return NULL;
    if (jct_val_is_empty(name)) return NULL;
    return name;
}

/*
 * Resolve a user-facing identifier (name, MAC-ID, or XX:XX:XX:XX)
 * to a MAC ID and wire-format MAC.  Returns 0 on success.
 */
static int chime_resolve(const char *arg, char *id_out, unsigned char *mac8)
{
    char id[MAC_ID_LEN + 1];

    /* 1. colon-separated MAC → strip to ID, derive mac8 */
    if (looks_like_mac(arg)) {
        mac_to_id(arg, id);
        if (chime_get_name(id)) {
            if (id_out) strcpy(id_out, id);
            return id_to_mac8(id, mac8);
        }
        return -1;
    }

    /* 2. try as MAC ID directly */
    if (strlen(arg) == MAC_ID_LEN) {
        if (chime_get_name(arg)) {
            if (id_out) strcpy(id_out, arg);
            return id_to_mac8(arg, mac8);
        }
    }

    /* 3. search by name */
    {
        char *ids[MAX_CHIMES];
        int count = jct_list_chime_ids(ids, MAX_CHIMES);
        int i;
        for (i = 0; i < count; i++) {
            const char *nm = chime_get_name(ids[i]);
            if (nm && !strcmp(nm, arg)) {
                if (id_out) strcpy(id_out, ids[i]);
                int rc = id_to_mac8(ids[i], mac8);
                free_id_list(ids, count);
                return rc;
            }
        }
        free_id_list(ids, count);
    }
    return -1;
}

/*
 * Find the MAC ID for a given name.  Returns static string or NULL.
 */
static const char *chime_id_by_name(const char *name)
{
    static char id[MAC_ID_LEN + 1];
    char *ids[MAX_CHIMES];
    int count = jct_list_chime_ids(ids, MAX_CHIMES);
    int i;
    for (i = 0; i < count; i++) {
        const char *nm = chime_get_name(ids[i]);
        if (nm && !strcmp(nm, name)) {
            strcpy(id, ids[i]);
            free_id_list(ids, count);
            return id;
        }
    }
    free_id_list(ids, count);
    return NULL;
}

/* ──────────────────────────── groups ───────────────────────────── */

static int chime_group_members_list(const char *group_name,
                                    char **ids, int max_ids)
{
    char cmd[256], buf[4096], *p, *end;
    FILE *pipe;
    int count = 0;

    snprintf(cmd, sizeof(cmd),
             "jct %s path '$.chime.groups.%s[*]' --mode values 2>/dev/null",
             CONFIG_FILE, group_name);
    pipe = popen(cmd, "r");
    if (!pipe) return 0;

    buf[0] = '\0';
    (void)!fread(buf, 1, sizeof(buf) - 1, pipe);
    pclose(pipe);

    p = buf;
    while (*p && count < max_ids) {
        p = strchr(p, '"');
        if (!p) break;
        p++;
        end = strchr(p, '"');
        if (!end) break;
        if (end - p == MAC_ID_LEN) {
            ids[count] = strndup(p, MAC_ID_LEN);
            if (ids[count]) count++;
        }
        p = end + 1;
    }
    return count;
}

static void chime_group_write(const char *group_name,
                              char **ids, int count)
{
    char patch_path[] = "/tmp/jct_grp.XXXXXX";
    char cmd[512];
    int fd, i;
    FILE *f;

    fd = mkstemp(patch_path);
    if (fd < 0) return;
    f = fdopen(fd, "w");
    if (!f) { close(fd); return; }

    fprintf(f, "{\"chime\":{\"groups\":{\"%s\":[", group_name);
    for (i = 0; i < count; i++) {
        if (i > 0) fputc(',', f);
        fprintf(f, "\"%s\"", ids[i]);
    }
    fprintf(f, "]}}}\n");
    fclose(f);

    snprintf(cmd, sizeof(cmd), "jct %s import %s 2>/dev/null",
             CONFIG_FILE, patch_path);
    system(cmd);
    unlink(patch_path);
}

static void chime_group_add(const char *group_name, const char *id)
{
    char *members[MAX_CHIMES];
    int count = chime_group_members_list(group_name, members, MAX_CHIMES);
    int i, found = 0;

    for (i = 0; i < count; i++) {
        if (!strcmp(members[i], id)) { found = 1; break; }
    }
    if (!found) {
        members[count] = strdup(id);
        if (members[count]) count++;
    }
    chime_group_write(group_name, members, count);
    for (i = 0; i < count; i++) free(members[i]);
}

static void chime_group_remove(const char *group_name, const char *id)
{
    char *members[MAX_CHIMES];
    int count = chime_group_members_list(group_name, members, MAX_CHIMES);
    int i, j = 0;

    for (i = 0; i < count; i++) {
        if (strcmp(members[i], id)) {
            members[j++] = members[i];
        } else {
            free(members[i]);
        }
    }
    chime_group_write(group_name, members, j);
}

static int list_group_names(char **names, int max_names)
{
    char cmd[256], buf[4096], *p, *end;
    FILE *pipe;
    int gcount = 0;

    snprintf(cmd, sizeof(cmd),
             "jct %s path '$.chime.groups.*~' --mode paths 2>/dev/null",
             CONFIG_FILE);
    pipe = popen(cmd, "r");
    if (!pipe) return 0;

    buf[0] = '\0';
    (void)!fread(buf, 1, sizeof(buf) - 1, pipe);
    pclose(pipe);
    p = buf;
    while (*p && gcount < max_names) {
        p = strstr(p, "$.chime.groups");
        if (!p) break;
        p += 14;  /* skip "$.chime.groups" */

        /* Handle jct bracket notation: $.chime.groups['all'] */
        if (p[0] == '[' && p[1] == '\'') {
            p += 2;
            end = strchr(p, '\'');
        } else if (p[0] == '.') {
            /* Legacy dot notation: $.chime.groups.all" */
            p += 1;
            end = strchr(p, '"');
        } else {
            break;
        }
        if (!end) break;
        if (end - p > 0 && end - p < MAX_NAME) {
            names[gcount] = strndup(p, (size_t)(end - p));
            if (names[gcount]) gcount++;
        }
        p = end + 1;
    }
    return gcount;
}

/* ──────────────────────────── sounds ───────────────────────────── */

static const struct { const char *name; int id; } SOUNDS[] = {
    {"SPACE_WAVE",  1}, {"WIND_CHIME", 2}, {"CURIOSITY",   3},
    {"SURPRISE",    4}, {"CHEERFUL",   5}, {"DOORBELL_1",  6},
    {"DOORBELL_2",  7}, {"DOORBELL_3", 8}, {"DOORBELL_4",  9},
    {"BIRD_CHIRP", 10}, {"DOG_BARK_1",11}, {"DOG_BARK_2", 12},
    {"DOOR_CLOSE", 13}, {"DOOR_OPEN", 14}, {"SIMPLE_1",   15},
    {"SIMPLE_2",   16}, {"SIMPLE_3",  17}, {"SIMPLE_4",   18},
    {"INTRUDER",   19},
};
#define N_SOUNDS ((int)(sizeof(SOUNDS) / sizeof(SOUNDS[0])))

static int resolve_sound(const char *arg)
{
    int i;
    for (i = 0; i < N_SOUNDS; i++)
        if (!strcmp(arg, SOUNDS[i].name)) return SOUNDS[i].id;
    char *end;
    long n = strtol(arg, &end, 10);
    return (*end == '\0' && n >= 1 && n <= 19) ? (int)n : -1;
}

/* ──────────────────────────── packet helpers ────────────────────── */

static void hex_dump(const char *lbl, const unsigned char *d, int n)
{
    int i;
    if (!debug_mode) return;
    printf("%s [%d]:", lbl, n);
    for (i = 0; i < n; i++) printf(" %02X", d[i]);
    printf("  |");
    for (i = 0; i < n; i++) putchar(isprint(d[i]) ? d[i] : '.');
    putchar('\n');
}

static unsigned short pkt_sum(const unsigned char *d, int n)
{
    unsigned short s = 0;
    while (n--) s += *d++;
    return s;
}

static int build_pkt(unsigned char *buf, unsigned char cmd,
                     const unsigned char *payload, int plen)
{
    int pos = 0;
    buf[pos++] = 0xAA; buf[pos++] = 0x55; buf[pos++] = 0x53;
    buf[pos++] = (unsigned char)(plen + 3);
    buf[pos++] = cmd;
    if (payload && plen) { memcpy(buf + pos, payload, plen); pos += plen; }
    unsigned short cs = pkt_sum(buf, pos);
    buf[pos++] = cs >> 8;
    buf[pos++] = cs & 0xFF;
    return pos;
}

/* ──────────────────────────── serial ───────────────────────────── */

static int configure_serial(int fd)
{
    struct termios tty;
    if (tcgetattr(fd, &tty)) { perror("tcgetattr"); return -1; }
    cfsetospeed(&tty, B115200); cfsetispeed(&tty, B115200);
    tty.c_cflag |=  (CLOCAL | CREAD);
    tty.c_cflag &= ~CSIZE;  tty.c_cflag |= CS8;
    tty.c_cflag &= ~(PARENB | CSTOPB | CRTSCTS);
    tty.c_iflag &= ~(IXON | IXOFF | IXANY | ICRNL | INLCR);
    tty.c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);
    tty.c_oflag &= ~OPOST;
    tty.c_cc[VMIN] = 0; tty.c_cc[VTIME] = 0;
    if (tcsetattr(fd, TCSANOW, &tty)) { perror("tcsetattr"); return -1; }
    return 0;
}

static int open_serial(void)
{
    int fd = open(DEVICE, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd < 0) { perror("open " DEVICE); exit(EXIT_FAILURE); }
    if (configure_serial(fd) < 0) { close(fd); exit(EXIT_FAILURE); }
    dbg("[+] %s: 115200 8N1 raw\n", DEVICE);
    return fd;
}

static void send_pkt(int fd, const unsigned char *pkt, int n, const char *desc)
{
    hex_dump(desc, pkt, n);
    if (write(fd, pkt, n) != n) perror("write");
    usleep(120000);
}

static int timed_read(int fd, unsigned char *buf, int max, int timeout_sec)
{
    fd_set fds; struct timeval tv = { timeout_sec, 0 };
    FD_ZERO(&fds); FD_SET(fd, &fds);
    if (select(fd + 1, &fds, NULL, NULL, &tv) <= 0) return 0;
    int n = (int)read(fd, buf, max);
    return n > 0 ? n : 0;
}

/* ──────────────────────────── RX frame engine ───────────────────── */

static unsigned char _rxbuf[2048];
static int           _rxlen = 0;

static void rx_push(const unsigned char *d, int n)
{
    if (_rxlen + n > (int)sizeof(_rxbuf)) {
        int drop = _rxlen + n - (int)sizeof(_rxbuf);
        memmove(_rxbuf, _rxbuf + drop, _rxlen - drop);
        _rxlen -= drop;
    }
    memcpy(_rxbuf + _rxlen, d, n);
    _rxlen += n;
}

static void rx_clear(void) { _rxlen = 0; }

static int scan_for(unsigned char code, unsigned char *body, int *body_len)
{
    int i;
    for (i = 0; i + 7 <= _rxlen; i++) {
        if (_rxbuf[i] != 0x55 || _rxbuf[i+1] != 0xAA || _rxbuf[i+2] != 0x53)
            continue;

        unsigned char plen = _rxbuf[i+3];
        if (plen < 0x70) {
            int tot = plen + 4;
            if (i + tot <= _rxlen) {
                unsigned short csc = pkt_sum(_rxbuf + i, tot - 2);
                unsigned short csr = ((unsigned short)_rxbuf[i+tot-2] << 8) | _rxbuf[i+tot-1];
                if (csc == csr && _rxbuf[i+4] == code) {
                    if (body && body_len) {
                        int bl = tot - 7;
                        *body_len = (bl > 0 && bl <= 64) ? bl : 0;
                        if (*body_len) memcpy(body, _rxbuf + i + 5, *body_len);
                    }
                    memmove(_rxbuf, _rxbuf + i + tot, _rxlen - i - tot);
                    _rxlen -= i + tot;
                    return 1;
                }
            }
        }

        {
            unsigned short csc = pkt_sum(_rxbuf + i, 5);
            unsigned short csr = ((unsigned short)_rxbuf[i+5] << 8) | _rxbuf[i+6];
            if (csc == csr && _rxbuf[i+3] == code) {
                memmove(_rxbuf, _rxbuf + i + 7, _rxlen - i - 7);
                _rxlen -= i + 7;
                return 1;
            }
        }
    }
    return 0;
}

static int wait_for(int fd, unsigned char code, int timeout_sec,
                    unsigned char *body, int *body_len, const char *ctx)
{
    dbg("[.] Waiting 0x%02X [%s] (%ds)\n", code, ctx, timeout_sec);
    time_t deadline = time(NULL) + timeout_sec;
    while (time(NULL) < deadline) {
        unsigned char tmp[256];
        int n = timed_read(fd, tmp, sizeof(tmp), 1);
        if (n > 0) { hex_dump("  ← RX", tmp, n); rx_push(tmp, n); }
        if (scan_for(code, body, body_len)) {
            dbg("[+] Got 0x%02X [%s]\n", code, ctx);
            return 1;
        }
    }
    dbg("[!] Timeout 0x%02X [%s]\n", code, ctx);
    return 0;
}

/* ──────────────────────────── protocol primitives ───────────────── */

static void do_init(int fd) {
    unsigned char p[] = {0xFF}, pkt[16];
    int n = build_pkt(pkt, 0x14, p, 1);
    send_pkt(fd, pkt, n, "→ SUB1G_INIT (0x14)");
    wait_for(fd, 0x14, 2, NULL, NULL, "INIT ACK");
}

static void do_delete_all(int fd) {
    unsigned char pkt[16];
    int n = build_pkt(pkt, 0x3F, NULL, 0);
    send_pkt(fd, pkt, n, "→ DELETE_ALL (0x3F)");
    wait_for(fd, 0x3F, 2, NULL, NULL, "DELETE ACK");
}

static void do_start_pairing(int fd) {
    unsigned char p[] = {0x01}, pkt[16];
    int n = build_pkt(pkt, 0x1C, p, 1);
    send_pkt(fd, pkt, n, "→ START_PAIRING (0x1C 01)");
    wait_for(fd, 0x1C, 2, NULL, NULL, "START ACK");
}

static void do_stop_pairing(int fd) {
    unsigned char p[] = {0x00}, pkt[16];
    int n = build_pkt(pkt, 0x1C, p, 1);
    send_pkt(fd, pkt, n, "→ STOP_PAIRING (0x1C 00)");
    wait_for(fd, 0x1C, 2, NULL, NULL, "STOP ACK");
}

static void do_challenge(int fd, const unsigned char *mac8) {
    unsigned char payload[24], pkt[48];
    memcpy(payload,     mac8,        8);
    memcpy(payload + 8, CHALLENGE_R, 16);
    int n = build_pkt(pkt, 0x21, payload, 24);
    send_pkt(fd, pkt, n, "→ CHALLENGE (0x21)");
}

static void do_verify(int fd, const unsigned char *mac8) {
    unsigned char payload[10], pkt[32];
    memcpy(payload, mac8, 8);
    payload[8] = 0xFF; payload[9] = 0x04;
    int n = build_pkt(pkt, 0x23, payload, 10);
    send_pkt(fd, pkt, n, "→ VERIFY_RESULT (0x23)");
}

/* ─────────────────── chime JSON persistence ─────────────────────── */

static void chime_store(const char *name, const unsigned char *mac8)
{
    char mac_str[20], id[MAC_ID_LEN + 1], key[64];

    mac8_to_str(mac8, mac_str);
    mac8_to_id(mac8, id);

    snprintf(key, sizeof(key), "chime.units.%s.name", id);
    jct_config_set(key, name);

    chime_group_add("all", id);

    printf("Stored chime '%s' (%s) [%s]\n", name, mac_str, id);

    /* Stop the no-chime alarm if running */
    {
        FILE *pf = fopen("/run/doorbell_alarm.pid", "r");
        if (pf) {
            int pid;
            if (fscanf(pf, "%d", &pid) == 1 && pid > 0)
                kill(pid, SIGTERM);
            fclose(pf);
            unlink("/run/doorbell_alarm.pid");
        }
        system("led off 2>/dev/null");
    }
}

/* ──────────────────── high-level commands ───────────────────────── */

static void cmd_pair(int fd, const char *name, const unsigned char *mac8_hint)
{
    unsigned char mac8[8], body[64];
    int body_len = 0, got_mac = 0;

    if (name && name[0]) {
        const char *existing_id = chime_id_by_name(name);
        if (existing_id) {
            fprintf(stderr,
                    "Note: chime '%s' already exists (ID %s).\n"
                    "Use -D to clear radio pairings first if the chime was\n"
                    "factory-reset (hold button 10+ s until fast blue flash).\n"
                    "Without -D, the existing radio pairing is reused.\n\n",
                    name, existing_id);
        }
    }

    printf("1. Hold button until LED slowly flashes blue (~3-4 s).\n");
    printf("2. Press ENTER when LED is slowly flashing blue...\n");
    getchar();

    rx_clear();

    dbg("── [1] SUB1G_INIT ──\n");
    do_init(fd);

    if (do_delete) {
        dbg("── [2] DELETE_ALL ──\n");
        do_delete_all(fd);
        usleep(400000);
    }

    dbg("── [3] START_PAIRING ──\n");
    do_start_pairing(fd);
    usleep(400000);

    printf("Waiting for chime (45 s)... LED should be slowly flashing blue.\n");
    if (wait_for(fd, 0x20, 45, body, &body_len, "CHIME_ANNOUNCE")) {
        if (body_len >= 9) {
            memcpy(mac8, body + 1, 8);
            got_mac = 1;
            dbg("[+] MAC from 0x20: %.8s\n", mac8);
        }
    }

    if (!got_mac) {
        if (mac8_hint) {
            memcpy(mac8, mac8_hint, 8);
            dbg("[!] No 0x20 — using provided MAC fallback\n");
        } else {
            fprintf(stderr, "Error: no chime announcement and no MAC given.\n");
            do_stop_pairing(fd);
            return;
        }
    }

    dbg("── [5] CHALLENGE ──\n");
    do_challenge(fd, mac8);

    dbg("── [6] Waiting 0x22 CHALLENGE_RESP ──\n");
    if (!wait_for(fd, 0x22, 10, NULL, NULL, "CHALLENGE_RESP"))
        dbg("[!] No 0x22 — proceeding\n");

    dbg("── [7] VERIFY_RESULT ──\n");
    do_verify(fd, mac8);
    wait_for(fd, 0x23, 5, NULL, NULL, "VERIFY ACK");

    dbg("── [8] STOP_PAIRING ──\n");
    do_stop_pairing(fd);

    printf("Done! Listen for the success tone from the chime.\n");

    if (name && name[0]) {
        chime_store(name, mac8);
    } else {
        char auto_name[16];
        snprintf(auto_name, sizeof(auto_name), "chime_%c%c%c%c",
                 mac8[4], mac8[5], mac8[6], mac8[7]);
        chime_store(auto_name, mac8);
    }
}

static void cmd_list(FILE *out)
{
    char *ids[MAX_CHIMES];
    int count = jct_list_chime_ids(ids, MAX_CHIMES);
    int i;

    if (count == 0) {
        fprintf(out, "No chimes configured.\n");
        return;
    }

    fprintf(out, "Chimes (%d):\n", count);
    for (i = 0; i < count; i++) {
        const char *nm = chime_get_name(ids[i]);
        char mac_str[20];
        id_to_mac_str(ids[i], mac_str);
        fprintf(out, "  %-16s %s  [%s]\n",
                nm ? nm : "(unnamed)", mac_str, ids[i]);
    }

    fprintf(out, "\nGroups:\n");
    {
        char *group_names[MAX_CHIMES];
        int gcount = list_group_names(group_names, MAX_CHIMES);
        int g;
        if (gcount == 0) {
            fprintf(out, "  (none)\n");
        } else {
            for (g = 0; g < gcount; g++) {
                char *members[MAX_CHIMES];
                int mcount = chime_group_members_list(group_names[g],
                                                      members, MAX_CHIMES);
                int m;
                fprintf(out, "  %-16s ", group_names[g]);
                for (m = 0; m < mcount; m++) {
                    const char *nm = chime_get_name(members[m]);
                    if (m > 0) fputs(", ", out);
                    if (nm) fputs(nm, out);
                    else fputs(members[m], out);
                    free(members[m]);
                }
                fputc('\n', out);
                free(group_names[g]);
            }
        }
    }

    free_id_list(ids, count);
}

static void cmd_unpair(const char *arg)
{
    char id[MAC_ID_LEN + 1];
    unsigned char mac8[8];

    if (chime_resolve(arg, id, mac8) < 0) {
        fprintf(stderr, "Chime '%s' not found.\n", arg);
        return;
    }

    printf("Removing chime '%s' [%s]\n",
           chime_get_name(id) ? chime_get_name(id) : id, id);

    /* Remove from config */
    {
        char key[64];
        snprintf(key, sizeof(key), "chime.units.%s", id);
        jct_config_remove(key);
    }

    /* Remove from all groups */
    {
        char *group_names[MAX_CHIMES];
        int gcount = list_group_names(group_names, MAX_CHIMES);
        int g;
        for (g = 0; g < gcount; g++) {
            chime_group_remove(group_names[g], id);
            free(group_names[g]);
        }
    }
}

static void cmd_play(int fd, const unsigned char *mac8,
                     int sound, int volume, int repeat)
{
    unsigned char payload[11], pkt[32];
    memcpy(payload, mac8, 8);
    payload[8]  = (unsigned char)sound;
    payload[9]  = (unsigned char)repeat;
    payload[10] = (unsigned char)volume;
    int n = build_pkt(pkt, 0x70, payload, 11);
    send_pkt(fd, pkt, n, "→ PLAY (0x70)");
    wait_for(fd, 0x70, 3, NULL, NULL, "PLAY ACK");
}

static void cmd_play_all(int fd, int sound, int volume, int repeat)
{
    char *ids[MAX_CHIMES];
    int count = jct_list_chime_ids(ids, MAX_CHIMES);
    int i;

    if (count == 0) {
        fprintf(stderr, "No chimes configured.\n");
        return;
    }

    for (i = 0; i < count; i++) {
        unsigned char mac8[8];
        if (id_to_mac8(ids[i], mac8) == 0) {
            printf("Playing %s [%s]...\n",
                   chime_get_name(ids[i]) ? chime_get_name(ids[i]) : ids[i],
                   ids[i]);
            cmd_play(fd, mac8, sound, volume, repeat);
            usleep(500000);
        }
    }
    free_id_list(ids, count);
}

static void cmd_play_group(int fd, const char *group_name,
                           int sound, int volume, int repeat)
{
    char *members[MAX_CHIMES];
    int count = chime_group_members_list(group_name, members, MAX_CHIMES);
    int i;

    if (count == 0) {
        fprintf(stderr, "Group '%s' not found or empty.\n", group_name);
        return;
    }

    for (i = 0; i < count; i++) {
        unsigned char mac8[8];
        if (id_to_mac8(members[i], mac8) == 0) {
            const char *nm = chime_get_name(members[i]);
            printf("Playing %s [%s]...\n",
                   nm ? nm : members[i], members[i]);
            cmd_play(fd, mac8, sound, volume, repeat);
            usleep(500000);
        } else {
            fprintf(stderr, "Warning: chime '%s' (in group '%s') not found.\n",
                    members[i], group_name);
        }
        free(members[i]);
    }
}

/* ──────────────────────────── help ─────────────────────────────── */

static void usage(const char *prog)
{
    printf("Wyze Doorbell V1 Chime Controller\n\n");
    printf("Usage:\n");
    printf("  %s [-d] [-D] pair [<NAME>] [<MAC>]       # pair and store\n", prog);
    printf("  %s [-d] list                              # list stored chimes\n", prog);
    printf("  %s [-d] unpair <NAME|MAC|ID>              # remove from config\n", prog);
    printf("  %s [-d] <NAME|ID> <SOUND> [VOL] [REP]     # play on one chime\n", prog);
    printf("  %s [-d] play <NAME|ID> <SOUND> [VOL] [REP]\n", prog);
    printf("  %s [-d] play-all <SOUND> [VOL] [REP]      # play on all chimes\n", prog);
    printf("  %s [-d] play-group <GROUP> <SOUND> [VOL] [REP]\n", prog);
    printf("  %s [-d] init|delete|start|stop            # low-level commands\n", prog);
    printf("  %s [-d] challenge|verify <MAC>            # pairing steps\n", prog);
    printf("\nOptions:\n");
    printf("  -d, --debug    Show TX/RX hex dumps\n");
    printf("  -D, --delete   Clear radio pairings before pairing\n");
    printf("  -h, --help     Show this help\n");
    printf("\nNAME: alphanumeric label (stored in thingino.json)\n");
    printf("ID:   8-char hex MAC without colons, e.g. 77DA39F9\n");
    printf("MAC:  XX:XX:XX:XX colon format; detected by ':'\n");
    printf("VOLUME default=%d (1-32), REPEAT default=%d (1-255)\n\n",
           DEFAULT_VOLUME, DEFAULT_REPEAT);
    printf("Sounds (name or number 1-19):\n");
    printf("  SPACE_WAVE(1)   WIND_CHIME(2)  CURIOSITY(3)   SURPRISE(4)   CHEERFUL(5)\n");
    printf("  DOORBELL_1(6)   DOORBELL_2(7)  DOORBELL_3(8)  DOORBELL_4(9) BIRD_CHIRP(10)\n");
    printf("  DOG_BARK_1(11)  DOG_BARK_2(12) DOOR_CLOSE(13) DOOR_OPEN(14) SIMPLE_1(15)\n");
    printf("  SIMPLE_2(16)    SIMPLE_3(17)   SIMPLE_4(18)   INTRUDER(19)\n\n");
    printf("Examples:\n");
    printf("  %s pair living_room            # pair and store as 'living_room'\n", prog);
    printf("  %s list                        # show all stored chimes\n", prog);
    printf("  %s living_room DOORBELL_1 5 2  # play via name\n", prog);
    printf("  %s play-all 6 5 2              # DOORBELL_1 on all chimes\n", prog);
    printf("  %s play-group daytime 6 5 2    # DOORBELL_1 on daytime group\n", prog);
    printf("  %s unpair kitchen              # remove kitchen from config\n", prog);
    printf("  %s -D pair basement            # delete all pairings, then pair\n", prog);
}

/* ──────────────────────────── main ─────────────────────────────── */

int main(int argc, char **argv)
{
    const char *prog = argv[0];
    int pair_flag = 0;

    while (argc > 1) {
        if      (!strcmp(argv[1], "-d") || !strcmp(argv[1], "--debug"))  debug_mode = 1;
        else if (!strcmp(argv[1], "-D") || !strcmp(argv[1], "--delete")) do_delete  = 1;
        else if (!strcmp(argv[1], "-p") || !strcmp(argv[1], "--pair"))   pair_flag  = 1;
        else if (!strcmp(argv[1], "-h") || !strcmp(argv[1], "--help"))
            { usage(prog); return EXIT_SUCCESS; }
        else break;
        argc--; argv++;
    }

    if (argc < 2) { usage(prog); return EXIT_FAILURE; }

    if (!strcmp(argv[1], "list")) {
        cmd_list(stdout);
        return EXIT_SUCCESS;
    }

    if (!strcmp(argv[1], "unpair")) {
        if (argc < 3) {
            fprintf(stderr, "%s: unpair requires a name, MAC, or ID\n", prog);
            return EXIT_FAILURE;
        }
        cmd_unpair(argv[2]);
        return EXIT_SUCCESS;
    }

    {
        const char *cmd = argv[1];
        int is_cmd = !looks_like_mac(cmd);
        int fd = open_serial();

        unsigned char mac8_hint[8];
        int have_hint_mac = 0;
        int i;
        for (i = 2; i < argc; i++) {
            if (looks_like_mac(argv[i])) {
                if (parse_mac(argv[i], mac8_hint) == 0) {
                    have_hint_mac = 1;
                    break;
                }
            }
        }

        if (pair_flag || (is_cmd && !strcmp(cmd, "pair"))) {
            const char *name = NULL;
            for (i = 2; i < argc; i++) {
                if (!looks_like_mac(argv[i])) {
                    name = argv[i];
                    break;
                }
            }
            cmd_pair(fd, name, have_hint_mac ? mac8_hint : NULL);

        } else if (is_cmd && !strcmp(cmd, "play")) {
            unsigned char mac8[8];
            if (argc < 3) {
                fprintf(stderr, "%s: play requires NAME|ID and SOUND\n", prog);
                close(fd); return EXIT_FAILURE;
            }
            if (chime_resolve(argv[2], NULL, mac8) < 0) {
                fprintf(stderr, "%s: unknown chime '%s'\n", prog, argv[2]);
                close(fd); return EXIT_FAILURE;
            }
            {
                int sound = resolve_sound(argv[3]);
                int vol, rep;
                if (sound < 1) {
                    fprintf(stderr, "%s: invalid sound '%s'\n", prog, argv[3]);
                    close(fd); return EXIT_FAILURE;
                }
                vol = (argc >= 5) ? atoi(argv[4]) : DEFAULT_VOLUME;
                rep = (argc >= 6) ? atoi(argv[5]) : DEFAULT_REPEAT;
                if (vol < 1 || vol > 32) {
                    fprintf(stderr, "%s: volume %d out of range (1-32)\n", prog, vol);
                    close(fd); return EXIT_FAILURE;
                }
                if (rep < 1 || rep > 255) {
                    fprintf(stderr, "%s: repeat %d out of range (1-255)\n", prog, rep);
                    close(fd); return EXIT_FAILURE;
                }
                cmd_play(fd, mac8, sound, vol, rep);
            }

        } else if (is_cmd && !strcmp(cmd, "play-all")) {
            int sound, vol, rep;
            if (argc < 3) {
                fprintf(stderr, "%s: play-all requires SOUND\n", prog);
                close(fd); return EXIT_FAILURE;
            }
            sound = resolve_sound(argv[2]);
            if (sound < 1) {
                fprintf(stderr, "%s: invalid sound '%s'\n", prog, argv[2]);
                close(fd); return EXIT_FAILURE;
            }
            vol = (argc >= 4) ? atoi(argv[3]) : DEFAULT_VOLUME;
            rep = (argc >= 5) ? atoi(argv[4]) : DEFAULT_REPEAT;
            cmd_play_all(fd, sound, vol, rep);

        } else if (is_cmd && !strcmp(cmd, "play-group")) {
            int sound, vol, rep;
            if (argc < 4) {
                fprintf(stderr, "%s: play-group requires GROUP and SOUND\n", prog);
                close(fd); return EXIT_FAILURE;
            }
            sound = resolve_sound(argv[3]);
            if (sound < 1) {
                fprintf(stderr, "%s: invalid sound '%s'\n", prog, argv[3]);
                close(fd); return EXIT_FAILURE;
            }
            vol = (argc >= 5) ? atoi(argv[4]) : DEFAULT_VOLUME;
            rep = (argc >= 6) ? atoi(argv[5]) : DEFAULT_REPEAT;
            cmd_play_group(fd, argv[2], sound, vol, rep);

        } else if (is_cmd && !strcmp(cmd, "init")) {
            do_init(fd);
            printf("sub-GHz radio initialised.\n");
        } else if (is_cmd && !strcmp(cmd, "delete")) {
            do_delete_all(fd);
            printf("All pairings deleted.\n");
        } else if (is_cmd && !strcmp(cmd, "start")) {
            do_start_pairing(fd);
            printf("Pairing mode started.\n");
        } else if (is_cmd && !strcmp(cmd, "stop")) {
            do_stop_pairing(fd);
            printf("Pairing mode stopped.\n");
        } else if (is_cmd && !strcmp(cmd, "challenge")) {
            if (!have_hint_mac) {
                fprintf(stderr, "%s: challenge requires a MAC\n", prog);
                close(fd); return EXIT_FAILURE;
            }
            do_challenge(fd, mac8_hint);
            printf("Challenge sent.\n");
        } else if (is_cmd && !strcmp(cmd, "verify")) {
            if (!have_hint_mac) {
                fprintf(stderr, "%s: verify requires a MAC\n", prog);
                close(fd); return EXIT_FAILURE;
            }
            do_verify(fd, mac8_hint);
            printf("Verify-result sent.\n");

        } else {
            unsigned char mac8[8];
            int sound, vol, rep;
            if (chime_resolve(argv[1], NULL, mac8) < 0) {
                fprintf(stderr, "%s: unknown chime '%s'\n", prog, argv[1]);
                close(fd); return EXIT_FAILURE;
            }
            if (argc < 3) {
                fprintf(stderr, "Usage: %s <NAME|ID> <SOUND> [VOLUME] [REPEAT]\n", prog);
                close(fd); return EXIT_FAILURE;
            }
            sound = resolve_sound(argv[2]);
            if (sound < 1) {
                fprintf(stderr, "%s: invalid sound '%s'\n", prog, argv[2]);
                close(fd); return EXIT_FAILURE;
            }
            vol = (argc >= 4) ? atoi(argv[3]) : DEFAULT_VOLUME;
            rep = (argc >= 5) ? atoi(argv[4]) : DEFAULT_REPEAT;
            if (vol < 1 || vol > 32) {
                fprintf(stderr, "%s: volume %d out of range (1-32)\n", prog, vol);
                close(fd); return EXIT_FAILURE;
            }
            if (rep < 1 || rep > 255) {
                fprintf(stderr, "%s: repeat %d out of range (1-255)\n", prog, rep);
                close(fd); return EXIT_FAILURE;
            }
            cmd_play(fd, mac8, sound, vol, rep);
        }

        close(fd);
    }

    return EXIT_SUCCESS;
}
