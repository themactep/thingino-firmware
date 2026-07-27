Opus over RTP and Codec References

- RFC 7587: RTP Payload Format for the Opus Speech and Audio Codec
  - https://www.rfc-editor.org/rfc/rfc7587
  - Key points used in prudynt-t:
    - RTP timestamp clock rate MUST be 48000 Hz for Opus, regardless of input sample rate
    - Common packetization durations: 20 ms (recommended), 2.5–60 ms allowed

- RFC 6716: Definition of the Opus Audio Codec
  - https://www.rfc-editor.org/rfc/rfc6716
  - Key points used in prudynt-t:
    - Valid Opus frame sizes (per channel) at 48 kHz: 120, 240, 480, 960, 1920, 2880 samples
    - 20 ms corresponds to 960 samples at 48 kHz (baseline reference)

Implementation notes

- prudynt-t uses a unified 20 ms Opus packetization across all platforms for consistency and low latency
- RTP timestamping follows RFC 7587 with a 48 kHz clock; encoder input accumulation is based on ACTUAL input rate
- Buffer thresholds are configurable via prudynt.json: audio.buffer_warn_frames (default 3), audio.buffer_cap_frames (default 5)

