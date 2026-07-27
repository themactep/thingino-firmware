#include "rtsp_server.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <arpa/inet.h>

// Generate SDP (Session Description Protocol) for RTSP stream
int sdp_generate(char *buffer, size_t buffer_size, const rtsp_stream_t *stream, const char *server_ip) {
    if (!buffer || !stream || !server_ip) {
        return -1;
    }

    uint64_t now = get_safe_time_ntp();

    // Basic SDP structure for H.264 video stream
    int len = snprintf(buffer, buffer_size,
        "v=0\r\n"                                           // Version
        "o=- %lld %lld IN IP4 %s\r\n"                       // Origin
        "s=%s\r\n"                                          // Session name
        "c=IN IP4 %s\r\n"                                   // Connection info
        "t=0 0\r\n"                                         // Time
        "a=tool:thingino-rtsp-server\r\n"                   // Tool
        "m=video 0 RTP/AVP 96\r\n"                          // Media description (Raw video)
        "b=AS:%d\r\n"                                       // Bandwidth
        "a=framerate:%d\r\n"                                // Frame rate
        "a=rtpmap:96 MP2T/90000\r\n"                        // MPEG-2 Transport Stream
        "a=control:track1\r\n",                             // Control
        now, now, server_ip,                                // Origin parameters
        stream->name,                                       // Session name
        server_ip,                                          // Connection IP
        stream->bitrate,                                    // Bandwidth
        stream->fps                                         // Frame rate
    );

    if (len >= (int)buffer_size) {
        return -1; // Buffer too small
    }

    return len;
}

// Generate SDP for multiple streams
int sdp_generate_multi(char *buffer, size_t buffer_size, const rtsp_stream_t *streams,
                      int stream_count, const char *server_ip) {
    if (!buffer || !streams || stream_count <= 0 || !server_ip) {
        return -1;
    }

    uint64_t now = get_safe_time_ntp();
    int offset = 0;

    // Session-level SDP
    int len = snprintf(buffer + offset, buffer_size - offset,
        "v=0\r\n"                                           // Version
        "o=- %lld %lld IN IP4 %s\r\n"                       // Origin
        "s=Thingino Camera Streams\r\n"                     // Session name
        "c=IN IP4 %s\r\n"                                   // Connection info
        "t=0 0\r\n"                                         // Time
        "a=tool:thingino-rtsp-server\r\n",                  // Tool
        now, now, server_ip,                                // Origin parameters
        server_ip                                           // Connection IP
    );

    if (len >= (int)(buffer_size - offset)) {
        return -1;
    }
    offset += len;

    // Add media descriptions for each stream
    for (int i = 0; i < stream_count; i++) {
        len = snprintf(buffer + offset, buffer_size - offset,
            "m=video 0 RTP/AVP %d\r\n"                      // Media description
            "b=AS:%d\r\n"                                   // Bandwidth
            "a=framerate:%d\r\n"                            // Frame rate
            "a=rtpmap:%d H264/90000\r\n"                    // RTP map
            "a=fmtp:%d packetization-mode=1;profile-level-id=42001e\r\n"  // Format parameters
            "a=control:%s\r\n",                             // Control
            96 + i,                                         // Payload type
            streams[i].bitrate,                             // Bandwidth
            streams[i].fps,                                 // Frame rate
            96 + i,                                         // Payload type
            96 + i,                                         // Payload type
            streams[i].name                                 // Control track name
        );

        if (len >= (int)(buffer_size - offset)) {
            return -1;
        }
        offset += len;
    }

    return offset;
}

// Parse SDP from buffer (basic implementation)
int sdp_parse(const char *sdp_data, rtsp_stream_t *stream) {
    if (!sdp_data || !stream) {
        return -1;
    }

    char line[256];
    const char *ptr = sdp_data;

    // Initialize stream with defaults
    memset(stream, 0, sizeof(rtsp_stream_t));
    stream->fps = 25;
    stream->bitrate = 1000;
    strcpy(stream->codec, "H264");

    // Parse SDP line by line
    while (*ptr) {
        // Extract line
        int i = 0;
        while (*ptr && *ptr != '\r' && *ptr != '\n' && i < (int)sizeof(line) - 1) {
            line[i++] = *ptr++;
        }
        line[i] = '\0';

        // Skip CRLF
        if (*ptr == '\r') ptr++;
        if (*ptr == '\n') ptr++;

        // Parse line
        if (strlen(line) >= 2 && line[1] == '=') {
            char type = line[0];
            char *value = line + 2;

            switch (type) {
                case 's': // Session name
                    strncpy(stream->name, value, sizeof(stream->name) - 1);
                    break;

                case 'm': // Media description
                    if (strncmp(value, "video", 5) == 0) {
                        // Parse video media line
                        // Format: "video <port> <proto> <fmt>"
                        // We mainly care about the format (payload type)
                    }
                    break;

                case 'a': // Attributes
                    if (strncmp(value, "framerate:", 10) == 0) {
                        stream->fps = atoi(value + 10);
                    } else if (strncmp(value, "rtpmap:", 7) == 0) {
                        // Parse RTP mapping
                        if (strstr(value, "H264")) {
                            strcpy(stream->codec, "H264");
                        }
                    }
                    break;

                case 'b': // Bandwidth
                    if (strncmp(value, "AS:", 3) == 0) {
                        stream->bitrate = atoi(value + 3);
                    }
                    break;
            }
        }
    }

    return 0;
}

// Validate SDP format
int sdp_validate(const char *sdp_data) {
    if (!sdp_data) {
        return 0;
    }

    // Check for required SDP fields
    if (!strstr(sdp_data, "v=0")) return 0;        // Version
    if (!strstr(sdp_data, "o=")) return 0;         // Origin
    if (!strstr(sdp_data, "s=")) return 0;         // Session name
    if (!strstr(sdp_data, "c=")) return 0;         // Connection
    if (!strstr(sdp_data, "t=")) return 0;         // Time
    if (!strstr(sdp_data, "m=")) return 0;         // Media

    return 1;
}
