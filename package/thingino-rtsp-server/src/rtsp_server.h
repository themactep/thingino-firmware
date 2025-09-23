#ifndef RTSP_SERVER_H
#define RTSP_SERVER_H

#include <stdint.h>
#include <time.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>

// Safe 32-bit time utilities for MIPS platform
uint32_t get_safe_time_seconds(void);
uint64_t get_safe_time_ntp(void);

#define RTSP_VERSION "RTSP/1.0"
#define RTSP_MAX_CLIENTS 8
#define RTSP_BUFFER_SIZE 4096
#define RTSP_DEFAULT_PORT 554

// RTSP Methods
typedef enum {
    RTSP_METHOD_OPTIONS,
    RTSP_METHOD_DESCRIBE,
    RTSP_METHOD_SETUP,
    RTSP_METHOD_PLAY,
    RTSP_METHOD_PAUSE,
    RTSP_METHOD_TEARDOWN,
    RTSP_METHOD_GET_PARAMETER,
    RTSP_METHOD_SET_PARAMETER,
    RTSP_METHOD_UNKNOWN
} rtsp_method_t;

// RTSP Response codes
typedef enum {
    RTSP_STATUS_OK = 200,
    RTSP_STATUS_BAD_REQUEST = 400,
    RTSP_STATUS_UNAUTHORIZED = 401,
    RTSP_STATUS_NOT_FOUND = 404,
    RTSP_STATUS_METHOD_NOT_ALLOWED = 405,
    RTSP_STATUS_UNSUPPORTED_MEDIA_TYPE = 415,
    RTSP_STATUS_SESSION_NOT_FOUND = 454,
    RTSP_STATUS_INTERNAL_ERROR = 500,
    RTSP_STATUS_NOT_IMPLEMENTED = 501
} rtsp_status_t;

// Client session structure
typedef struct {
    int socket_fd;
    struct sockaddr_in addr;
    char session_id[32];
    char transport[256];
    int rtp_port;
    int rtcp_port;
    int rtp_socket;
    int rtcp_socket;
    struct sockaddr_in rtp_addr;
    struct sockaddr_in rtcp_addr;
    int active;
    int streaming;
    uint32_t last_activity;  // Time in seconds (safe 32-bit)
    uint16_t rtp_sequence;
    uint32_t rtp_timestamp;
    uint32_t rtp_ssrc;
} rtsp_client_t;

// Stream configuration
typedef struct {
    char name[64];          // Stream name (e.g., "ch0", "ch1")
    char path[256];         // Stream path (e.g., "/ch0")
    int width;              // Video width
    int height;             // Video height
    int fps;                // Frame rate
    char codec[32];         // Video codec (e.g., "H264")
    int bitrate;            // Bitrate in kbps
    int (*data_callback)(uint8_t *data, size_t len, void *user_data);
    void *user_data;
} rtsp_stream_t;

// RTSP Server structure
typedef struct {
    int server_fd;
    int port;
    int running;
    rtsp_client_t clients[RTSP_MAX_CLIENTS];
    rtsp_stream_t streams[4];  // Support up to 4 streams
    int stream_count;
    char username[64];
    char password[64];
    int auth_required;
    pthread_t streaming_thread;
    int streaming_active;
} rtsp_server_t;

// Function prototypes
rtsp_server_t* rtsp_server_create(int port);
void rtsp_server_destroy(rtsp_server_t *server);
int rtsp_server_add_stream(rtsp_server_t *server, const rtsp_stream_t *stream);
int rtsp_server_set_auth(rtsp_server_t *server, const char *username, const char *password);
int rtsp_server_start(rtsp_server_t *server);
void rtsp_server_stop(rtsp_server_t *server);
int rtsp_server_run(rtsp_server_t *server);

// Utility functions
rtsp_method_t rtsp_parse_method(const char *method_str);
const char* rtsp_method_to_string(rtsp_method_t method);
const char* rtsp_status_to_string(rtsp_status_t status);
int rtsp_parse_request(const char *request, char *method, char *uri, char *version);
int rtsp_send_response(int client_fd, rtsp_status_t status, const char *headers, const char *body);

// RTP/RTCP utilities
int rtp_create_socket(int port);
int rtp_send_packet(int socket_fd, struct sockaddr_in *addr, uint8_t *data, size_t len);
int rtp_create_header(uint8_t *buffer, size_t buffer_size, uint8_t payload_type,
                     uint16_t sequence, uint32_t timestamp, uint32_t ssrc);
int rtp_send_data(int socket_fd, struct sockaddr_in *addr, uint8_t payload_type,
                 uint16_t sequence, uint32_t timestamp, uint32_t ssrc,
                 uint8_t *payload, size_t payload_len);

// Test pattern generation
int generate_test_pattern_frame(uint8_t *buffer, size_t buffer_size, int width, int height, uint32_t frame_number);
int start_streaming_thread(rtsp_server_t *server);
void stop_streaming_thread(rtsp_server_t *server);

// SDP utilities
int sdp_generate(char *buffer, size_t buffer_size, const rtsp_stream_t *stream, const char *server_ip);

#endif // RTSP_SERVER_H
