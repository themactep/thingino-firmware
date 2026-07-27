#include "rtsp_server.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <pthread.h>
#include <arpa/inet.h>
#include <sys/select.h>

// External function declarations for RTP and SDP utilities
extern int rtp_create_socket(int port);
extern int rtp_send_packet(int socket_fd, struct sockaddr_in *addr, uint8_t *data, size_t len);
extern int sdp_generate(char *buffer, size_t buffer_size, const rtsp_stream_t *stream, const char *server_ip);

// Create RTSP server
rtsp_server_t* rtsp_server_create(int port) {
    rtsp_server_t *server = calloc(1, sizeof(rtsp_server_t));
    if (!server) {
        return NULL;
    }

    server->port = port > 0 ? port : RTSP_DEFAULT_PORT;
    server->server_fd = -1;
    server->running = 0;
    server->stream_count = 0;
    server->auth_required = 0;

    // Initialize client slots
    for (int i = 0; i < RTSP_MAX_CLIENTS; i++) {
        server->clients[i].socket_fd = -1;
        server->clients[i].active = 0;
    }

    return server;
}

// Destroy RTSP server
void rtsp_server_destroy(rtsp_server_t *server) {
    if (!server) return;

    rtsp_server_stop(server);
    free(server);
}

// Add stream to server
int rtsp_server_add_stream(rtsp_server_t *server, const rtsp_stream_t *stream) {
    if (!server || !stream || server->stream_count >= 4) {
        return -1;
    }

    memcpy(&server->streams[server->stream_count], stream, sizeof(rtsp_stream_t));
    server->stream_count++;

    return 0;
}

// Set authentication
int rtsp_server_set_auth(rtsp_server_t *server, const char *username, const char *password) {
    if (!server || !username || !password) {
        return -1;
    }

    strncpy(server->username, username, sizeof(server->username) - 1);
    strncpy(server->password, password, sizeof(server->password) - 1);
    server->auth_required = 1;

    return 0;
}

// Parse RTSP method
rtsp_method_t rtsp_parse_method(const char *method_str) {
    if (!method_str) return RTSP_METHOD_UNKNOWN;

    if (strcmp(method_str, "OPTIONS") == 0) return RTSP_METHOD_OPTIONS;
    if (strcmp(method_str, "DESCRIBE") == 0) return RTSP_METHOD_DESCRIBE;
    if (strcmp(method_str, "SETUP") == 0) return RTSP_METHOD_SETUP;
    if (strcmp(method_str, "PLAY") == 0) return RTSP_METHOD_PLAY;
    if (strcmp(method_str, "PAUSE") == 0) return RTSP_METHOD_PAUSE;
    if (strcmp(method_str, "TEARDOWN") == 0) return RTSP_METHOD_TEARDOWN;
    if (strcmp(method_str, "GET_PARAMETER") == 0) return RTSP_METHOD_GET_PARAMETER;
    if (strcmp(method_str, "SET_PARAMETER") == 0) return RTSP_METHOD_SET_PARAMETER;

    return RTSP_METHOD_UNKNOWN;
}

// Convert method to string
const char* rtsp_method_to_string(rtsp_method_t method) {
    switch (method) {
        case RTSP_METHOD_OPTIONS: return "OPTIONS";
        case RTSP_METHOD_DESCRIBE: return "DESCRIBE";
        case RTSP_METHOD_SETUP: return "SETUP";
        case RTSP_METHOD_PLAY: return "PLAY";
        case RTSP_METHOD_PAUSE: return "PAUSE";
        case RTSP_METHOD_TEARDOWN: return "TEARDOWN";
        case RTSP_METHOD_GET_PARAMETER: return "GET_PARAMETER";
        case RTSP_METHOD_SET_PARAMETER: return "SET_PARAMETER";
        default: return "UNKNOWN";
    }
}

// Convert status to string
const char* rtsp_status_to_string(rtsp_status_t status) {
    switch (status) {
        case RTSP_STATUS_OK: return "OK";
        case RTSP_STATUS_BAD_REQUEST: return "Bad Request";
        case RTSP_STATUS_UNAUTHORIZED: return "Unauthorized";
        case RTSP_STATUS_NOT_FOUND: return "Not Found";
        case RTSP_STATUS_METHOD_NOT_ALLOWED: return "Method Not Allowed";
        case RTSP_STATUS_UNSUPPORTED_MEDIA_TYPE: return "Unsupported Media Type";
        case RTSP_STATUS_SESSION_NOT_FOUND: return "Session Not Found";
        case RTSP_STATUS_INTERNAL_ERROR: return "Internal Server Error";
        case RTSP_STATUS_NOT_IMPLEMENTED: return "Not Implemented";
        default: return "Unknown";
    }
}

// Parse RTSP request line
int rtsp_parse_request(const char *request, char *method, char *uri, char *version) {
    if (!request || !method || !uri || !version) {
        return -1;
    }

    return sscanf(request, "%63s %255s %63s", method, uri, version);
}

