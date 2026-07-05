/*
 * doorbell_chime.c – Wyze Doorbell V1 Chime Controller
 *
 * Chime persistence (thingino.json):
 *   { "chime": {
 *       "units":  { "<MAC_ID>": {"name":"..."}, ... },
 *       "groups": { "groupname": ["<MAC_ID>","<MAC_ID>"], ... },
 *       "events": { "eventname": { "sound":"...", ... }, ... }
 *   } }
 *
 * MAC_ID is the 8-char hex MAC without colons (e.g. "77DA39F9"); the
 * colon-form MAC is derived from it, not stored.  Groups reference
 * MAC_IDs, so renaming a chime never breaks groups.
 *
 * Requires jct with the 'del' command (>= 61c80e3).
 *
 * Built by Buildroot via wyze-accessory.mk.
 */

#define _DEFAULT_SOURCE   /* popen, strndup, usleep, mkstemp, kill, ... */

#include <errno.h>
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

/* Portable variadic form: the format is __VA_ARGS__'s first argument,
 * so no GNU ',##' extension is needed and it stays ISO C99-clean. */
#define dbg(...) do { if (debug_mode) printf(__VA_ARGS__); } while (0)

/* ──────────────────────────── MAC helpers ───────────────────────── */

static int parse_mac(const char *s, unsigned char *mac8)
{
    int j = 0;
    for (; *s; s++) {
        if (*s == ':') continue;
        if (!isxdigit((unsigned char)*s) || j >= 8) return -1;
        mac8[j++] = (unsigned char)toupper((unsigned char)*s);
    }
    return (j == 8) ? 0 : -1;
}

/* Recognise colon-separated MAC or 8-char hex MAC-ID: exactly 8 hex
 * digits, optionally colon-separated, nothing else. */
static int looks_like_mac(const char *s)
{
    int hex = 0;
    if (!strchr(s, ':') && strlen(s) != MAC_ID_LEN) return 0;
    for (; *s; s++) {
        if (*s == ':') continue;
        if (!isxdigit((unsigned char)*s)) return 0;
        hex++;
    }
    return hex == MAC_ID_LEN;
}

/*
 * Chime and group names end up in shell commands, JSONPath queries and
 * JSON patches: restrict them to [A-Za-z0-9_-] so no quoting or
 * escaping is ever needed.
 */
