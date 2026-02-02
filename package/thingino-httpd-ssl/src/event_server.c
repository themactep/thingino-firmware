#include "mbedtls/error.h"
#include "mbedtls/net_sockets.h"
#include "mbedtls/ssl.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/types.h>

// Local HTTP backend
#define HTTP_HOST "127.0.0.1"
#define HTTP_PORT "80"

// I/O buffering
#define RBUF_SIZE (64 * 1024)
#define TMP_READ 4096
#define BUFFER_SIZE 16384

extern volatile int keep_running;

typedef struct {
    unsigned char buf[RBUF_SIZE];
    size_t head, tail, len;
} ring_t;

static inline void rb_init(ring_t* rb)
{
    rb->head = rb->tail = rb->len = 0;
}
static inline size_t rb_space(const ring_t* rb)
{
    return RBUF_SIZE - rb->len;
}
static inline size_t rb_size(const ring_t* rb)
{
    return rb->len;
}
static size_t rb_write(ring_t* rb, const unsigned char* src, size_t n)
{
    size_t w = 0, space = rb_space(rb);
    if (n > space)
        n = space;
    while (w < n) {
        size_t chunk = RBUF_SIZE - rb->head;
        if (chunk > n - w)
            chunk = n - w;
        memcpy(&rb->buf[rb->head], &src[w], chunk);
        rb->head = (rb->head + chunk) % RBUF_SIZE;
        rb->len += chunk;
        w += chunk;
    }
    return w;
}
static size_t rb_peek(const ring_t* rb, const unsigned char** p)
{
    if (rb->len == 0) {
        *p = NULL;
        return 0;
    }
    *p = &rb->buf[rb->tail];
    size_t chunk = RBUF_SIZE - rb->tail;
    if (chunk > rb->len)
        chunk = rb->len;
    return chunk;
}
static inline void rb_consume(ring_t* rb, size_t n)
{
    if (n > rb->len)
        n = rb->len;
    rb->tail = (rb->tail + n) % RBUF_SIZE;
    rb->len -= n;
}

// Connection state
typedef enum { C_INIT = 0, C_HANDSHAKE, C_HTTP_CONNECTING, C_FORWARD, C_SHUTDOWN, C_CLOSED } cstate_t;

typedef struct conn_s {
    cstate_t state;
    int tls_done;
    mbedtls_ssl_context ssl;
    mbedtls_net_context client_fd; // wraps tls fd
    int tls_fd;
    int http_fd;
    int http_connected; // 0=pending, 1=ok, -1=err
    ring_t to_http;     // TLS->HTTP
    ring_t to_tls;      // HTTP->TLS
    // trace helpers
    unsigned char prev4[4];
    size_t prev4_len;
    struct conn_s* next;
} conn_t;

static void set_nonblock(int fd)
{
    int fl = fcntl(fd, F_GETFL, 0);
    if (fl >= 0)
        fcntl(fd, F_SETFL, fl | O_NONBLOCK);
}
static void tcp_tune(int fd)
{
    int one = 1, sz = 65536;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &sz, sizeof(sz));
    setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sz, sizeof(sz));
}

static int http_connect_nb(void)
{
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0)
        return -1;
    tcp_tune(s);
    set_nonblock(s);
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(atoi(HTTP_PORT));
    inet_pton(AF_INET, HTTP_HOST, &addr.sin_addr);
    if (connect(s, (struct sockaddr*) &addr, sizeof(addr)) == 0)
        return s;
    if (errno == EINPROGRESS)
        return s;
    close(s);
    return -1;
}

static void close_conn(conn_t* c)
{
    if (!c)
        return;
    if (c->http_fd >= 0) {
        close(c->http_fd);
        c->http_fd = -1;
    }
    if (c->client_fd.fd >= 0) {
        mbedtls_net_free(&c->client_fd);
    }
    mbedtls_ssl_free(&c->ssl);
    c->state = C_CLOSED;
}

