/*
 * doorbell_chime.c – Wyze Doorbell V1 Chime Controller
 *
 * This is a superset of the original doorbell_chime and a drop-in
 * replacement for it.  The two commands end-users will call most are:
 *
 *   pair – full 8-step pairing sequence with the CC1310 sub-GHz radio
 *   play – trigger a sound/volume/repeat on an already-paired chime
 *
 * This implementation can also serve as a base for other Wyze sensors
 * that use the same serial protocol.
 *
 * Protocol (TX, host → device): AA 55 53 [LEN] [CMD] [payload] [CHK_HI][CHK_LO]
 * Protocol (RX, device → host): 55 AA 53 [LEN] [CMD] [payload] [CHK_HI][CHK_LO]
 *   LEN = payload_len + 1(cmd) + 2(cksum)
 *
 * Pairing sequence (reverse-engineered from WyzeSensePy / Wyze protocol):
 *   1. SUB1G_INIT       TX 0x14 0xFF
 *   2. DELETE_ALL       TX 0x3F           [optional: -D flag]
 *   3. START_PAIRING    TX 0x1C 0x01
 *   4. NOTIFY_SCAN   ← RX 0x20           chime broadcasts MAC when in pairing mode
 *   5. CHALLENGE        TX 0x21 <MAC8> <CHALLENGE_R[16]>
 *   6. CHALLENGE_RESP ← RX 0x22
 *   7. VERIFY_RESULT    TX 0x23 <MAC8> 0xFF 0x04
 *   8. STOP_PAIRING     TX 0x1C 0x00
 *
 * MAC wire format: 8 upper-case ASCII hex chars, no colons.
 *   Command line "77:AB:62:77" → wire bytes 0x37 0x37 0x41 0x42 0x36 0x32 0x37 0x37
 *   (each character's ASCII value, not the decoded byte value)
 *
 * Built by Buildroot via wyze-accessory.mk (WYZE_ACCESSORY_INSTALL_TARGET_CMDS_DOORBELL_CTRL)
 * using $(TARGET_CC) $(TARGET_CFLAGS).  For manual testing:
 *   mipsel-linux-gnu-gcc -march=mips32 -O2 -static \
 *     -fno-builtin -Wall -Wextra doorbell_chime.c -o doorbell_chime
 */
 
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
#define DEFAULT_VOLUME  5   /* 1–32 (device accepts up to ~32) */
#define DEFAULT_REPEAT  1   /* times to play */

/* 16-byte challenge R (from WyzeSensePy Scan()) */
static const unsigned char CHALLENGE_R[16] = {
    'O','k','5','H','P','N','Q','4','l','f','7','7','u','7','5','4'
};

static int debug_mode = 0;  /* -d / --debug */
static int do_delete  = 0;  /* -D / --delete: clear pairings before pair */

/* Print only when debug is on */
#define dbg(fmt, ...) do { if (debug_mode) printf(fmt, ##__VA_ARGS__); } while (0)

/* ──────────────────────────── MAC ──────────────────────────────── */

/*
 * Parse "XX:XX:XX:XX" → 8 upper-case ASCII hex chars (wire format).
 * E.g. "00:11:22:33" → {'0','0','1','1','2','2','3','3'}
 * Returns 0 on success, -1 on invalid input.
 */
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

/* A string containing ':' is treated as a MAC address. */
static int looks_like_mac(const char *s) { return !!strchr(s, ':'); }

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

/* Returns ID 1-19 for a sound name or decimal integer, -1 on error. */
static int resolve_sound(const char *arg)
{
    for (int i = 0; i < N_SOUNDS; i++)
        if (!strcmp(arg, SOUNDS[i].name)) return SOUNDS[i].id;
    char *end;
    long n = strtol(arg, &end, 10);
    return (*end == '\0' && n >= 1 && n <= 19) ? (int)n : -1;
}

/* ──────────────────────────── packet helpers ────────────────────── */

static void hex_dump(const char *lbl, const unsigned char *d, int n)
{
    if (!debug_mode) return;
    printf("%s [%d]:", lbl, n);
    for (int i = 0; i < n; i++) printf(" %02X", d[i]);
    printf("  |");
    for (int i = 0; i < n; i++) putchar(isprint(d[i]) ? d[i] : '.');
    putchar('\n');
}

static unsigned short pkt_sum(const unsigned char *d, int n)
{
    unsigned short s = 0;
    while (n--) s += *d++;
    return s;
}

/*
 * Build TX frame into buf: AA 55 53 [LEN=plen+3] [cmd] [payload] [CHK_HI][CHK_LO]
 * Returns total length.
 */
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
    tty.c_cc[VMIN] = 0; tty.c_cc[VTIME] = 0;  /* non-blocking reads */
    if (tcsetattr(fd, TCSANOW, &tty)) { perror("tcsetattr"); return -1; }
    return 0;
}

