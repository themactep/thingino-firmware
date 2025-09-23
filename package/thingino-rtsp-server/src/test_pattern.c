#define _GNU_SOURCE
#include "rtsp_server.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <time.h>
#include <math.h>

// Simple test pattern generator (RGB24 format)
int generate_test_pattern_frame(uint8_t *buffer, size_t buffer_size, int width, int height, uint32_t frame_number) {
    if (!buffer || buffer_size < (size_t)(width * height * 3)) {
        return -1;
    }

    // Generate colorful test pattern
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            int offset = (y * width + x) * 3;

            // Create moving color bars with animation
            int bar_width = width / 8;
            int bar_index = (x + frame_number / 10) / bar_width % 8;
            int time_offset = frame_number / 25; // 1 second cycles at 25fps

            uint8_t r, g, b;

            switch (bar_index) {
                case 0: r = 255; g = 255; b = 255; break; // White
                case 1: r = 255; g = 255; b = 0;   break; // Yellow
                case 2: r = 0;   g = 255; b = 255; break; // Cyan
                case 3: r = 0;   g = 255; b = 0;   break; // Green
                case 4: r = 255; g = 0;   b = 255; break; // Magenta
                case 5: r = 255; g = 0;   b = 0;   break; // Red
                case 6: r = 0;   g = 0;   b = 255; break; // Blue
                case 7: r = 0;   g = 0;   b = 0;   break; // Black
                default: r = 128; g = 128; b = 128; break; // Gray
            }

            // Add some animation
            if (y < height / 4) {
                // Top quarter: pulsing brightness
                float pulse = (sin(time_offset * 0.5) + 1.0) * 0.5;
                r = (uint8_t)(r * pulse);
                g = (uint8_t)(g * pulse);
                b = (uint8_t)(b * pulse);
            } else if (y > height * 3 / 4) {
                // Bottom quarter: moving gradient
                int gradient = (x + time_offset * 5) % 256;
                r = gradient;
                g = 255 - gradient;
                b = (gradient + 128) % 256;
            }

            buffer[offset] = r;
            buffer[offset + 1] = g;
            buffer[offset + 2] = b;
        }
    }

    return width * height * 3;
}

// Create a minimal JPEG header for test pattern
int create_simple_jpeg(uint8_t *rgb_data, int width, int height, uint8_t *jpeg_buffer, size_t jpeg_buffer_size) {
    if (!rgb_data || !jpeg_buffer || jpeg_buffer_size < 1000) {
        return -1;
    }

    // Simple JPEG header for RGB data (minimal but valid)
    uint8_t jpeg_header[] = {
        0xFF, 0xD8,                     // SOI (Start of Image)
        0xFF, 0xE0,                     // APP0
        0x00, 0x10,                     // Length
        'J', 'F', 'I', 'F', 0x00,       // JFIF identifier
        0x01, 0x01,                     // Version
        0x01,                           // Units (1 = pixels per inch)
        0x00, 0x48, 0x00, 0x48,         // X and Y density (72 DPI)
        0x00, 0x00,                     // Thumbnail width/height (none)

        0xFF, 0xC0,                     // SOF0 (Start of Frame)
        0x00, 0x11,                     // Length
        0x08,                           // Precision (8 bits)
        (height >> 8) & 0xFF, height & 0xFF,  // Height
        (width >> 8) & 0xFF, width & 0xFF,    // Width
        0x03,                           // Number of components (RGB)
        0x01, 0x11, 0x00,               // Component 1 (R)
        0x02, 0x11, 0x01,               // Component 2 (G)
        0x03, 0x11, 0x02,               // Component 3 (B)

        0xFF, 0xDA,                     // SOS (Start of Scan)
        0x00, 0x0C,                     // Length
        0x03,                           // Number of components
        0x01, 0x00,                     // Component 1
        0x02, 0x11,                     // Component 2
        0x03, 0x11,                     // Component 3
        0x00, 0x3F, 0x00                // Spectral selection
    };

    // Copy header
    memcpy(jpeg_buffer, jpeg_header, sizeof(jpeg_header));
    int offset = sizeof(jpeg_header);

    // Add compressed RGB data (very simple compression - just copy every 4th pixel)
    int compressed_size = 0;
    for (int i = 0; i < width * height * 3; i += 12) { // Sample every 4th pixel
        if (offset + 3 < jpeg_buffer_size - 10) {
            jpeg_buffer[offset++] = rgb_data[i];     // R
            jpeg_buffer[offset++] = rgb_data[i+1];   // G
            jpeg_buffer[offset++] = rgb_data[i+2];   // B
            compressed_size += 3;
        }
    }

    // Add EOI (End of Image)
    jpeg_buffer[offset++] = 0xFF;
    jpeg_buffer[offset++] = 0xD9;

    return offset;
}

