#include "rtsp_server.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <arpa/inet.h>
#include <sys/socket.h>

// Create RTP socket
int rtp_create_socket(int port) {
    int sock_fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock_fd < 0) {
        perror("socket");
        return -1;
    }

    // Set socket options
    int opt = 1;
    if (setsockopt(sock_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) < 0) {
        perror("setsockopt");
        close(sock_fd);
        return -1;
    }

    // Bind to port if specified
    if (port > 0) {
        struct sockaddr_in addr;
        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port = htons(port);

        if (bind(sock_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
            perror("bind");
            close(sock_fd);
            return -1;
        }
    }

    return sock_fd;
}

// Send RTP packet
int rtp_send_packet(int socket_fd, struct sockaddr_in *addr, uint8_t *data, size_t len) {
    if (socket_fd < 0 || !addr || !data || len == 0) {
        return -1;
    }

    ssize_t sent = sendto(socket_fd, data, len, 0, (struct sockaddr*)addr, sizeof(*addr));
    if (sent < 0) {
        printf("RTP sendto failed: socket=%d, addr=%s:%d, len=%zu, error=%s\n",
               socket_fd, inet_ntoa(addr->sin_addr), ntohs(addr->sin_port), len, strerror(errno));
        return -1;
    }

    return (int)sent;
}

// Create RTP header (basic implementation)
int rtp_create_header(uint8_t *buffer, size_t buffer_size, uint8_t payload_type,
                     uint16_t sequence, uint32_t timestamp, uint32_t ssrc) {
    if (!buffer || buffer_size < 12) {
        return -1;
    }

    // RTP Header format (12 bytes):
    // 0                   1                   2                   3
    // 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    // |V=2|P|X|  CC   |M|     PT      |       sequence number         |
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    // |                           timestamp                           |
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    // |           synchronization source (SSRC) identifier          |
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

    memset(buffer, 0, 12);

    // Version (2), Padding (0), Extension (0), CSRC count (0)
    buffer[0] = 0x80;

    // Marker (0), Payload Type
    buffer[1] = payload_type & 0x7F;

    // Sequence number (big endian)
    buffer[2] = (sequence >> 8) & 0xFF;
    buffer[3] = sequence & 0xFF;

    // Timestamp (big endian)
    buffer[4] = (timestamp >> 24) & 0xFF;
    buffer[5] = (timestamp >> 16) & 0xFF;
    buffer[6] = (timestamp >> 8) & 0xFF;
    buffer[7] = timestamp & 0xFF;

    // SSRC (big endian)
    buffer[8] = (ssrc >> 24) & 0xFF;
    buffer[9] = (ssrc >> 16) & 0xFF;
    buffer[10] = (ssrc >> 8) & 0xFF;
    buffer[11] = ssrc & 0xFF;

    return 12;
}

// Send RTP packet with header
int rtp_send_data(int socket_fd, struct sockaddr_in *addr, uint8_t payload_type,
                 uint16_t sequence, uint32_t timestamp, uint32_t ssrc,
                 uint8_t *payload, size_t payload_len) {

    uint8_t packet[1500]; // MTU size
    int header_len;

    // Debug logging removed for production

    if (payload_len > sizeof(packet) - 12) {
        printf("rtp_send_data: Payload too large (%zu > %zu)\n", payload_len, sizeof(packet) - 12);
        return -1; // Payload too large
    }

    // Create RTP header
    header_len = rtp_create_header(packet, sizeof(packet), payload_type, sequence, timestamp, ssrc);
    if (header_len < 0) {
        return -1;
    }

    // Copy payload
    memcpy(packet + header_len, payload, payload_len);

    // Send packet
    return rtp_send_packet(socket_fd, addr, packet, header_len + payload_len);
}