static int open_serial(void)
{
    /* O_RDWR: need to read responses; O_NONBLOCK: use select() for timeouts */
    int fd = open(DEVICE, O_RDWR | O_NOCTTY | O_NONBLOCK);
    if (fd < 0) { perror("open " DEVICE); exit(EXIT_FAILURE); }
    if (configure_serial(fd) < 0) { close(fd); exit(EXIT_FAILURE); }
    dbg("[+] %s: 115200 8N1 raw\n", DEVICE);
    return fd;
}

/* Send a packet; 120 ms settling time after write. */
static void send_pkt(int fd, const unsigned char *pkt, int n, const char *desc)
{
    hex_dump(desc, pkt, n);
    if (write(fd, pkt, n) != n) perror("write");
    usleep(120000);
}

/* Non-blocking read with select() timeout. */
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

/*
 * Scan accumulator for a packet matching 'code'.
 * RX magic: 55 AA 53
 *   NOTIFICATION: 55 AA 53 LEN code payload CHK_HI CHK_LO  (LEN < 0x70)
 *   ACK (7 bytes): 55 AA 53 code 00 CHK_HI CHK_LO
 * On match, consumes the frame and optionally fills body/body_len.
 */
static int scan_for(unsigned char code, unsigned char *body, int *body_len)
{
    for (int i = 0; i + 7 <= _rxlen; i++) {
        if (_rxbuf[i] != 0x55 || _rxbuf[i+1] != 0xAA || _rxbuf[i+2] != 0x53)
            continue;

        /* NOTIFICATION (length-prefixed) */
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

        /* ACK (7-byte fixed frame) */
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

/*
 * Wait up to timeout_sec for a specific response code.
 * Debug mode: prints wait/got/timeout messages + hex dumps.
 * Returns 1 on success, 0 on timeout.
 */
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

/* ──────────────────────────── high-level commands ───────────────── */

/*
 * cmd_pair: full 8-step pairing sequence.
 *   mac8_hint: 8-char ASCII fallback if 0x20 doesn't carry the MAC (may be NULL).
 *   do_delete:  global; when set, sends DELETE_ALL before START_PAIRING.
 */
static void cmd_pair(int fd, const unsigned char *mac8_hint)
{
    unsigned char mac8[8], body[64];
    int body_len = 0, got_mac = 0;

    /* Guide user to put chime in pairing mode */
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
    do_start_pairing(fd);
    usleep(400000);

    /* Step 4: wait up to 45 s for chime broadcast */
    printf("Waiting for chime (45 s)... LED should be slowly flashing blue.\n");
    if (wait_for(fd, 0x20, 45, body, &body_len, "CHIME_ANNOUNCE")) {
        /* Body layout: [1 unknown byte][8 ASCII MAC bytes][type][ver] */
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
}

/*
 * cmd_play: trigger a sound on an already-paired chime.
 * sound: 1-19, volume: 1-32, repeat: 1-255
 */
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

/* ──────────────────────────── help ─────────────────────────────── */

static void usage(const char *prog)
{
    printf("Wyze Doorbell V1 Chime Controller\n\n");
    printf("Usage:\n");
    printf("  %s [-d] [-D] pair|-p [<MAC>]              # full pairing\n", prog);
    printf("  %s [-d] <MAC> <SOUND> [VOLUME] [REPEAT]   # play (positional)\n", prog);
    printf("  %s [-d] play <MAC> <SOUND> [VOL] [REP]    # play (named)\n", prog);
    printf("  %s [-d] init|delete|start|stop            # low-level commands\n", prog);
    printf("  %s [-d] challenge|verify <MAC>            # pairing steps\n", prog);
    printf("\nOptions:\n");
    printf("  -d, --debug    Show TX/RX hex dumps and protocol steps\n");
    printf("  -D, --delete   Delete existing pairings before pairing\n");
    printf("  -h, --help     Show this help\n");
    printf("\nMAC: XX:XX:XX:XX (e.g. 00:11:22:33); detected by ':' in any argument.\n");
    printf("VOLUME default=%d (1-32), REPEAT default=%d (1-255)\n\n",
           DEFAULT_VOLUME, DEFAULT_REPEAT);
    printf("Sounds (name or number 1-19):\n");
    printf("  SPACE_WAVE(1)   WIND_CHIME(2)  CURIOSITY(3)   SURPRISE(4)   CHEERFUL(5)\n");
    printf("  DOORBELL_1(6)   DOORBELL_2(7)  DOORBELL_3(8)  DOORBELL_4(9) BIRD_CHIRP(10)\n");
    printf("  DOG_BARK_1(11)  DOG_BARK_2(12) DOOR_CLOSE(13) DOOR_OPEN(14) SIMPLE_1(15)\n");
    printf("  SIMPLE_2(16)    SIMPLE_3(17)   SIMPLE_4(18)   INTRUDER(19)\n\n");
    printf("Examples:\n");
    printf("  %s -p 00:11:22:33 # Pair with chime at MAC 00:11:22:33 \n", prog);
    printf("  %s 00:11:22:33 DOORBELL_1 5 2 # Play DOORBELL_1 sound at volume 5, repeat 2 times\n", prog);
    printf("  %s 00:11:22:33 15 8 # Play SIMPLE_1 sound at maximum volume\n", prog);
    printf("  %s -D pair 00:11:22:33    # pair, clearing old pairings first\n", prog);
}

/* ──────────────────────────── main ─────────────────────────────── */

int main(int argc, char **argv)
{
    const char *prog = argv[0];  /* save before argv++ shifts it */
    int pair_flag = 0;

    /* Strip leading option flags (all flags must precede the command/MAC) */
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

    /* Locate MAC address anywhere in the remaining args (detected by ':') */
    unsigned char mac8[8];
    int mac_idx = -1;
    for (int i = 1; i < argc; i++) {
        if (looks_like_mac(argv[i])) {
            if (parse_mac(argv[i], mac8) < 0) {
                fprintf(stderr, "%s: invalid MAC '%s'\n", prog, argv[i]);
                return EXIT_FAILURE;
            }
            mac_idx = i;
            break;
        }
    }
    int have_mac = (mac_idx >= 0);

    /* First non-flag arg: either a command word or a MAC (positional play) */
    const char *cmd = argv[1];
    int is_cmd = !looks_like_mac(cmd);  /* if not a MAC, it's a command word */

    int fd = open_serial();

    /* ── pair ─────────────────────────────────────────────────── */
    if (pair_flag ||
        (is_cmd && !strcmp(cmd, "pair"))) {
        cmd_pair(fd, have_mac ? mac8 : NULL);

    /* ── play (named) ─────────────────────────────────────────── */
    } else if (is_cmd && !strcmp(cmd, "play")) {
        if (!have_mac) {
            fprintf(stderr, "%s: play requires a MAC address\n", prog);
            close(fd); return EXIT_FAILURE;
        }
        int sound = -1, vol = DEFAULT_VOLUME, rep = DEFAULT_REPEAT, extra = 0;
        const char *sound_arg = NULL;  /* track for error message */
        for (int i = 2; i < argc; i++) {
            if (i == mac_idx) continue;
            if (extra == 0) {
                sound_arg = argv[i];
                sound = resolve_sound(argv[i]);
                extra++;
            } else if (extra == 1) { vol = atoi(argv[i]); extra++; }
            else if (extra == 2) { rep = atoi(argv[i]); extra++; }
        }
        if (sound < 1) {
            fprintf(stderr, "%s: invalid sound '%s' (use name or 1-19)\n",
                    prog, sound_arg ? sound_arg : "(missing)");
            close(fd); return EXIT_FAILURE;
        }
        if (vol < 1 || vol > 32) {
        fprintf(stderr, "%s: volume %d out of range (1-32)\n", prog, vol);
        close(fd); return EXIT_FAILURE;
        }
        if (rep < 1 || rep > 255) {
            fprintf(stderr, "%s: repeat %d out of range (1-255)\n", prog, rep);
            close(fd); return EXIT_FAILURE;
        }
        cmd_play(fd, mac8, sound, vol, rep);

    /* ── low-level standalone commands ───────────────────────── */
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
        if (!have_mac) { fprintf(stderr, "%s: challenge requires a MAC\n", prog); close(fd); return EXIT_FAILURE; }
        do_challenge(fd, mac8);
        printf("Challenge sent.\n");
    } else if (is_cmd && !strcmp(cmd, "verify")) {
        if (!have_mac) { fprintf(stderr, "%s: verify requires a MAC\n", prog); close(fd); return EXIT_FAILURE; }
        do_verify(fd, mac8);
        printf("Verify-result sent.\n");

    /* ── positional play: <MAC> <SOUND> [VOL] [REP] ─────────── */
    } else if (have_mac && mac_idx == 1) {
        if (argc < 3) {
            fprintf(stderr, "Usage: %s <MAC> <SOUND> [VOLUME] [REPEAT]\n", prog);
            close(fd); return EXIT_FAILURE;
        }
        int sound = resolve_sound(argv[2]);
        if (sound < 1) {
            fprintf(stderr, "%s: invalid sound '%s' (use name or 1-19)\n",
                    prog, argv[2]);
            close(fd); return EXIT_FAILURE;
        }
        int vol = (argc >= 4) ? atoi(argv[3]) : DEFAULT_VOLUME;
        int rep = (argc >= 5) ? atoi(argv[4]) : DEFAULT_REPEAT;
        if (vol < 1 || vol > 32) {
            fprintf(stderr, "%s: volume %d out of range (1-32)\n", prog, vol);
            close(fd); return EXIT_FAILURE;
        }
        if (rep < 1 || rep > 255) {
            fprintf(stderr, "%s: repeat %d out of range (1-255)\n", prog, rep);
            close(fd); return EXIT_FAILURE;
        }
        cmd_play(fd, mac8, sound, vol, rep);

    } else {
        fprintf(stderr, "%s: unknown command '%s' (try -h)\n", prog, cmd);
        close(fd); return EXIT_FAILURE;
    }

    close(fd);
    return EXIT_SUCCESS;
}
