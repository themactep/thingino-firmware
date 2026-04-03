#include "mbedtls/net_sockets.h"
#include "mbedtls/ssl.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <arpa/inet.h>
#include <netinet/tcp.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/types.h>

#define RBUF_SIZE (64 * 1024)
#define TMP_READ 4096

extern const char *proxy_backend_host;
extern const char *proxy_backend_port;
extern volatile int keep_running;

typedef struct {
	unsigned char buf[RBUF_SIZE];
	size_t head;
	size_t tail;
	size_t len;
} ring_t;

typedef enum {
	C_INIT = 0,
	C_HANDSHAKE,
	C_SHUTDOWN,
	C_CLOSED
} cstate_t;

typedef struct conn_s {
	cstate_t state;
	int tls_done;
	mbedtls_ssl_context ssl;
	mbedtls_net_context client_fd;
	int http_fd;
	int http_connected;
	ring_t to_http;
	ring_t to_tls;
	struct conn_s *next;
} conn_t;

static void rb_init(ring_t *rb)
{
	rb->head = 0;
	rb->tail = 0;
	rb->len = 0;
}

static size_t rb_space(const ring_t *rb)
{
	return RBUF_SIZE - rb->len;
}

static size_t rb_size(const ring_t *rb)
{
	return rb->len;
}

static size_t rb_write(ring_t *rb, const unsigned char *src, size_t len)
{
	size_t written = 0;
	size_t space = rb_space(rb);

	if (len > space) {
		len = space;
	}
	while (written < len) {
		size_t chunk = RBUF_SIZE - rb->head;
		if (chunk > len - written) {
			chunk = len - written;
		}
		memcpy(&rb->buf[rb->head], &src[written], chunk);
		rb->head = (rb->head + chunk) % RBUF_SIZE;
		rb->len += chunk;
		written += chunk;
	}
	return written;
}

static size_t rb_peek(const ring_t *rb, const unsigned char **ptr)
{
	size_t chunk;

	if (rb->len == 0) {
		*ptr = NULL;
		return 0;
	}
	*ptr = &rb->buf[rb->tail];
	chunk = RBUF_SIZE - rb->tail;
	if (chunk > rb->len) {
		chunk = rb->len;
	}
	return chunk;
}

static void rb_consume(ring_t *rb, size_t len)
{
	if (len > rb->len) {
		len = rb->len;
	}
	rb->tail = (rb->tail + len) % RBUF_SIZE;
	rb->len -= len;
}

static void set_nonblock(int fd)
{
	int flags = fcntl(fd, F_GETFL, 0);

	if (flags >= 0) {
		fcntl(fd, F_SETFL, flags | O_NONBLOCK);
	}
}

static void tcp_tune(int fd)
{
	int one = 1;
	int bufsize = 65536;

	setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
	setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &bufsize, sizeof(bufsize));
	setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &bufsize, sizeof(bufsize));
}

static int http_connect_nb(void)
{
	int fd;
	struct sockaddr_in addr;

	fd = socket(AF_INET, SOCK_STREAM, 0);
	if (fd < 0) {
		return -1;
	}
	tcp_tune(fd);
	set_nonblock(fd);
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons((unsigned short)atoi(proxy_backend_port));
	if (inet_pton(AF_INET, proxy_backend_host, &addr.sin_addr) != 1) {
		close(fd);
		return -1;
	}
	if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0 || errno == EINPROGRESS) {
		return fd;
	}
	close(fd);
	return -1;
}

static void close_conn(conn_t *conn)
{
	if (conn->http_fd >= 0) {
		close(conn->http_fd);
		conn->http_fd = -1;
	}
	if (conn->client_fd.fd >= 0) {
		mbedtls_net_free(&conn->client_fd);
	}
	mbedtls_ssl_free(&conn->ssl);
	conn->state = C_CLOSED;
}