// Send RTSP response
int rtsp_send_response(int client_fd, rtsp_status_t status, const char *headers, const char *body) {
    char response[RTSP_BUFFER_SIZE];
    int len;

    len = snprintf(response, sizeof(response),
        "%s %d %s\r\n"
        "Server: Thingino-RTSP/1.0\r\n"
        "Date: %s\r\n"
        "%s"
        "\r\n"
        "%s",
        RTSP_VERSION, status, rtsp_status_to_string(status),
        "Thu, 01 Jan 1970 00:00:00 GMT", // TODO: Real date
        headers ? headers : "",
        body ? body : ""
    );

    return send(client_fd, response, len, 0);
}

// Start RTSP server
int rtsp_server_start(rtsp_server_t *server) {
    if (!server || server->running) {
        return -1;
    }

    // Create server socket
    server->server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server->server_fd < 0) {
        perror("socket");
        return -1;
    }

    // Set socket options
    int opt = 1;
    if (setsockopt(server->server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) < 0) {
        perror("setsockopt");
        close(server->server_fd);
        return -1;
    }

    // Bind to port
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(server->port);

    if (bind(server->server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind");
        close(server->server_fd);
        return -1;
    }

    // Listen for connections
    if (listen(server->server_fd, RTSP_MAX_CLIENTS) < 0) {
        perror("listen");
        close(server->server_fd);
        return -1;
    }

    server->running = 1;
    printf("RTSP server started on port %d\n", server->port);

    return 0;
}

// Stop RTSP server
void rtsp_server_stop(rtsp_server_t *server) {
    if (!server || !server->running) {
        return;
    }

    server->running = 0;

    // Close client connections
    for (int i = 0; i < RTSP_MAX_CLIENTS; i++) {
        if (server->clients[i].socket_fd >= 0) {
            close(server->clients[i].socket_fd);
            server->clients[i].socket_fd = -1;
            server->clients[i].active = 0;
        }
    }

    // Close server socket
    if (server->server_fd >= 0) {
        close(server->server_fd);
        server->server_fd = -1;
    }

    printf("RTSP server stopped\n");
}