static int valid_name(const char *s)
{
    size_t n = 0;
    for (; s[n]; n++) {
        if (!isalnum((unsigned char)s[n]) && s[n] != '_' && s[n] != '-')
            return 0;
    }
    return n > 0 && n < MAX_NAME;
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

/* Import a JSON patch via a temp file.  Note: jct import exits 0 even
 * when the patch fails to parse, so callers must verify the result
 * themselves when it matters. */
static int jct_import_str(const char *json)
{
    char patch_path[] = "/tmp/jct_patch.XXXXXX";
    char cmd[512];
    int fd, rc;
    FILE *f;

    fd = mkstemp(patch_path);
    if (fd < 0) return -1;
    f = fdopen(fd, "w");
    if (!f) { close(fd); unlink(patch_path); return -1; }
    fprintf(f, "%s\n", json);
    if (fclose(f) != 0) { unlink(patch_path); return -1; }

    snprintf(cmd, sizeof(cmd), "jct %s import %s 2>/dev/null",
             CONFIG_FILE, patch_path);
    rc = system(cmd);
    unlink(patch_path);
    return (rc == 0) ? 0 : -1;
}

static int jct_val_is_empty(const char *val)
{
    return !val[0] || !strcmp(val, "null");
}

/*
 * Skip past the key separator in a jct path: either ".key" or
 * "['key']" / "[\"key\"]" (jct uses bracket notation when the key is
 * not a plain identifier, e.g. a MAC ID starting with a digit).
 * Returns pointer to the key, or NULL if neither form matches.
 */
static char *jct_path_key(char *p)
{
    if (*p == '.') return p + 1;
    if (p[0] == '[' && (p[1] == '\'' || p[1] == '"')) return p + 2;
    return NULL;
}

/*
 * Collect chime IDs (MAC IDs) from chime.units{} object keys.
 * Returns count, fills ids[] (caller must free each).
 */
static int jct_list_chime_ids(char **ids, int max_ids)
{
    char cmd[256], buf[4096], *p, *key, *end;
    FILE *pipe;
    int count = 0;

    snprintf(cmd, sizeof(cmd),
             "jct %s path '$.chime.units.*~' --mode paths 2>/dev/null",
             CONFIG_FILE);
    pipe = popen(cmd, "r");
    if (!pipe) return 0;

    {
        size_t got = fread(buf, 1, sizeof(buf) - 1, pipe);
        buf[got] = '\0';
    }
    pclose(pipe);

    p = buf;
    while (*p && count < max_ids) {
        p = strstr(p, "chime.units");
        if (!p) break;
        p += 11;  /* skip "chime.units" */
        key = jct_path_key(p);
        if (!key) continue;
        end = key + strcspn(key, "'\"]");
        if (end - key == MAC_ID_LEN) {
            int hex = 1, k;
            for (k = 0; k < MAC_ID_LEN; k++)
                if (!isxdigit((unsigned char)key[k])) hex = 0;
            /* only hex IDs: these keys are re-embedded in jct commands */
            if (hex) {
                ids[count] = strndup(key, MAC_ID_LEN);
                if (ids[count]) count++;
            }
        }
        p = end;
    }
    return count;
}

static void free_id_list(char **ids, int count)
{
    int i;
    for (i = 0; i < count; i++) free(ids[i]);
}

/*
 * Get a chime's name by MAC ID into caller buffer 'out' (>= MAX_NAME).
 * Returns 'out' on success, NULL if the unit has no name.  Writing into
 * a caller buffer (rather than a shared static) lets two names be held
 * live at once, e.g. in a single printf.
 */
static const char *chime_get_name(const char *id, char *out, size_t out_size)
{
    char key[64];
    snprintf(key, sizeof(key), "chime.units.%s.name", id);
    if (jct_config_read(key, out, out_size) < 0) return NULL;
    if (jct_val_is_empty(out)) return NULL;
    return out;
}

/*
 * Remove one unit from chime.units via jct's 'del' command, which
 * deletes exactly that key (json_object_object_del) and leaves every
 * other unit — and any fields they carry — untouched.  rm_id is a
 * validated hex MAC ID: safe to embed in the shell command, and free of
 * the '.' that del uses to split its dotted path.  Returns 0 if the
 * unit is gone afterwards.
 */
static int chime_units_remove(const char *rm_id)
{
    char cmd[128];
    char *ids[MAX_CHIMES];
    int count, i, still = 0;

    snprintf(cmd, sizeof(cmd), "jct %s del chime.units.%s 2>/dev/null",
             CONFIG_FILE, rm_id);
    if (system(cmd) != 0) return -1;

    /* del reports success even for an absent key; confirm it is gone. */
    count = jct_list_chime_ids(ids, MAX_CHIMES);
    for (i = 0; i < count; i++)
        if (!strcmp(ids[i], rm_id)) still = 1;
    free_id_list(ids, count);
    return still ? -1 : 0;
}

/*
 * Resolve a user-facing identifier (name, MAC-ID, or XX:XX:XX:XX)
 * to a MAC ID and wire-format MAC.  Returns 0 on success.
 */
static int chime_resolve(const char *arg, char *id_out, unsigned char *mac8)
{
    char id[MAC_ID_LEN + 1];

    /* 1. MAC or bare MAC-ID (8 hex digits) → strip to ID, derive mac8.
     * Anything else must NOT reach chime_get_name: it would be embedded
     * in a shell command. */
    if (looks_like_mac(arg)) {
        char nmbuf[MAX_NAME];
        mac_to_id(arg, id);
        if (chime_get_name(id, nmbuf, sizeof nmbuf)) {
            if (id_out) strcpy(id_out, id);
            return id_to_mac8(id, mac8);
        }
        return -1;
    }

    /* 2. search by name */
    {
        char *ids[MAX_CHIMES];
        char nmbuf[MAX_NAME];
        int count = jct_list_chime_ids(ids, MAX_CHIMES);
        int i;
        for (i = 0; i < count; i++) {
            const char *nm = chime_get_name(ids[i], nmbuf, sizeof nmbuf);
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
 * Find the MAC ID for a given name into 'id_out' (>= MAC_ID_LEN + 1;
 * may be NULL for an existence check).  Returns 0 if found, else -1.
 */
static int chime_id_by_name(const char *name, char *id_out)
{
    char *ids[MAX_CHIMES];
    char nmbuf[MAX_NAME];
    int count = jct_list_chime_ids(ids, MAX_CHIMES);
    int i, rc = -1;
    for (i = 0; i < count; i++) {
        const char *nm = chime_get_name(ids[i], nmbuf, sizeof nmbuf);
        if (nm && !strcmp(nm, name)) {
            if (id_out) strcpy(id_out, ids[i]);
            rc = 0;
            break;
        }
    }
    free_id_list(ids, count);
    return rc;
}

/* ──────────────────────────── groups ───────────────────────────── */

static int chime_group_members_list(const char *group_name,
                                    char **ids, int max_ids)
{
    char cmd[256], buf[4096], *p, *end;
    FILE *pipe;
    int count = 0;

    if (!valid_name(group_name)) return 0;
    snprintf(cmd, sizeof(cmd),
             "jct %s path \"$.chime.groups['%s'][*]\" --mode values 2>/dev/null",
             CONFIG_FILE, group_name);
    pipe = popen(cmd, "r");
    if (!pipe) return 0;

    {
        size_t got = fread(buf, 1, sizeof(buf) - 1, pipe);
        buf[got] = '\0';
    }
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
    char json[1024];
    int off, i;

    if (!valid_name(group_name)) return;
    off = snprintf(json, sizeof(json), "{\"chime\":{\"groups\":{\"%s\":[",
                   group_name);
    for (i = 0; i < count && off < (int)sizeof(json) - 16; i++)
        off += snprintf(json + off, sizeof(json) - (size_t)off,
                        "%s\"%s\"", i ? "," : "", ids[i]);
    snprintf(json + off, sizeof(json) - (size_t)off, "]}}}");
    jct_import_str(json);
}

static void chime_group_add(const char *group_name, const char *id)
{
    char *members[MAX_CHIMES];
    int count = chime_group_members_list(group_name, members, MAX_CHIMES);
    int i, found = 0;

    for (i = 0; i < count; i++) {
        if (!strcmp(members[i], id)) { found = 1; break; }
    }
    if (!found && count < MAX_CHIMES) {
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
    char cmd[256], buf[4096], *p, *key, *end;
    FILE *pipe;
    int gcount = 0;

    snprintf(cmd, sizeof(cmd),
             "jct %s path '$.chime.groups.*~' --mode paths 2>/dev/null",
             CONFIG_FILE);
    pipe = popen(cmd, "r");
    if (!pipe) return 0;

    {
        size_t got = fread(buf, 1, sizeof(buf) - 1, pipe);
        buf[got] = '\0';
    }
    pclose(pipe);
    p = buf;
    while (*p && gcount < max_names) {
        p = strstr(p, "chime.groups");
        if (!p) break;
        p += 12;  /* skip "chime.groups" */
        key = jct_path_key(p);
        if (!key) continue;
        end = key + strcspn(key, "'\"]");
        if (end - key > 0 && end - key < MAX_NAME) {
            names[gcount] = strndup(key, (size_t)(end - key));
            if (names[gcount]) gcount++;
        }
        p = end;
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
    char *end;
    long n;
    int i;
    for (i = 0; i < N_SOUNDS; i++)
        if (!strcmp(arg, SOUNDS[i].name)) return SOUNDS[i].id;
    n = strtol(arg, &end, 10);
    return (end != arg && *end == '\0' && n >= 1 && n <= N_SOUNDS)
           ? (int)n : -1;
}

/* Parse a decimal argument within [lo, hi]; -1 and a message on error. */
static int parse_int_arg(const char *s, int lo, int hi, const char *what)
{
    char *end;
    long n = strtol(s, &end, 10);
    if (end == s || *end != '\0' || n < lo || n > hi) {
        fprintf(stderr, "invalid %s '%s' (%d-%d)\n", what, s, lo, hi);
        return -1;
    }
    return (int)n;
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
    /* O_CLOEXEC: the fd must not leak into the jct/led children we
     * spawn via popen()/system() while it is open. */
    int fd = open(DEVICE, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) { perror("open " DEVICE); exit(EXIT_FAILURE); }
    if (configure_serial(fd) < 0) { close(fd); exit(EXIT_FAILURE); }
    dbg("[+] %s: 115200 8N1 raw\n", DEVICE);
    return fd;
}

/* The fd is O_NONBLOCK: handle partial writes and EAGAIN. */
static void send_pkt(int fd, const unsigned char *pkt, int n, const char *desc)
{
    int off = 0;
    hex_dump(desc, pkt, n);
    while (off < n) {
        ssize_t w = write(fd, pkt + off, (size_t)(n - off));
        if (w < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                usleep(5000);
                continue;
            }
            perror("write");
            break;
        }
        off += (int)w;
    }
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

static unsigned char rx_buf[2048];
static int           rx_len = 0;

static void rx_push(const unsigned char *d, int n)
{
    if (n <= 0) return;
    if (n >= (int)sizeof(rx_buf)) {         /* keep only the tail */
        d += n - (int)sizeof(rx_buf);
        n = (int)sizeof(rx_buf);
        rx_len = 0;
    }
    if (rx_len + n > (int)sizeof(rx_buf)) {
        int drop = rx_len + n - (int)sizeof(rx_buf);
        memmove(rx_buf, rx_buf + drop, (size_t)(rx_len - drop));
        rx_len -= drop;
    }
    memcpy(rx_buf + rx_len, d, (size_t)n);
    rx_len += n;
}

static void rx_clear(void) { rx_len = 0; }

/*
 * Find and consume one frame with the given code.  Two RX formats:
 *   long:  55 AA 53 <plen> <code> <body...> <sum16>   (plen = body+3)
 *   ACK:   55 AA 53 <code> <flag> <sum16>             (7 bytes fixed)
 * Both are tried at each sync position; the checksum decides.  Frames
 * for other codes are left in the buffer for a later wait_for().
 */
static int scan_for(unsigned char code, unsigned char *body, int *body_len)
{
    int i;
    for (i = 0; i + 7 <= rx_len; i++) {
        if (rx_buf[i] != 0x55 || rx_buf[i+1] != 0xAA || rx_buf[i+2] != 0x53)
            continue;

        unsigned char plen = rx_buf[i+3];
        if (plen < 0x70) {
            int tot = plen + 4;
            if (i + tot <= rx_len) {
                unsigned short csc = pkt_sum(rx_buf + i, tot - 2);
                unsigned short csr = ((unsigned short)rx_buf[i+tot-2] << 8) | rx_buf[i+tot-1];
                if (csc == csr && rx_buf[i+4] == code) {
                    if (body && body_len) {
                        int bl = tot - 7;
                        *body_len = (bl > 0 && bl <= 64) ? bl : 0;
                        if (*body_len) memcpy(body, rx_buf + i + 5, *body_len);
                    }
                    memmove(rx_buf, rx_buf + i + tot, rx_len - i - tot);
                    rx_len -= i + tot;
                    return 1;
                }
            }
        }

        {
            unsigned short csc = pkt_sum(rx_buf + i, 5);
            unsigned short csr = ((unsigned short)rx_buf[i+5] << 8) | rx_buf[i+6];
            if (csc == csr && rx_buf[i+3] == code) {
                memmove(rx_buf, rx_buf + i + 7, rx_len - i - 7);
                rx_len -= i + 7;
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
    if (jct_config_set(key, name) < 0)
        fprintf(stderr, "Warning: failed to write %s\n", CONFIG_FILE);

    chime_group_add("all", id);

    printf("Stored chime '%s' (%s) [%s]\n", name, mac_str, id);

    /* Stop the no-chime alarm if running */
    {
        FILE *pf = fopen("/run/doorbell_alarm.pid", "r");
        if (pf) {
            int pid;
            if (fscanf(pf, "%d", &pid) == 1 && pid > 1)
                kill(pid, SIGTERM);
            fclose(pf);
            unlink("/run/doorbell_alarm.pid");
        }
        system("led off 2>/dev/null");
    }
}

/* ──────────────────── high-level commands ───────────────────────── */

/*
 * While a pairing is in progress the doorbell's sub-GHz radio is in
 * pairing mode; a bare Ctrl-C would leave it there.  Arm a handler over
 * that window that takes the radio back out before exiting.
 */
static volatile sig_atomic_t g_pair_fd = -1;

static void pair_abort(int sig)
{
    (void)sig;
    if (g_pair_fd >= 0) {
        /* async-signal-safe: pure build_pkt + a single write(), no stdio */
        unsigned char p = 0x00, pkt[16];
        int n = build_pkt(pkt, 0x1C, &p, 1);
        (void)!write((int)g_pair_fd, pkt, (size_t)n);
    }
    _exit(130);   /* 128 + SIGINT */
}

static void pair_set_handler(int fd, void (*h)(int))
{
    struct sigaction sa;
    sa.sa_handler = h;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    g_pair_fd = fd;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
}

static void pair_arm(int fd)   { pair_set_handler(fd, pair_abort); }
static void pair_disarm(void)  { pair_set_handler(-1, SIG_DFL); }

static int cmd_pair(int fd, const char *name, const unsigned char *mac8_hint)
{
    unsigned char mac8[8], body[64];
    int body_len = 0, got_mac = 0;

    /* The tool handles at most MAX_CHIMES units; a fuller config would
     * be truncated by the next unpair rebuild, so refuse up front.
     * Re-pairing an existing name overwrites and is always allowed. */
    {
        char *ids[MAX_CHIMES];
        int count = jct_list_chime_ids(ids, MAX_CHIMES);
        free_id_list(ids, count);
        if (count >= MAX_CHIMES &&
            !(name && name[0] && chime_id_by_name(name, NULL) == 0)) {
            fprintf(stderr, "Chime limit reached (%d); unpair one first.\n",
                    MAX_CHIMES);
            return -1;
        }
    }

    if (name && name[0]) {
        char existing_id[MAC_ID_LEN + 1];
        if (chime_id_by_name(name, existing_id) == 0) {
            fprintf(stderr,
                    "Note: chime '%s' already exists (ID %s).\n"
                    "Use -D to clear radio pairings first if the chime was\n"
                    "factory-reset (hold button 10+ s until fast blue flash).\n"
                    "Without -D, the existing radio pairing is reused.\n\n",
                    name, existing_id);
        }
    }

    printf("1. Unplug chime 10+ s, plug back in.\n");
    printf("2. Hold button until slow blue flash (~3-4 s).\n");
    printf("3. Press ENTER when LED is slowly flashing blue...\n");
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
    pair_arm(fd);          /* radio now enters pairing mode */
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
            pair_disarm();
            return -1;
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
    pair_disarm();         /* radio out of pairing mode */

    printf("Done! Listen for the success tone from the chime.\n");

    if (name && name[0]) {
        chime_store(name, mac8);
    } else {
        char auto_name[16];
        snprintf(auto_name, sizeof(auto_name), "chime_%c%c%c%c",
                 mac8[4], mac8[5], mac8[6], mac8[7]);
        chime_store(auto_name, mac8);
    }
    return 0;
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
        char nmbuf[MAX_NAME];
        const char *nm = chime_get_name(ids[i], nmbuf, sizeof nmbuf);
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
                    char nmbuf[MAX_NAME];
                    const char *nm = chime_get_name(members[m], nmbuf, sizeof nmbuf);
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

static int cmd_unpair(const char *arg)
{
    char id[MAC_ID_LEN + 1];
    unsigned char mac8[8];

    if (chime_resolve(arg, id, mac8) < 0) {
        /* also accept a stored but nameless ID */
        char *ids[MAX_CHIMES];
        int n, k, found = 0;
        if (looks_like_mac(arg)) {
            mac_to_id(arg, id);
            n = jct_list_chime_ids(ids, MAX_CHIMES);
            for (k = 0; k < n; k++)
                if (!strcmp(ids[k], id)) found = 1;
            free_id_list(ids, n);
        }
        if (!found) {
            fprintf(stderr, "Chime '%s' not found.\n", arg);
            return -1;
        }
    }

    {
        char nmbuf[MAX_NAME];
        const char *nm = chime_get_name(id, nmbuf, sizeof nmbuf);
        printf("Removing chime '%s' [%s]\n", nm ? nm : id, id);
    }

    if (chime_units_remove(id) < 0) {
        fprintf(stderr, "Failed to remove '%s' from %s\n", id, CONFIG_FILE);
        return -1;
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
    return 0;
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

static int cmd_play_all(int fd, int sound, int volume, int repeat)
{
    char *ids[MAX_CHIMES];
    int count = jct_list_chime_ids(ids, MAX_CHIMES);
    int i;

    if (count == 0) {
        fprintf(stderr, "No chimes configured.\n");
        return -1;
    }

    for (i = 0; i < count; i++) {
        unsigned char mac8[8];
        if (id_to_mac8(ids[i], mac8) == 0) {
            char nmbuf[MAX_NAME];
            const char *nm = chime_get_name(ids[i], nmbuf, sizeof nmbuf);
            printf("Playing %s [%s]...\n", nm ? nm : ids[i], ids[i]);
            cmd_play(fd, mac8, sound, volume, repeat);
            usleep(500000);
        }
    }
    free_id_list(ids, count);
    return 0;
}

static int cmd_play_group(int fd, const char *group_name,
                          int sound, int volume, int repeat)
{
    char *members[MAX_CHIMES];
    int count = chime_group_members_list(group_name, members, MAX_CHIMES);
    int i;

    if (count == 0) {
        fprintf(stderr, "Group '%s' not found or empty.\n", group_name);
        return -1;
    }

    for (i = 0; i < count; i++) {
        unsigned char mac8[8];
        if (id_to_mac8(members[i], mac8) == 0) {
            char nmbuf[MAX_NAME];
            const char *nm = chime_get_name(members[i], nmbuf, sizeof nmbuf);
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
    return 0;
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
    printf("  -p, --pair     Treat the arguments as a pair request\n");
    printf("  -h, --help     Show this help\n");
    printf("\nNAME: 1-%d chars of A-Za-z0-9_- (stored in thingino.json)\n",
           MAX_NAME - 1);
    printf("ID:   8-char hex MAC without colons, e.g. 77DA39F9\n");
    printf("MAC:  XX:XX:XX:XX colon format; detected by ':'\n");
    printf("VOLUME default=%d (1-8), REPEAT default=%d (1-255)\n\n",
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
        else if (argv[1][0] == '-') {
            fprintf(stderr, "%s: unknown option '%s'\n", prog, argv[1]);
            return EXIT_FAILURE;
        }
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
        return cmd_unpair(argv[2]) == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
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
            if (name && !valid_name(name)) {
                fprintf(stderr, "%s: invalid name '%s' (1-%d chars of A-Za-z0-9_-)\n",
                        prog, name, MAX_NAME - 1);
                close(fd); return EXIT_FAILURE;
            }
            if (cmd_pair(fd, name, have_hint_mac ? mac8_hint : NULL) < 0) {
                close(fd); return EXIT_FAILURE;
            }

        } else if (is_cmd && !strcmp(cmd, "play")) {
            unsigned char mac8[8];
            if (argc < 4) {
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
                vol = (argc >= 5) ? parse_int_arg(argv[4], 1, 8, "volume")
                                  : DEFAULT_VOLUME;
                rep = (argc >= 6) ? parse_int_arg(argv[5], 1, 255, "repeat")
                                  : DEFAULT_REPEAT;
                if (vol < 0 || rep < 0) { close(fd); return EXIT_FAILURE; }
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
            vol = (argc >= 4) ? parse_int_arg(argv[3], 1, 8, "volume")
                              : DEFAULT_VOLUME;
            rep = (argc >= 5) ? parse_int_arg(argv[4], 1, 255, "repeat")
                              : DEFAULT_REPEAT;
            if (vol < 0 || rep < 0) { close(fd); return EXIT_FAILURE; }
            if (cmd_play_all(fd, sound, vol, rep) < 0) {
                close(fd); return EXIT_FAILURE;
            }

        } else if (is_cmd && !strcmp(cmd, "play-group")) {
            int sound, vol, rep;
            if (argc < 4) {
                fprintf(stderr, "%s: play-group requires GROUP and SOUND\n", prog);
                close(fd); return EXIT_FAILURE;
            }
            if (!valid_name(argv[2])) {
                fprintf(stderr, "%s: invalid group '%s'\n", prog, argv[2]);
                close(fd); return EXIT_FAILURE;
            }
            sound = resolve_sound(argv[3]);
            if (sound < 1) {
                fprintf(stderr, "%s: invalid sound '%s'\n", prog, argv[3]);
                close(fd); return EXIT_FAILURE;
            }
            vol = (argc >= 5) ? parse_int_arg(argv[4], 1, 8, "volume")
                              : DEFAULT_VOLUME;
            rep = (argc >= 6) ? parse_int_arg(argv[5], 1, 255, "repeat")
                              : DEFAULT_REPEAT;
            if (vol < 0 || rep < 0) { close(fd); return EXIT_FAILURE; }
            if (cmd_play_group(fd, argv[2], sound, vol, rep) < 0) {
                close(fd); return EXIT_FAILURE;
            }

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
            vol = (argc >= 4) ? parse_int_arg(argv[3], 1, 8, "volume")
                              : DEFAULT_VOLUME;
            rep = (argc >= 5) ? parse_int_arg(argv[4], 1, 255, "repeat")
                              : DEFAULT_REPEAT;
            if (vol < 0 || rep < 0) { close(fd); return EXIT_FAILURE; }
            cmd_play(fd, mac8, sound, vol, rep);
        }

        close(fd);
    }

    return EXIT_SUCCESS;
}