int run_event_server(mbedtls_net_context *listen_fd, mbedtls_ssl_config *conf)
{
	conn_t *head = NULL;
	conn_t *conn;
	const char *workers_env;
	int max_conns = 8;
	int worker_count = 5;
	int worker_index;

	if (listen_fd && listen_fd->fd >= 0) {
		set_nonblock(listen_fd->fd);
	}
	workers_env = getenv("HTTPD_SSL_WORKERS");
	if (workers_env != NULL) {
		int parsed = atoi(workers_env);
		if (parsed > 0 && parsed < 16) {
			worker_count = parsed;
		}
	}
	for (worker_index = 1; worker_index < worker_count; worker_index++) {
		pid_t pid = fork();
		if (pid < 0) {
			continue;
		}
		if (pid == 0) {
			break;
		}
	}

	while (keep_running) {
		fd_set rfds;
		fd_set wfds;
		struct timeval timeout = { .tv_sec = 60, .tv_usec = 0 };
		int conn_count = 0;
		int maxfd = -1;
		int ready;
		conn_t *prev;

		FD_ZERO(&rfds);
		FD_ZERO(&wfds);
		if (listen_fd && listen_fd->fd >= 0) {
			FD_SET(listen_fd->fd, &rfds);
			maxfd = listen_fd->fd;
		}
		for (conn = head; conn; conn = conn->next) {
			int tls_fd = conn->client_fd.fd;
			int http_fd = conn->http_fd;

			if (conn->state == C_CLOSED) {
				continue;
			}
			conn_count++;
			if (tls_fd >= 0 && tls_fd > maxfd) {
				maxfd = tls_fd;
			}
			if (http_fd >= 0 && http_fd > maxfd) {
				maxfd = http_fd;
			}
			if (http_fd >= 0 && !conn->http_connected) {
				FD_SET(http_fd, &wfds);
			}
			if (!conn->tls_done) {
				if (tls_fd >= 0) {
					FD_SET(tls_fd, &rfds);
					FD_SET(tls_fd, &wfds);
				}
				continue;
			}
			if (tls_fd >= 0 && rb_space(&conn->to_http) > 0) {
				FD_SET(tls_fd, &rfds);
			}
			if (tls_fd >= 0 && rb_size(&conn->to_tls) > 0) {
				FD_SET(tls_fd, &wfds);
			}
			if (http_fd >= 0 && conn->http_connected && rb_space(&conn->to_tls) > 0) {
				FD_SET(http_fd, &rfds);
			}
			if (http_fd >= 0 && conn->http_connected && rb_size(&conn->to_http) > 0) {
				FD_SET(http_fd, &wfds);
			}
		}

		ready = select(maxfd + 1, &rfds, &wfds, NULL, &timeout);
		if (ready < 0) {
			if (errno == EINTR) {
				continue;
			}
			break;
		}

		if (listen_fd && listen_fd->fd >= 0 && FD_ISSET(listen_fd->fd, &rfds)) {
			for (;;) {
				struct sockaddr_in cli_addr;
				socklen_t cli_len = sizeof(cli_addr);
				int client_fd = accept(listen_fd->fd, (struct sockaddr *)&cli_addr, &cli_len);
				conn_t *new_conn;

				if (client_fd < 0) {
					if (errno == EAGAIN || errno == EWOULDBLOCK) {
						break;
					}
					break;
				}
				if (conn_count >= max_conns) {
					close(client_fd);
					break;
				}
				new_conn = calloc(1, sizeof(*new_conn));
				if (new_conn == NULL) {
					close(client_fd);
					break;
				}
				mbedtls_ssl_init(&new_conn->ssl);
				mbedtls_net_init(&new_conn->client_fd);
				new_conn->client_fd.fd = client_fd;
				new_conn->http_fd = http_connect_nb();
				new_conn->http_connected = 0;
				new_conn->state = new_conn->http_fd < 0 ? C_SHUTDOWN : C_HANDSHAKE;
				set_nonblock(client_fd);
				tcp_tune(client_fd);
				rb_init(&new_conn->to_http);
				rb_init(&new_conn->to_tls);
				if (mbedtls_ssl_setup(&new_conn->ssl, conf) != 0) {
					close_conn(new_conn);
					free(new_conn);
					continue;
				}
				mbedtls_ssl_set_bio(&new_conn->ssl, &new_conn->client_fd,
					mbedtls_net_send, mbedtls_net_recv, NULL);
				new_conn->next = head;
				head = new_conn;
				conn_count++;
			}
		}

		for (conn = head, prev = NULL; conn;) {
			int remove = 0;
			int tls_fd = conn->client_fd.fd;
			int http_fd = conn->http_fd;

			if (http_fd >= 0 && !conn->http_connected && FD_ISSET(http_fd, &wfds)) {
				int err = 0;
				socklen_t err_len = sizeof(err);

				if (getsockopt(http_fd, SOL_SOCKET, SO_ERROR, &err, &err_len) == 0 && err == 0) {
					conn->http_connected = 1;
				} else {
					conn->state = C_SHUTDOWN;
				}
			}

			if (!conn->tls_done && tls_fd >= 0 && (FD_ISSET(tls_fd, &rfds) || FD_ISSET(tls_fd, &wfds))) {
				int ret = mbedtls_ssl_handshake(&conn->ssl);

				if (ret == 0) {
					conn->tls_done = 1;
				} else if (ret != MBEDTLS_ERR_SSL_WANT_READ && ret != MBEDTLS_ERR_SSL_WANT_WRITE) {
					conn->state = C_SHUTDOWN;
				}
			}

			if (conn->tls_done && conn->http_connected && conn->state != C_SHUTDOWN) {
				if (http_fd >= 0 && FD_ISSET(http_fd, &wfds) && rb_size(&conn->to_http) > 0) {
					for (;;) {
						const unsigned char *ptr;
						size_t len = rb_peek(&conn->to_http, &ptr);
						int sent;

						if (len == 0) {
							break;
						}
						sent = send(http_fd, ptr, len, MSG_DONTWAIT);
						if (sent > 0) {
							rb_consume(&conn->to_http, (size_t)sent);
							continue;
						}
						if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
							break;
						}
						conn->state = C_SHUTDOWN;
						break;
					}
				}
				if (tls_fd >= 0 && FD_ISSET(tls_fd, &wfds) && rb_size(&conn->to_tls) > 0) {
					for (;;) {
						const unsigned char *ptr;
						size_t len = rb_peek(&conn->to_tls, &ptr);
						int written;

						if (len == 0) {
							break;
						}
						written = mbedtls_ssl_write(&conn->ssl, ptr, len);
						if (written > 0) {
							rb_consume(&conn->to_tls, (size_t)written);
							continue;
						}
						if (written == MBEDTLS_ERR_SSL_WANT_READ || written == MBEDTLS_ERR_SSL_WANT_WRITE) {
							break;
						}
						conn->state = C_SHUTDOWN;
						break;
					}
				}
				if (tls_fd >= 0 && FD_ISSET(tls_fd, &rfds)) {
					for (;;) {
						unsigned char tmp[TMP_READ];
						size_t space = rb_space(&conn->to_http);
						size_t to_read = space < sizeof(tmp) ? space : sizeof(tmp);
						int read_len;

						if (space == 0) {
							break;
						}
						read_len = mbedtls_ssl_read(&conn->ssl, tmp, (unsigned int)to_read);
						if (read_len > 0) {
							rb_write(&conn->to_http, tmp, (size_t)read_len);
							if (!mbedtls_ssl_check_pending(&conn->ssl)) {
								break;
							}
							continue;
						}
						if (read_len == 0) {
							conn->state = C_SHUTDOWN;
							break;
						}
						if (read_len == MBEDTLS_ERR_SSL_WANT_READ || read_len == MBEDTLS_ERR_SSL_WANT_WRITE) {
							break;
						}
						conn->state = C_SHUTDOWN;
						break;
					}
				}
				if (http_fd >= 0 && FD_ISSET(http_fd, &rfds)) {
					for (;;) {
						unsigned char tmp[TMP_READ];
						size_t space = rb_space(&conn->to_tls);
						size_t to_read = space < sizeof(tmp) ? space : sizeof(tmp);
						int read_len;

						if (space == 0) {
							break;
						}
						read_len = recv(http_fd, tmp, to_read, MSG_DONTWAIT);
						if (read_len > 0) {
							rb_write(&conn->to_tls, tmp, (size_t)read_len);
							if ((size_t)read_len < to_read) {
								break;
							}
							continue;
						}
						if (read_len == 0) {
							conn->state = C_SHUTDOWN;
							break;
						}
						if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
							break;
						}
						conn->state = C_SHUTDOWN;
						break;
					}
				}
			}

			if (conn->state == C_SHUTDOWN) {
				close_conn(conn);
				remove = 1;
			}

			if (remove) {
				conn_t *next = conn->next;

				if (prev) {
					prev->next = next;
				} else {
					head = next;
				}
				free(conn);
				conn = next;
				continue;
			}

			prev = conn;
			conn = conn->next;
		}
	}

	for (conn = head; conn;) {
		conn_t *next = conn->next;

		close_conn(conn);
		free(conn);
		conn = next;
	}

	return 0;
}