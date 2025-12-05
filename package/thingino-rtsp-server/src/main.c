#define _GNU_SOURCE
#include "rtsp_server.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>

static rtsp_server_t *g_server = NULL;

// Signal handler for graceful shutdown
void signal_handler(int sig) {
    printf("\nReceived signal %d, shutting down...\n", sig);
    if (g_server) {
        rtsp_server_stop(g_server);
    }
}

// Print usage information
void print_usage(const char *program_name) {
    printf("Usage: %s [options]\n", program_name);
    printf("\n");
    printf("Options:\n");
    printf("  -p PORT     RTSP server port (default: 554)\n");
    printf("  -u USER     Username for authentication\n");
    printf("  -P PASS     Password for authentication\n");
    printf("  -c CONFIG   Configuration file\n");
    printf("  -d          Run as daemon\n");
    printf("  -h          Show this help\n");
    printf("\n");
    printf("Examples:\n");
    printf("  %s -p 8554                    # Run on port 8554\n", program_name);
    printf("  %s -u admin -P secret         # With authentication\n", program_name);
    printf("  %s -c /etc/rtsp-server.conf   # Use config file\n", program_name);
    printf("\n");
}

// Load configuration from file (basic implementation)
int load_config(const char *config_file, int *port, char *username, char *password) {
    FILE *fp = fopen(config_file, "r");
    if (!fp) {
        perror("fopen");
        return -1;
    }

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        // Remove newline
        line[strcspn(line, "\r\n")] = '\0';

        // Skip comments and empty lines
        if (line[0] == '#' || line[0] == '\0') {
            continue;
        }

        // Parse key=value pairs
        char *eq = strchr(line, '=');
        if (eq) {
            *eq = '\0';
            char *key = line;
            char *value = eq + 1;

            // Trim whitespace
            while (*key == ' ' || *key == '\t') key++;
            while (*value == ' ' || *value == '\t') value++;

            if (strcmp(key, "port") == 0) {
                *port = atoi(value);
            } else if (strcmp(key, "username") == 0) {
                strncpy(username, value, 63);
                username[63] = '\0';
            } else if (strcmp(key, "password") == 0) {
                strncpy(password, value, 63);
                password[63] = '\0';
            }
        }
    }

    fclose(fp);
    return 0;
}

int main(int argc, char *argv[]) {
    int port = RTSP_DEFAULT_PORT;
    char username[64] = "";
    char password[64] = "";
    char config_file[256] = "";
    int daemon_mode = 0;
    int opt;

    // Parse command line arguments
    while ((opt = getopt(argc, argv, "p:u:P:c:dh")) != -1) {
        switch (opt) {
            case 'p':
                port = atoi(optarg);
                if (port <= 0 || port > 65535) {
                    fprintf(stderr, "Invalid port: %s\n", optarg);
                    return 1;
                }
                break;
            case 'u':
                strncpy(username, optarg, sizeof(username) - 1);
                break;
            case 'P':
                strncpy(password, optarg, sizeof(password) - 1);
                break;
            case 'c':
                strncpy(config_file, optarg, sizeof(config_file) - 1);
                break;
            case 'd':
                daemon_mode = 1;
                break;
            case 'h':
                print_usage(argv[0]);
                return 0;
            default:
                print_usage(argv[0]);
                return 1;
        }
    }

    // Load configuration file if specified
    if (config_file[0] != '\0') {
        if (load_config(config_file, &port, username, password) < 0) {
            fprintf(stderr, "Failed to load config file: %s\n", config_file);
            return 1;
        }
    }

    // Daemonize if requested
    if (daemon_mode) {
        if (daemon(0, 0) < 0) {
            perror("daemon");
            return 1;
        }
    }

    // Set up signal handlers
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    signal(SIGPIPE, SIG_IGN);

    // Create RTSP server
    g_server = rtsp_server_create(port);
    if (!g_server) {
        fprintf(stderr, "Failed to create RTSP server\n");
        return 1;
    }

    // Set authentication if provided
    if (username[0] != '\0' && password[0] != '\0') {
        if (rtsp_server_set_auth(g_server, username, password) < 0) {
            fprintf(stderr, "Failed to set authentication\n");
            rtsp_server_destroy(g_server);
            return 1;
        }
        printf("Authentication enabled for user: %s\n", username);
    }

    // Add default streams (example)
    rtsp_stream_t stream1 = {
        .name = "ch0",
        .path = "/ch0",
        .width = 1920,
        .height = 1080,
        .fps = 25,
        .codec = "H264",
        .bitrate = 2000,
        .data_callback = NULL,
        .user_data = NULL
    };

    rtsp_stream_t stream2 = {
        .name = "ch1",
        .path = "/ch1",
        .width = 640,
        .height = 360,
        .fps = 25,
        .codec = "H264",
        .bitrate = 500,
        .data_callback = NULL,
        .user_data = NULL
    };

    rtsp_server_add_stream(g_server, &stream1);
    rtsp_server_add_stream(g_server, &stream2);

    // Start server
    if (rtsp_server_start(g_server) < 0) {
        fprintf(stderr, "Failed to start RTSP server\n");
        rtsp_server_destroy(g_server);
        return 1;
    }

    printf("Thingino RTSP Server started successfully\n");
    printf("Listening on port %d\n", port);
    if (username[0] != '\0') {
        printf("Authentication: enabled\n");
    }
    printf("Available streams:\n");
    printf("  rtsp://server:%d/ch0 (1920x1080, 25fps)\n", port);
    printf("  rtsp://server:%d/ch1 (640x360, 25fps)\n", port);
    printf("\nPress Ctrl+C to stop\n");

    // Run server main loop
    int result = rtsp_server_run(g_server);

    // Cleanup
    rtsp_server_destroy(g_server);
    g_server = NULL;

    printf("RTSP server stopped\n");
    return result;
}