int run_event_server(mbedtls_net_context* listen_fd, mbedtls_ssl_config* conf)
{
    // Make listening socket non-blocking
    if (listen_fd && listen_fd->fd >= 0)
        set_nonblock(listen_fd->fd);

    // Simple singly-linked list of connections
    conn_t* head = NULL;

    // Connection cap (env or default 8)
    int max_conns = 8;
    const char* mc = getenv("HTTPD_SSL_MAX_CONNS");
    if (mc) {
        int v = atoi(mc);
        if (v >= 1 && v <= 64)
            max_conns = v;
    }

    // Options
    const char* trace_env = getenv("HTTPD_SSL_TRACE");
    int trace = (trace_env && (*trace_env == '1' || strcasecmp(trace_env, "true") == 0 || strcasecmp(trace_env, "on") == 0));
    const char* pt_env = getenv("HTTPD_SSL_PASSTHRU");
    int passthru = (pt_env && (*pt_env == '1' || strcasecmp(pt_env, "true") == 0 || strcasecmp(pt_env, "on") == 0));

    while (keep_running) {
        fd_set rfds, wfds;
        FD_ZERO(&rfds);
        FD_ZERO(&wfds);
        int maxfd = -1, conn_count = 0;

        // Accept readiness
        if (listen_fd && listen_fd->fd >= 0) {
            FD_SET(listen_fd->fd, &rfds);
            if (listen_fd->fd > maxfd)
                maxfd = listen_fd->fd;
        }

        // Build fd sets for connections
        for (conn_t* c = head; c; c = c->next) {
            if (c->state == C_CLOSED)
                continue;
            conn_count++;
            int tfd = c->client_fd.fd;
            int hfd = c->http_fd;
            if (tfd >= 0 && tfd > maxfd)
                maxfd = tfd;
            if (hfd >= 0 && hfd > maxfd)
                maxfd = hfd;

            // Always drive backend connect if not yet connected
            if (hfd >= 0 && !c->http_connected)
                FD_SET(hfd, &wfds);

            if (!c->tls_done) {
                if (tfd >= 0) {
                    FD_SET(tfd, &rfds);
                    FD_SET(tfd, &wfds);
                }
                continue;
            }

            // Forwarding phase (TLS handshake done)
            if (tfd >= 0 && rb_space(&c->to_http) > 0)
                FD_SET(tfd, &rfds);
            if (tfd >= 0 && rb_size(&c->to_tls) > 0)
                FD_SET(tfd, &wfds);
            if (hfd >= 0 && c->http_connected && rb_space(&c->to_tls) > 0)
                FD_SET(hfd, &rfds);
            if (hfd >= 0 && c->http_connected && rb_size(&c->to_http) > 0)
                FD_SET(hfd, &wfds);
        }

        struct timeval tv = {.tv_sec = 60, .tv_usec = 0};
        int n = select(maxfd + 1, &rfds, &wfds, NULL, &tv);
        if (n < 0) {
            if (errno == EINTR)
                continue;
            break;
        }

        // Accept new connections
        if (listen_fd && listen_fd->fd >= 0 && FD_ISSET(listen_fd->fd, &rfds)) {
            for (;;) {
                struct sockaddr_in cli;
                socklen_t cl = sizeof(cli);
                int cfd = accept(listen_fd->fd, (struct sockaddr*) &cli, &cl);
                if (cfd < 0) {
                    if (errno == EAGAIN || errno == EWOULDBLOCK)
                        break;
                    else
                        break;
                }
                if (conn_count >= max_conns) {
                    close(cfd);
                    break;
                }
                // Setup connection struct
                conn_t* c = (conn_t*) calloc(1, sizeof(conn_t));
                if (!c) {
                    close(cfd);
                    break;
                }
                c->state = C_INIT;
                c->tls_done = 0;
                c->prev4_len = 0;
                mbedtls_ssl_init(&c->ssl);
                mbedtls_net_init(&c->client_fd);
                c->client_fd.fd = cfd;
                c->tls_fd = cfd;
                set_nonblock(cfd);
                tcp_tune(cfd);
                rb_init(&c->to_http);
                rb_init(&c->to_tls);
                // Setup TLS
                if (mbedtls_ssl_setup(&c->ssl, conf) != 0) {
                    close_conn(c);
                    free(c);
                    continue;
                }
                mbedtls_ssl_set_bio(&c->ssl, &c->client_fd, mbedtls_net_send, mbedtls_net_recv, NULL);
                // Start backend connect
                c->http_fd = http_connect_nb();
                c->http_connected = 0;
                c->state = (c->http_fd < 0) ? C_SHUTDOWN : C_HANDSHAKE;
                // Push front
                c->next = head;
                head = c;
                conn_count++;
            }
        }

        // Drive all connections
        for (conn_t *c = head, *prev = NULL; c;) {
            int remove = 0; // flag to remove node
            int tfd = c->client_fd.fd, hfd = c->http_fd;

            // finalize backend connect
            if (hfd >= 0 && !c->http_connected && FD_ISSET(hfd, &wfds)) {
                int err = 0;
                socklen_t el = sizeof(err);
                if (getsockopt(hfd, SOL_SOCKET, SO_ERROR, &err, &el) == 0 && err == 0) {
                    c->http_connected = 1;
                    if (trace)
                        fprintf(stderr, "[ev] backend connect OK fd=%d\n", hfd);
                } else {
                    if (trace)
                        fprintf(stderr, "[ev] backend connect err=%d\n", err);
                    c->state = C_SHUTDOWN;
                }
            }

            // TLS handshake step
            if (!c->tls_done && tfd >= 0 && (FD_ISSET(tfd, &rfds) || FD_ISSET(tfd, &wfds))) {
                int ret = mbedtls_ssl_handshake(&c->ssl);
                if (ret == 0) {
                    c->tls_done = 1;
                    if (trace)
                        fprintf(stderr, "[ev] tls handshake done fd=%d\n", tfd);
                } else if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) { /* wait */
                } else {
                    if (trace)
                        fprintf(stderr, "[ev] tls handshake fail ret=%d\n", ret);
                    c->state = C_SHUTDOWN;
                }
            }

            // Forwarding only when both sides ready
            if (c->tls_done && c->http_connected && c->state != C_SHUTDOWN) {
                // Prioritize draining writes first to minimize buffer pressure
                // HTTP writable -> drain to_http
                if (hfd >= 0 && FD_ISSET(hfd, &wfds) && rb_size(&c->to_http) > 0) {
                    for (;;) {
                        const unsigned char* p;
                        size_t n = rb_peek(&c->to_http, &p);
                        if (n == 0)
                            break;
                        int s = send(hfd, p, n, MSG_DONTWAIT);
                        if (s > 0) {
                            rb_consume(&c->to_http, (size_t) s);
                            continue;
                        }
                        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
                            break;
                        c->state = C_SHUTDOWN;
                        break;
                    }
                }
                // TLS writable -> drain to_tls
                if (tfd >= 0 && FD_ISSET(tfd, &wfds) && rb_size(&c->to_tls) > 0) {
                    for (;;) {
                        const unsigned char* p;
                        size_t n = rb_peek(&c->to_tls, &p);
                        if (n == 0)
                            break;
                        int w = mbedtls_ssl_write(&c->ssl, p, n);
                        if (w > 0) {
                            rb_consume(&c->to_tls, (size_t) w);
                            continue;
                        }
                        if (w == MBEDTLS_ERR_SSL_WANT_READ || w == MBEDTLS_ERR_SSL_WANT_WRITE)
                            break;
                        c->state = C_SHUTDOWN;
                        break;
                    }
                }
                // TLS readable -> to_http
                if (tfd >= 0 && FD_ISSET(tfd, &rfds)) {
                    for (;;) {
                        size_t space = rb_space(&c->to_http);
                        if (space == 0)
                            break;
                        unsigned char tmp[TMP_READ];
                        size_t toread = space < TMP_READ ? space : TMP_READ;
                        int r = mbedtls_ssl_read(&c->ssl, tmp, (unsigned int) toread);
                        if (r > 0) {
                            size_t w = rb_write(&c->to_http, tmp, (size_t) r);
                            if (trace && w != (size_t) r)
                                fprintf(stderr, "[ev] DROP tls->http wrote=%zu r=%d\n", w, r);
                            if (!mbedtls_ssl_check_pending(&c->ssl))
                                break;
                            continue;
                        }
                        if (r == 0) {
                            c->state = C_SHUTDOWN;
                            break;
                        }
                        if (r == MBEDTLS_ERR_SSL_WANT_READ || r == MBEDTLS_ERR_SSL_WANT_WRITE)
                            break;
                        c->state = C_SHUTDOWN;
                        break;
                    }
                }
                // HTTP readable -> to_tls
                if (hfd >= 0 && FD_ISSET(hfd, &rfds)) {
                    for (;;) {
                        size_t space = rb_space(&c->to_tls);
                        if (space == 0)
                            break;
                        unsigned char tmp[TMP_READ];
                        size_t toread = space < TMP_READ ? space : TMP_READ;
                        int r = recv(hfd, tmp, toread, MSG_DONTWAIT);
                        if (r > 0) {
                            if (trace) {
                                // Boundary detection
                                static const char bnd[] = "--prudyntmjpegboundary";
                                for (int i = 0; i < r; i++) {
                                    // check prev4 + tmp window prefix
                                    unsigned char wbuf[4 + TMP_READ];
                                    int wlen = 0;
                                    if (c->prev4_len > 0) {
                                        memcpy(wbuf, c->prev4, c->prev4_len);
                                        wlen = (int) c->prev4_len;
                                    }
                                    int rem = r - i;
                                    int cp = rem;
                                    if (cp > 64)
                                        cp = 64; // don't spam
                                    memcpy(wbuf + wlen, tmp + i, cp);
                                    wlen += cp;
                                    if (wlen >= (int) sizeof(bnd) - 1) {
                                        // simple substring search in small wbuf
                                        for (int k = 0; k <= wlen - ((int) sizeof(bnd) - 1); k++) {
                                            if (!memcmp(&wbuf[k], bnd, sizeof(bnd) - 1)) {
                                                fprintf(stderr, "[ev] BOUNDARY seen (i=%d rem=%d)\n", i, rem);
                                                break;
                                            }
                                        }
                                    }
                                    // update prev4 with next bytes
                                    if (cp >= 4) {
                                        memcpy(c->prev4, &tmp[i + cp - 4], 4);
                                        c->prev4_len = 4;
                                    } else {
                                        int need = 4 - cp;
                                        if (need > (int) c->prev4_len)
                                            need = (int) c->prev4_len;
                                        memmove(c->prev4, &c->prev4[c->prev4_len - need], need);
                                        memcpy(&c->prev4[need], &tmp[i], cp);
                                        c->prev4_len = need + cp;
                                    }
                                    break; // only first window per recv for noise control
                                }
                            }
                            if (passthru) {
                                size_t off = 0;
                                while (off < (size_t) r) {
                                    int w = mbedtls_ssl_write(&c->ssl, tmp + off, (size_t) r - off);
                                    if (w > 0) {
                                        off += (size_t) w;
                                        continue;
                                    }
                                    if (w == MBEDTLS_ERR_SSL_WANT_READ || w == MBEDTLS_ERR_SSL_WANT_WRITE) {
                                        // stash remainder into ring if space permits
                                        size_t rem = (size_t) r - off;
                                        size_t sp = rb_space(&c->to_tls);
                                        size_t wr = rb_write(&c->to_tls, tmp + off, rem);
                                        if (trace && wr != rem)
                                            fprintf(stderr, "[ev] DROP passthru stash rem=%zu wr=%zu sp=%zu\n", rem, wr, sp);
                                        break;
                                    }
                                    c->state = C_SHUTDOWN;
                                    break;
                                }
                            } else {
                                size_t w = rb_write(&c->to_tls, tmp, (size_t) r);
                                if (trace && w != (size_t) r)
                                    fprintf(stderr, "[ev] DROP http->tls wrote=%zu r=%d\n", w, r);
                            }
                            if ((size_t) r < toread)
                                break;
                            continue;
                        }
                        if (r == 0) {
                            c->state = C_SHUTDOWN;
                            break;
                        }
                        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
                            break;
                        c->state = C_SHUTDOWN;
                        break;
                    }
                }
            }

            if (c->state == C_SHUTDOWN) {
                close_conn(c);
                remove = 1;
            }

            if (remove) {
                conn_t* to_free = c;
                if (prev)
                    prev->next = c->next;
                else
                    head = c->next;
                c = c->next;
                free(to_free);
                continue;
            }

            prev = c;
            c = c->next;
        }
    }

    // Cleanup remaining
    for (conn_t* c = head; c;) {
        conn_t* n = c->next;
        close_conn(c);
        free(c);
        c = n;
    }
    return 0;
}
