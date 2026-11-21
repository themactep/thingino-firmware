/*
 * SPI frame format between the T30 (SPI master, xr871net) and the XR871
 * (SPI slave, bridge firmware). Shared verbatim by both sides; keep the
 * copy in thingino package/xr871-bridge/files/ identical.
 *
 * Every transfer is SPIF_SIZE bytes, full duplex, one chip-select frame.
 * The slave arms its next frame before raising the ready line, so data
 * from the XR871 always travels in the transfer after it became pending.
 *
 *   0  u32 magic  SPIF_MAGIC ("X871")
 *   4  u8  type   SPIF_IDLE / SPIF_ETH
 *   5  u8  flags  SPIF_F_MORE: sender has more frames queued
 *   6  u16 len    payload bytes (<= SPIF_MAX_PAYLOAD)
 *   8  u16 seq    per-sender counter
 *  10  u16 crc    CRC-16/CCITT-FALSE over the payload
 *  12  payload    SPIF_ETH: one Ethernet frame (no FCS)
 *                 SPIF_IDLE: empty, or (XR871 -> T30) a struct spif_info
 * All fields little endian. A frame with a bad magic or CRC is dropped.
 *
 * spif_info (SPIF_INFO_LEN bytes): the T30 must use the XR871 station MAC
 * on wlan0 (a WiFi STA can only send with its own address), and gets the
 * link state for free with every idle poll.
 *   0  u8[6] mac   XR871 station MAC
 *   6  u8    link  1 = associated with the AP
 *   7  i8    rssi  dBm, 0 = unknown
 */
#ifndef SPI_FRAME_H
#define SPI_FRAME_H

#include <stdint.h>
#include <string.h>

#define SPIF_SIZE 1536
#define SPIF_HDR 12
#define SPIF_MAX_PAYLOAD (SPIF_SIZE - SPIF_HDR)
#define SPIF_MAGIC 0x31373858u
#define SPIF_IDLE 0
#define SPIF_ETH 1
#define SPIF_F_MORE 0x01
#define SPIF_INFO_LEN 8

static inline uint16_t spif_crc16(const uint8_t *p, int n)
{
	uint16_t c = 0xffff;
	int i;

	while (n-- > 0) {
		c ^= (uint16_t)(*p++) << 8;
		for (i = 0; i < 8; i++)
			c = (c & 0x8000) ? (uint16_t)((c << 1) ^ 0x1021) : (uint16_t)(c << 1);
	}
	return c;
}

/* fills a whole SPIF_SIZE buffer; returns 0, or -1 if len is too big */
static inline int spif_build(uint8_t *f, uint8_t type, uint8_t flags,
			     uint16_t seq, const uint8_t *payload, int len)
{
	uint16_t crc;

	if (len < 0 || len > SPIF_MAX_PAYLOAD)
		return -1;
	memset(f, 0, SPIF_SIZE);
	f[0] = (uint8_t)(SPIF_MAGIC & 0xff);
	f[1] = (uint8_t)((SPIF_MAGIC >> 8) & 0xff);
	f[2] = (uint8_t)((SPIF_MAGIC >> 16) & 0xff);
	f[3] = (uint8_t)((SPIF_MAGIC >> 24) & 0xff);
	f[4] = type;
	f[5] = flags;
	f[6] = len & 0xff; f[7] = len >> 8;
	f[8] = seq & 0xff; f[9] = seq >> 8;
	if (len)
		memcpy(f + SPIF_HDR, payload, len);
	crc = spif_crc16(f + SPIF_HDR, len);
	f[10] = crc & 0xff; f[11] = crc >> 8;
	return 0;
}

/* returns payload length (>= 0) and sets type and flags, or -1 if invalid */
static inline int spif_parse(const uint8_t *f, int n, uint8_t *type, uint8_t *flags)
{
	uint32_t m;
	int len;

	if (n < SPIF_HDR)
		return -1;
	m = f[0] | f[1] << 8 | f[2] << 16 | (uint32_t)f[3] << 24;
	if (m != SPIF_MAGIC)
		return -1;
	len = f[6] | f[7] << 8;
	if (len > SPIF_MAX_PAYLOAD || SPIF_HDR + len > n)
		return -1;
	if (spif_crc16(f + SPIF_HDR, len) != (uint16_t)(f[10] | f[11] << 8))
		return -1;
	*type = f[4];
	*flags = f[5];
	return len;
}

#endif
