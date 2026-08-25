/*
 * ha-mqtt-pubd - persistent MQTT publisher for thingino-ha
 *
 * Holds a single MQTT connection to the broker and publishes messages on
 * behalf of the HA shell scripts. Without this, every state or discovery
 * message forks a fresh mosquitto_pub process and pays a TCP connect +
 * CONNECT + teardown round trip per message. On a single-core camera that
 * is measurable churn every poll cycle.
 *
 * Broker settings are read from the environment exported by ha-common:
 * HA_MQTT_HOST, HA_MQTT_PORT, HA_MQTT_USER, HA_MQTT_PASS, HA_MQTT_SSL,
 * HA_MQTT_TLS_SKIP_VERIFY, HA_MQTT_CLIENT_PREFIX, HA_CAMERA_ID.
 *
 * Reads commands from a FIFO (argv[1]), one per line:
 *
 *     <retain>\t<topic>\t<payload-file>\n
 *
 * <retain> is '0' or '1'. The payload is read from <payload-file>, which
 * is unlinked after the publish attempt regardless of outcome so /tmp is
 * never left accumulating stale files.
 */

#include <errno.h>
#include <fcntl.h>
#include <mosquitto.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define MAX_PAYLOAD (1 << 22) /* 4 MiB, generous for base64 snapshots */
#define CONNECT_TIMEOUT_MS 5000
#define KEEPALIVE_S 30

static struct mosquitto *mosq;
static volatile sig_atomic_t connected;
static volatile sig_atomic_t quitting;

static void on_connect(struct mosquitto *m, void *obj, int rc)
{
	(void)m;
	(void)obj;
	connected = (rc == MOSQ_ERR_SUCCESS);
}

static void on_disconnect(struct mosquitto *m, void *obj, int rc)
{
	(void)m;
	(void)obj;
	(void)rc;
	connected = 0;
}

static void on_signal(int sig)
{
	(void)sig;
	quitting = 1;
}

/*
 * Bring the connection back up. With mosquitto_loop_start() running in the
 * background the reconnect completes asynchronously and on_connect() flips
 * 'connected', so poll that flag for a bounded time.
 */
static int ensure_connected(void)
{
	int waited;

	if (connected)
		return 0;

	mosquitto_reconnect(mosq);
	for (waited = 0; waited < CONNECT_TIMEOUT_MS && !connected; waited += 50)
		usleep(50000);

	return connected ? 0 : -1;
}

static int publish_file(const char *topic, int retain, const char *path)
{
	FILE *f;
	long len;
	char *buf;
	size_t n;
	int rc = -1;

	f = fopen(path, "rb");
	if (!f)
		return -1;

	if (fseek(f, 0, SEEK_END) != 0)
		goto out_close;
	len = ftell(f);
	if (len < 0 || len > MAX_PAYLOAD)
		goto out_close;
	rewind(f);

	buf = malloc(len ? (size_t)len : 1);
	if (!buf)
		goto out_close;

	n = fread(buf, 1, (size_t)len, f);
	if (n == (size_t)len && ensure_connected() == 0) {
		rc = mosquitto_publish(mosq, NULL, topic, (int)n, buf, 0,
				       retain);
		if (rc != MOSQ_ERR_SUCCESS)
			connected = 0;
	}
	free(buf);

out_close:
	fclose(f);
	return rc;
}

static void handle_line(char *line)
{
	char *save = NULL;
	char *retain_s = strtok_r(line, "\t\r\n", &save);
	char *topic = strtok_r(NULL, "\t\r\n", &save);
	char *path = strtok_r(NULL, "\t\r\n", &save);
	int retain;

	if (!retain_s || !topic || !path)
		return;

	retain = (retain_s[0] == '1');
	publish_file(topic, retain, path);
	unlink(path);
}

int main(int argc, char **argv)
{
	const char *host;
	const char *port_s;
	const char *client_prefix;
	const char *camera_id;
	const char *fifo;
	struct sigaction sa;
	char client_id[128];
	int port;
	int rc;

	if (argc < 2) {
		fprintf(stderr, "Usage: %s FIFO\n", argv[0]);
		return 1;
	}
	fifo = argv[1];

	host = getenv("HA_MQTT_HOST");
	port_s = getenv("HA_MQTT_PORT");
	client_prefix = getenv("HA_MQTT_CLIENT_PREFIX");
	camera_id = getenv("HA_CAMERA_ID");

	if (!host || !*host) {
		fprintf(stderr, "ha-mqtt-pubd: HA_MQTT_HOST is not set\n");
		return 1;
	}
	port = port_s ? atoi(port_s) : 1883;

	snprintf(client_id, sizeof(client_id), "%s-pubd-%s",
		 client_prefix && *client_prefix ? client_prefix : "thingino-ha",
		 camera_id && *camera_id ? camera_id : "thingino");

	mosquitto_lib_init();

	mosq = mosquitto_new(client_id, true, NULL);
	if (!mosq)
		return 1;

	{
		const char *user = getenv("HA_MQTT_USER");
		const char *pass = getenv("HA_MQTT_PASS");
		if (user && *user)
			mosquitto_username_pw_set(mosq, user, pass);
	}

	if (getenv("HA_MQTT_SSL") &&
	    strcmp(getenv("HA_MQTT_SSL"), "true") == 0) {
		mosquitto_tls_set(mosq, NULL, "/etc/ssl/certs", NULL, NULL,
				  NULL);
		if (getenv("HA_MQTT_TLS_SKIP_VERIFY") &&
		    strcmp(getenv("HA_MQTT_TLS_SKIP_VERIFY"), "true") == 0)
			mosquitto_tls_insecure_set(mosq, true);
	}

	mosquitto_connect_callback_set(mosq, on_connect);
	mosquitto_disconnect_callback_set(mosq, on_disconnect);

	/* Ignore the result: ensure_connected() retries on demand. */
	rc = mosquitto_connect(mosq, host, port, KEEPALIVE_S);
	(void)rc;
	mosquitto_loop_start(mosq);

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = on_signal;
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);
	signal(SIGPIPE, SIG_IGN);

	/*
	 * ha-daemon creates the FIFO before starting this daemon, but
	 * recreate it here too. If the node is ever missing, a shell writer
	 * using O_CREAT would silently create a regular file that nothing
	 * reads, so self-heal by re-creating the FIFO node first.
	 */
	mkfifo(fifo, 0600);

	while (!quitting) {
		FILE *fp;
		char line[1024];
		int fd;

		fd = open(fifo, O_RDONLY);
		if (fd < 0) {
			if (errno == EINTR)
				continue;
			usleep(200000);
			continue;
		}

		fp = fdopen(fd, "r");
		if (!fp) {
			close(fd);
			usleep(200000);
			continue;
		}

		while (!quitting && fgets(line, sizeof(line), fp))
			handle_line(line);

		fclose(fp);
	}

	mosquitto_loop_stop(mosq, true);
	mosquitto_destroy(mosq);
	mosquitto_lib_cleanup();
	return 0;
}