// Main server loop (basic implementation)
int rtsp_server_run(rtsp_server_t *server) {
    if (!server || !server->running) {
        return -1;
    }

    fd_set read_fds;
    int max_fd;
    struct timeval timeout;

    while (server->running) {
        FD_ZERO(&read_fds);
        FD_SET(server->server_fd, &read_fds);
        max_fd = server->server_fd;

        // Add client sockets to fd_set
        for (int i = 0; i < RTSP_MAX_CLIENTS; i++) {
            if (server->clients[i].socket_fd >= 0) {
                FD_SET(server->clients[i].socket_fd, &read_fds);
                if (server->clients[i].socket_fd > max_fd) {
                    max_fd = server->clients[i].socket_fd;
                }
            }
        }

        timeout.tv_sec = 1;
        timeout.tv_usec = 0;

        int activity = select(max_fd + 1, &read_fds, NULL, NULL, &timeout);

        if (activity < 0) {
            if (errno != EINTR) {
                perror("select");
                break;
            }
            continue;
        }

        // Handle new connections
        if (FD_ISSET(server->server_fd, &read_fds)) {
            struct sockaddr_in client_addr;
            socklen_t addr_len = sizeof(client_addr);
            int client_fd = accept(server->server_fd, (struct sockaddr*)&client_addr, &addr_len);

            if (client_fd >= 0) {
                // Find free client slot
                int slot = -1;
                for (int i = 0; i < RTSP_MAX_CLIENTS; i++) {
                    if (!server->clients[i].active) {
                        slot = i;
                        break;
                    }
                }

                if (slot >= 0) {
                    server->clients[slot].socket_fd = client_fd;
                    server->clients[slot].addr = client_addr;
                    server->clients[slot].active = 1;
                    server->clients[slot].last_activity = get_safe_time_seconds();
                    printf("New client connected: %s:%d\n",
                           inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));
                } else {
                    printf("Max clients reached, rejecting connection\n");
                    close(client_fd);
                }
            }
        }

        // Handle client requests (basic implementation)
        for (int i = 0; i < RTSP_MAX_CLIENTS; i++) {
            if (server->clients[i].active && FD_ISSET(server->clients[i].socket_fd, &read_fds)) {
                char buffer[RTSP_BUFFER_SIZE];
                int bytes = recv(server->clients[i].socket_fd, buffer, sizeof(buffer) - 1, 0);

                if (bytes <= 0) {
                    // Client disconnected
                    printf("Client disconnected\n");
                    close(server->clients[i].socket_fd);
                    server->clients[i].socket_fd = -1;
                    server->clients[i].active = 0;
                } else {
                    buffer[bytes] = '\0';
                    server->clients[i].last_activity = get_safe_time_seconds();

                    // Basic RTSP request handling
                    char method[64], uri[256], version[64];
                    if (rtsp_parse_request(buffer, method, uri, version) == 3) {
                        rtsp_method_t rtsp_method = rtsp_parse_method(method);

                        switch (rtsp_method) {
                            case RTSP_METHOD_OPTIONS:
                                rtsp_send_response(server->clients[i].socket_fd, RTSP_STATUS_OK,
                                    "Public: OPTIONS, DESCRIBE, SETUP, PLAY, PAUSE, TEARDOWN\r\n", NULL);
                                break;
                            case RTSP_METHOD_DESCRIBE:
                                {
                                    // Generate basic SDP for test stream
                                    char sdp_buffer[1024];
                                    char server_ip[64] = "127.0.0.1"; // TODO: Get actual IP

                                    // Use first stream or create default
                                    rtsp_stream_t test_stream = {
                                        .name = "ch0",
                                        .path = "/ch0",
                                        .width = 640,
                                        .height = 360,
                                        .fps = 25,
                                        .codec = "MP2T",
                                        .bitrate = 1000
                                    };

                                    if (sdp_generate(sdp_buffer, sizeof(sdp_buffer), &test_stream, server_ip) > 0) {
                                        char headers[256];
                                        snprintf(headers, sizeof(headers),
                                            "Content-Type: application/sdp\r\n"
                                            "Content-Length: %d\r\n", (int)strlen(sdp_buffer));
                                        rtsp_send_response(server->clients[i].socket_fd, RTSP_STATUS_OK, headers, sdp_buffer);
                                    } else {
                                        rtsp_send_response(server->clients[i].socket_fd, RTSP_STATUS_INTERNAL_ERROR, NULL, NULL);
                                    }
                                }
                                break;
                            case RTSP_METHOD_SETUP:
                                {
                                    // Parse Transport header from request
                                    char *transport_line = strstr(buffer, "Transport:");
                                    int use_tcp = 0;
                                    int interleaved_rtp = 0, interleaved_rtcp = 1;
                                    int client_rtp_port = 5004, client_rtcp_port = 5005;

                                    if (transport_line) {
                                        printf("Client Transport: %.*s\n", (int)(strchr(transport_line, '\r') - transport_line), transport_line);

                                        // Check if client wants TCP transport
                                        if (strstr(transport_line, "RTP/AVP/TCP")) {
                                            use_tcp = 1;
                                            char *interleaved = strstr(transport_line, "interleaved=");
                                            if (interleaved) {
                                                sscanf(interleaved, "interleaved=%d-%d", &interleaved_rtp, &interleaved_rtcp);
                                            }
                                        } else {
                                            // UDP transport
                                            char *client_port = strstr(transport_line, "client_port=");
                                            if (client_port) {
                                                sscanf(client_port, "client_port=%d-%d", &client_rtp_port, &client_rtcp_port);
                                            }
                                        }
                                    }

                                    // Generate session ID
                                    char session_id[32];
                                    snprintf(session_id, sizeof(session_id), "%08X", get_safe_time_seconds());
                                    strncpy(server->clients[i].session_id, session_id, sizeof(server->clients[i].session_id) - 1);

                                    char headers[512];
                                    if (use_tcp) {
                                        // TCP interleaved transport
                                        snprintf(headers, sizeof(headers),
                                            "Transport: RTP/AVP/TCP;unicast;interleaved=%d-%d\r\n"
                                            "Session: %s\r\n",
                                            interleaved_rtp, interleaved_rtcp, session_id);
                                        printf("Server Transport: RTP/AVP/TCP;unicast;interleaved=%d-%d\n", interleaved_rtp, interleaved_rtcp);
                                    } else {
                                        // UDP transport
                                        snprintf(headers, sizeof(headers),
                                            "Transport: RTP/AVP;unicast;client_port=%d-%d;server_port=%d-%d\r\n"
                                            "Session: %s\r\n",
                                            client_rtp_port, client_rtcp_port, client_rtp_port, client_rtcp_port, session_id);
                                        printf("Server Transport: RTP/AVP;unicast;client_port=%d-%d;server_port=%d-%d\n",
                                               client_rtp_port, client_rtcp_port, client_rtp_port, client_rtcp_port);
                                    }

                                    rtsp_send_response(server->clients[i].socket_fd, RTSP_STATUS_OK, headers, NULL);
                                }
                                break;
                            case RTSP_METHOD_PLAY:
                                {
                                    char headers[256];
                                    snprintf(headers, sizeof(headers),
                                        "Session: %s\r\n"
                                        "Range: npt=0.000-\r\n",
                                        server->clients[i].session_id);

                                    rtsp_send_response(server->clients[i].socket_fd, RTSP_STATUS_OK, headers, NULL);
                                }
                                break;
                            default:
                                rtsp_send_response(server->clients[i].socket_fd, RTSP_STATUS_NOT_IMPLEMENTED, NULL, NULL);
                                break;
                        }
                    } else {
                        rtsp_send_response(server->clients[i].socket_fd, RTSP_STATUS_BAD_REQUEST, NULL, NULL);
                    }
                }
            }
        }
    }

    return 0;
}