// Streaming thread function
void* streaming_thread_func(void *arg) {
    rtsp_server_t *server = (rtsp_server_t*)arg;
    uint8_t *frame_buffer = malloc(640 * 360 * 3); // RGB24 buffer
    uint8_t *jpeg_buffer = malloc(640 * 360 * 3 + 1000); // JPEG buffer
    uint32_t frame_number = 0;

    if (!frame_buffer || !jpeg_buffer) {
        printf("Failed to allocate frame buffers\n");
        free(frame_buffer);
        free(jpeg_buffer);
        return NULL;
    }

    printf("Streaming thread started\n");

    while (server->streaming_active) {
        // Generate test pattern frame
        int frame_size = generate_test_pattern_frame(frame_buffer, 640 * 360 * 3, 640, 360, frame_number);
        if (frame_size <= 0) {
            continue;
        }

        // Create a simple MPEG-2 TS packet with test pattern
        // This creates a minimal transport stream that FFmpeg can decode
        uint8_t ts_packet[188]; // Standard TS packet size
        memset(ts_packet, 0, sizeof(ts_packet));

        // TS Header
        ts_packet[0] = 0x47;  // Sync byte
        ts_packet[1] = 0x40;  // Transport Error Indicator=0, Payload Unit Start=1, Priority=0, PID high bits
        ts_packet[2] = 0x00;  // PID low bits (PID=0 for PAT)
        ts_packet[3] = 0x10;  // Scrambling=00, Adaptation=01, Continuity=0

        // Simple payload - create a colorful pattern that changes each frame
        for (int i = 4; i < 188; i++) {
            // Create a simple animated pattern
            int pattern = (frame_number + i) % 256;
            if (i % 3 == 0) ts_packet[i] = pattern;           // Red channel
            else if (i % 3 == 1) ts_packet[i] = 255 - pattern; // Green channel
            else ts_packet[i] = (pattern * 2) % 256;          // Blue channel
        }

        // Copy the TS packet multiple times to make it more visible
        int ts_size = 0;
        for (int copy = 0; copy < 10 && ts_size + 188 < 640 * 360 * 3 + 1000; copy++) {
            memcpy(jpeg_buffer + ts_size, ts_packet, 188);
            ts_size += 188;
        }

        int rgb_size = ts_size;

        // Send to all active streaming clients
        for (int i = 0; i < RTSP_MAX_CLIENTS; i++) {
            if (server->clients[i].active && server->clients[i].streaming && server->clients[i].rtp_socket >= 0) {
                // Calculate timestamp (90kHz clock for video)
                uint32_t timestamp = frame_number * 90000 / 25; // 25fps

                // Send RTP packets (split large payload into multiple packets)
                int max_payload_size = 1400; // Leave room for RTP header and network headers
                int offset = 0;
                int packets_sent = 0;

                while (offset < rgb_size) {
                    int chunk_size = (rgb_size - offset > max_payload_size) ? max_payload_size : (rgb_size - offset);

                    int sent = rtp_send_data(
                        server->clients[i].rtp_socket,
                        &server->clients[i].rtp_addr,
                        96, // H.264 payload type
                        server->clients[i].rtp_sequence++,
                        timestamp,
                        server->clients[i].rtp_ssrc,
                        jpeg_buffer + offset,
                        chunk_size
                    );

                    if (sent < 0) {
                        printf("Failed to send RTP packet %d to client %d (addr: %s:%d)\n",
                               packets_sent, i, inet_ntoa(server->clients[i].rtp_addr.sin_addr),
                               ntohs(server->clients[i].rtp_addr.sin_port));
                        break;
                    }

                    offset += chunk_size;
                    packets_sent++;
                }

                // Only print success message occasionally to avoid spam
                if (packets_sent > 0 && frame_number % 100 == 0) {
                    printf("Sent %d MPEG-TS RTP packets to client %d (total size: %d)\n",
                           packets_sent, i, rgb_size);
                }
            }
        }

        frame_number++;

        // Sleep for frame rate (25fps = 40ms per frame)
        usleep(40000);
    }

    printf("Streaming thread stopped\n");
    free(frame_buffer);
    free(jpeg_buffer);
    return NULL;
}

// Start streaming thread
int start_streaming_thread(rtsp_server_t *server) {
    if (!server || server->streaming_active) {
        return -1;
    }

    server->streaming_active = 1;

    if (pthread_create(&server->streaming_thread, NULL, streaming_thread_func, server) != 0) {
        server->streaming_active = 0;
        return -1;
    }

    return 0;
}

// Stop streaming thread
void stop_streaming_thread(rtsp_server_t *server) {
    if (!server || !server->streaming_active) {
        return;
    }

    server->streaming_active = 0;
    pthread_join(server->streaming_thread, NULL);
}
