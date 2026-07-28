/*
* *
* Copyright (c) 2016, altobeam
* Author:
*
* Based on apollo code
* Copyright (C) STE SA 2012
* Author: Piotr Nakraszewicz <piotr.nakraszewicz@tieto.com> for ST-Ericsson
*
* This program is free software; you can redistribute it and/or modify
* it under the terms of the GNU General Public License version 2 as
* published by the Free Software Foundation.
*/

#ifndef ATBM_NL80211_TESTMODE_MSG_COPY_H
#define ATBM_NL80211_TESTMODE_MSG_COPY_H

/* example command structure for test purposes */
struct atbm_msg_test_t {
	int dummy;
};

/* example reply structure for test purposes */
struct atbm_reply_test_t {
	int dummy;
};

/* example event structure for test purposes */
struct atbm_event_test_t {
	int dummy;
};

enum atbm_msg_id {
	ATBM_MSG_TEST = 0,	/* for test purposes */
	ATBM_MSG_EVENT_TEST,	/* for test purposes */
	ATBM_MSG_SET_SNAP_FRAME,
	ATBM_MSG_EVENT_FRAME_DATA,
	ATBM_MSG_GET_TX_POWER_LEVEL,
	ATBM_MSG_GET_TX_POWER_RANGE,
	ATBM_MSG_SET_ADVANCE_SCAN_ELEMS,
	ATBM_MSG_SET_TX_QUEUE_PARAMS,
	ATBM_MSG_SET_POWER_SAVE,
	/* Add new IDs here */

	ATBM_MSG_ID_MAX,
};

enum atbm_nl80211_testmode_data_attributes {
	ATBM_TM_MSG_ID = 0x0001,	/* u32 type containing the ATBM message ID */
	ATBM_TM_MSG_DATA,	/* message payload */

	/* Max indicator so module test may add its own attributes */
	ATBM_TM_MSG_ATTR_MAX,
};

/**
 * atbm_msg_set_snap_frame - set SNAP frame format
 * @len: length of SNAP frame, if 0 SNAP frame disabled
 * @frame: SNAP frame format
 *
 * In this structure is difference between user space because
 * format and length have to be hidden
 *
 */
struct atbm_msg_set_snap_frame {
	u8 len;
	u8 frame[0];
};

/**
 * atbm_msg_set_txqueue_params - store Tx queue params
 * @user_priority: User priority for which TSPEC negotiated
 * @medium_time: Allowed medium time
 * @expiry_time: The expiry time of MSDU
 *
 */
struct atbm_msg_set_txqueue_params {
	u8 user_priority;
	u16 medium_time;
	u16 expiry_time;
};
#ifdef CONFIG_ATBM_APOLLO_TESTMODE
/**
 * atbm_tsm_stats - To retrieve the Transmit Stream Measurement stats
 * @actual_msrmt_start_time: The TSF at the time at which the measurement
 * started
 * @msrmt_duration: Duration for measurement
 * @peer_sta_addr: Peer STA address
 * @tid: TID for which measurements were made
 * @reporting_reason: Reason for report sent
 * @txed_msdu_count: The number of MSDUs transmitted for the specified TID
 * @msdu_discarded_count: The number of discarded MSDUs for the specified TID
 * @msdu_failed_count: The number of failed MSDUs for the specified TID
 * @multi_retry_count: The number of MSDUs which were retried
 * @qos_cfpolls_lost_count: The number of QOS CF polls frames lost
 * @avg_q_delay: Average queue delay
 * @avg_transmit_delay: Average transmit delay
 * @bin0_range: Delay range of the first bin (Bin 0)
 * @bin0: bin0 transmit delay histogram
 * @bin1: bin1 transmit delay histogram
 * @bin2: bin2 transmit delay histogram
 * @bin3: bin3 transmit delay histogram
 * @bin4: bin4 transmit delay histogram
 * @bin5: bin5 transmit delay histogram
 *
 */
struct atbm_tsm_stats {
	u64 actual_msrmt_start_time;
	u16 msrmt_duration;
	u8 peer_sta_addr[6];
	u8 tid;
	u8 reporting_reason;
	u32 txed_msdu_count;
	u32 msdu_discarded_count;
	u32 msdu_failed_count;
	u32 multi_retry_count;
	u32 qos_cfpolls_lost_count;
	u32 avg_q_delay;
	u32 avg_transmit_delay;
	u8 bin0_range;
	u32 bin0;
	u32 bin1;
	u32 bin2;
	u32 bin3;
	u32 bin00;
	u32 bin01;
	u32 bin02;
	u32 bin03;
	u32 bin04;
	u32 bin05;
	u32 bin06;
} __packed;

#endif
/**
 * atbm_msg_set_start_stop_tsm - To start or stop collecting TSM metrics in
 * apollo driver
 * @start: To start or stop collecting TSM metrics
 * @up: up for which metrics to be collected
 * @packetization_delay: Packetization period for this TID
 *
 */
struct atbm_msg_start_stop_tsm {
	u8 start;	/*1: To start, 0: To stop*/
	u8 up;
	u16 packetization_delay;
};

/**
 * power_save_elems - To enable/disable legacy power Save
 */
struct power_save_elems {
	int powerSave;
};


#define ATBM_TM_MAX_ATTRIB_SIZE 1024

#endif /* ATBM_NL80211_TESTMODE_MSG_COPY_H*/
