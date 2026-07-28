/*
 * WSM host interface (HI) interface for APOLLO mac80211 drivers
 *
 * Copyright (c) 2016, altobeam
 * Author:
 *
 * Based on CW1200 UMAC WSM API, which is
 * Copyright (C) ST-Ericsson SA 2010
 * Author: Stewart Mathers <stewart.mathers@stericsson.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#ifndef ATBM_APOLLO_WSM_H_INCLUDED
#define ATBM_APOLLO_WSM_H_INCLUDED

#ifdef LINUX_OS
#include <linux/spinlock.h>
#endif

struct atbm_common;

/* Bands */
/* Radio band 2.412 -2.484 GHz. */
#define WSM_PHY_BAND_2_4G		(0)

/* Radio band 4.9375-5.8250 GHz. */
#define WSM_PHY_BAND_5G			(1)

/* Transmit rates */
/* 1   Mbps            ERP-DSSS */
#define WSM_TRANSMIT_RATE_1		(0)

/* 2   Mbps            ERP-DSSS */
#define WSM_TRANSMIT_RATE_2		(1)

/* 5.5 Mbps            ERP-CCK, ERP-PBCC (Not supported) */
 #define WSM_TRANSMIT_RATE_5		(2) 

/* 11  Mbps            ERP-CCK, ERP-PBCC (Not supported) */
 #define WSM_TRANSMIT_RATE_11		(3) 

/* 22  Mbps            ERP-PBCC (Not supported) */
/* #define WSM_TRANSMIT_RATE_22		(4) */

/* 33  Mbps            ERP-PBCC (Not supported) */
/* #define WSM_TRANSMIT_RATE_33		(5) */

/* 6   Mbps   (3 Mbps) ERP-OFDM, BPSK coding rate 1/2 */
#define WSM_TRANSMIT_RATE_6		(6)

/* 9   Mbps (4.5 Mbps) ERP-OFDM, BPSK coding rate 3/4 */
#define WSM_TRANSMIT_RATE_9		(7)

/* 12  Mbps  (6 Mbps)  ERP-OFDM, QPSK coding rate 1/2 */
#define WSM_TRANSMIT_RATE_12		(8)

/* 18  Mbps  (9 Mbps)  ERP-OFDM, QPSK coding rate 3/4 */
#define WSM_TRANSMIT_RATE_18		(9)

/* 24  Mbps (12 Mbps)  ERP-OFDM, 16QAM coding rate 1/2 */
#define WSM_TRANSMIT_RATE_24		(10)

/* 36  Mbps (18 Mbps)  ERP-OFDM, 16QAM coding rate 3/4 */
#define WSM_TRANSMIT_RATE_36		(11)

/* 48  Mbps (24 Mbps)  ERP-OFDM, 64QAM coding rate 1/2 */
#define WSM_TRANSMIT_RATE_48		(12)

/* 54  Mbps (27 Mbps)  ERP-OFDM, 64QAM coding rate 3/4 */
#define WSM_TRANSMIT_RATE_54		(13)

/* 6.5 Mbps            HT-OFDM, BPSK coding rate 1/2 */
#define WSM_TRANSMIT_RATE_HT_6		(14)

/* 13  Mbps            HT-OFDM, QPSK coding rate 1/2 */
#define WSM_TRANSMIT_RATE_HT_13		(15)

/* 19.5 Mbps           HT-OFDM, QPSK coding rate 3/4 */
#define WSM_TRANSMIT_RATE_HT_19		(16)

/* 26  Mbps            HT-OFDM, 16QAM coding rate 1/2 */
#define WSM_TRANSMIT_RATE_HT_26		(17)

/* 39  Mbps            HT-OFDM, 16QAM coding rate 3/4 */
#define WSM_TRANSMIT_RATE_HT_39		(18)

/* 52  Mbps            HT-OFDM, 64QAM coding rate 2/3 */
#define WSM_TRANSMIT_RATE_HT_52		(19)

/* 58.5 Mbps           HT-OFDM, 64QAM coding rate 3/4 */
#define WSM_TRANSMIT_RATE_HT_58		(20)

/* 65  Mbps            HT-OFDM, 64QAM coding rate 5/6 */
#define WSM_TRANSMIT_RATE_HT_65		(21)

/* Scan types */
/* Foreground scan */
#define WSM_SCAN_TYPE_FOREGROUND	(0)

/* Background scan */
#define WSM_SCAN_TYPE_BACKGROUND	(1)

/* Auto scan */
#define WSM_SCAN_TYPE_AUTO		(2)

/* Scan flags */
/* Forced background scan means if the station cannot */
/* enter the power-save mode, it shall force to perform a */
/* background scan. Only valid when ScanType is */
/* background scan. */
#define WSM_SCAN_FLAG_FORCE_BACKGROUND	(BIT(0))

/* The WLAN device scans one channel at a time so */
/* that disturbance to the data traffic is minimized. */
#define WSM_SCAN_FLAG_SPLIT_METHOD	(BIT(1))

/* Preamble Type. Long if not set. */
#define WSM_SCAN_FLAG_SHORT_PREAMBLE	(BIT(2))

/* 11n Tx Mode. Mixed if not set. */
#define WSM_SCAN_FLAG_11N_GREENFIELD	(BIT(3))

#define WSM_FLAG_MAC_INSTANCE_1	(BIT(4))

#define WSM_FLAG_MAC_INSTANCE_0	(~(BIT(4)))

/* Scan constraints */
/* Maximum number of channels to be scanned. */
#define WSM_SCAN_MAX_NUM_OF_CHANNELS	(14)
#define WSM_FLAG_START_SMARTCONFIG    BIT(5)

#define WSM_FLAG_BEST_CHANNEL_START		BIT(6)
#define WSM_FLAG_BEST_CHANNEL_END		(~(BIT(6)))

/* The maximum number of SSIDs that the device can scan for. */
#define WSM_SCAN_MAX_NUM_OF_SSIDS	(2)
#ifdef CONFIG_ATBM_APOLLO_TESTMODE
/* Transmit flags */
/* Start Expiry time from the receipt of tx request */
#define WSM_TX_FLAG_EXPIRY_TIME		(BIT(0))
#endif /*CONFIG_ATBM_APOLLO_TESTMODE*/

/* Power management modes */
/* 802.11 Active mode */
#define WSM_PSM_ACTIVE			(0)

/* 802.11 PS mode */
#define WSM_PSM_PS			BIT(0)

/* Fast Power Save bit */
#define WSM_PSM_FAST_PS_FLAG		BIT(7)

/* Dynamic aka Fast power save */
#define WSM_PSM_FAST_PS			(BIT(0) | BIT(7))

/* Undetermined */
/* Note : Undetermined status is reported when the */
/* NULL data frame used to advertise the PM mode to */
/* the AP at Pre or Post Background Scan is not Acknowledged */
#define WSM_PSM_UNKNOWN			BIT(1)

/* Queue IDs */
/* best effort/legacy */
#define WSM_QUEUE_BEST_EFFORT		(0)

/* background */
#define WSM_QUEUE_BACKGROUND		(1)

/* video */
#define WSM_QUEUE_VIDEO			(2)

/* voice */
#define WSM_QUEUE_VOICE			(3)

/* HT TX parameters */
/* Non-HT */
#define WSM_HT_TX_NON_HT		(0)

/* Mixed format */
#define WSM_HT_TX_MIXED			(1)

/* Greenfield format */
#define WSM_HT_TX_GREENFIELD		(2)

#define WSM_HT_TX_SGI				(4)

#define WSM_HT_TX_WIDTH_40M			(BIT(3))

#define WSM_HT_TX_USE_MINRATE		(BIT(4))
/* STBC allowed */
#define WSM_HT_TX_STBC			(BIT(7))
#define WSM_NEED_TX_CONFIRM		(BIT(8))
#define WSM_TX_LINUX_HOST		(BIT(9))

/* EPTA prioirty flags for BT Coex */
/* default epta priority */
#define WSM_EPTA_PRIORITY_DEFAULT	4
/* use for normal data */
#define WSM_EPTA_PRIORITY_DATA		4
/* use for connect/disconnect/roaming*/
#define WSM_EPTA_PRIORITY_MGT		5
/* use for action frames */
#define WSM_EPTA_PRIORITY_ACTION	5
/* use for AC_VI data */
#define WSM_EPTA_PRIORITY_VIDEO		5
/* use for AC_VO data */
#define WSM_EPTA_PRIORITY_VOICE		6
/* use for EAPOL exchange */
#define WSM_EPTA_PRIORITY_EAPOL		7

/* TX status */
/* Frame was sent aggregated */
/* Only valid for WSM_SUCCESS status. */
#define WSM_TX_STATUS_AGGREGATION	(BIT(0))

/* Host should requeue this frame later. */
/* Valid only when status is WSM_REQUEUE. */
#define WSM_TX_STATUS_REQUEUE		(BIT(1))

/* Normal Ack */
#define WSM_TX_STATUS_NORMAL_ACK	(0<<2)

/* No Ack */
#define WSM_TX_STATUS_NO_ACK		(1<<2)

/* No explicit acknowledgement */
#define WSM_TX_STATUS_NO_EXPLICIT_ACK	(2<<2)

/* Block Ack */
/* Only valid for WSM_SUCCESS status. */
#define WSM_TX_STATUS_BLOCK_ACK		(3<<2)

/* RX status */
/* Unencrypted */
#define WSM_RX_STATUS_UNENCRYPTED	(0<<0)

/* WEP */
#define WSM_RX_STATUS_WEP		(1<<0)

/* TKIP */
#define WSM_RX_STATUS_TKIP		(2<<0)

/* AES */
#define WSM_RX_STATUS_AES		(3<<0)

/* WAPI */
#define WSM_RX_STATUS_WAPI		(4<<0)

/* Macro to fetch encryption subfield. */
#define WSM_RX_STATUS_ENCRYPTION(status) ((status) & 0x07)

/* Frame was part of an aggregation */
#define WSM_RX_STATUS_AGGREGATE		(BIT(3))

/* Frame was first in the aggregation */
#define WSM_RX_STATUS_AGGREGATE_FIRST	(BIT(4))

/* Frame was last in the aggregation */
#define WSM_RX_STATUS_AGGREGATE_LAST	(BIT(5))

/* Indicates a defragmented frame */
#define WSM_RX_STATUS_DEFRAGMENTED	(BIT(6))

/* Indicates a Beacon frame */
#define WSM_RX_STATUS_BEACON		(BIT(7))

/* Indicates STA bit beacon TIM field */
#define WSM_RX_STATUS_TIM		(BIT(8))

/* Indicates Beacon frame's virtual bitmap contains multicast bit */
#define WSM_RX_STATUS_MULTICAST		(BIT(9))

/* Indicates frame contains a matching SSID */
#define WSM_RX_STATUS_MATCHING_SSID	(BIT(10))

/* Indicates frame contains a matching BSSI */
#define WSM_RX_STATUS_MATCHING_BSSI	(BIT(11))

/* Indicates More bit set in Framectl field */
#define WSM_RX_STATUS_SMARTCONFIG		(BIT(12))

/* Indicates frame received during a measurement process */
#define WSM_RX_STATUS_MEASUREMENT	(BIT(13))

/* Indicates frame received as an HT packet */
#define WSM_RX_STATUS_HT		(BIT(14))

/* Indicates frame received with STBC */
#define WSM_RX_STATUS_STBC		(BIT(15))

/* Indicates Address 1 field matches dot11StationId */
#define WSM_RX_STATUS_ADDRESS1		(BIT(16))

/* Indicates Group address present in the Address 1 field */
#define WSM_RX_STATUS_GROUP		(BIT(17))

/* Indicates Broadcast address present in the Address 1 field */
#define WSM_RX_STATUS_BROADCAST		(BIT(18))

/* Indicates group key used with encrypted frames */
#define WSM_RX_STATUS_GROUP_KEY		(BIT(19))
#define WSM_RX_STATUS_CHKSUM_ERROR (BIT(21))
/*indicates rx 40M*/
#define WSM_RX_STATUS_RX_40M		(BIT(22))
/* Macro to fetch encryption key index. */
#define WSM_RX_STATUS_KEY_IDX(status)	(((status >> 20)) & 0x0F)
#define WSM_RX_STATUS_SHORT_GI      (BIT(24))

/* Frame Control field starts at Frame offset + 2 */
#define WSM_TX_2BYTES_SHIFT		(BIT(7))

/* Join mode */
/* IBSS */
#define WSM_JOIN_MODE_IBSS		(0)

/* BSS */
#define WSM_JOIN_MODE_BSS		(1)

/* PLCP preamble type */
/* For long preamble */
#define WSM_JOIN_PREAMBLE_LONG		(0)

/* For short preamble (Long for 1Mbps) */
#define WSM_JOIN_PREAMBLE_SHORT		(1)

/* For short preamble (Long for 1 and 2Mbps) */
#define WSM_JOIN_PREAMBLE_SHORT_2	(2)

/* Join flags */
/* Unsynchronized */
#define WSM_JOIN_FLAGS_UNSYNCRONIZED	BIT(0)
/* The BSS owner is a P2P GO */
#define WSM_JOIN_FLAGS_P2P_GO		BIT(1)
/* Force to join BSS with the BSSID and the
 * SSID specified without waiting for beacons. The
 * ProbeForJoin parameter is ignored. */
#define WSM_JOIN_FLAGS_FORCE		BIT(2)
/* Give probe request/response higher
 * priority over the BT traffic */
#define WSM_JOIN_FLAGS_PRIO		BIT(3)

/* Key types */
#define WSM_KEY_TYPE_WEP_DEFAULT	(0)
#define WSM_KEY_TYPE_WEP_PAIRWISE	(1)
#define WSM_KEY_TYPE_TKIP_GROUP		(2)
#define WSM_KEY_TYPE_TKIP_PAIRWISE	(3)
#define WSM_KEY_TYPE_AES_GROUP		(4)
#define WSM_KEY_TYPE_AES_PAIRWISE	(5)
#define WSM_KEY_TYPE_WAPI_GROUP		(6)
#define WSM_KEY_TYPE_WAPI_PAIRWISE	(7)
#define WSM_KEY_TYPE_IGTK_GROUP	    (8)

/* Key indexes */
#define ATBMWIFI_WSM_KEY_MAX_INDEX	(15)
#define WSM_KEY_MAX_INDEX		(10)

/* ACK policy */
#define WSM_ACK_POLICY_NORMAL		(0)
#define WSM_ACK_POLICY_NO_ACK		(1)

/* Start modes */
#define WSM_START_MODE_AP		(0)	/* Mini AP */
#define WSM_START_MODE_P2P_GO		(1)	/* P2P GO */
#define WSM_START_MODE_P2P_DEV		(2)	/* P2P device */
#ifdef ATBM_SUPPORT_PKG_MONITOR
#define WSM_START_MODE_MONITOR_DEV	(3)
#endif

/* SetAssociationMode MIB flags */
#define WSM_ASSOCIATION_MODE_USE_PREAMBLE_TYPE		(BIT(0))
#define WSM_ASSOCIATION_MODE_USE_HT_MODE		(BIT(1))
#define WSM_ASSOCIATION_MODE_USE_BASIC_RATE_SET		(BIT(2))
#define WSM_ASSOCIATION_MODE_USE_MPDU_START_SPACING	(BIT(3))
#define WSM_ASSOCIATION_MODE_SNOOP_ASSOC_FRAMES		(BIT(4))

/* RcpiRssiThreshold MIB flags */
#define WSM_RCPI_RSSI_THRESHOLD_ENABLE	(BIT(0))
#define WSM_RCPI_RSSI_USE_RSSI		(BIT(1))
#define WSM_RCPI_RSSI_DONT_USE_UPPER	(BIT(2))
#define WSM_RCPI_RSSI_DONT_USE_LOWER	(BIT(3))

/* Update-ie constants */
#define WSM_UPDATE_IE_BEACON		(BIT(0))
#define WSM_UPDATE_IE_PROBE_RESP	(BIT(1))
#define WSM_UPDATE_IE_PROBE_REQ		(BIT(2))

/* WSM events */
/* Error */
#define WSM_EVENT_ERROR			(0)

/* BSS lost */
#define WSM_EVENT_BSS_LOST		(2)

/* BSS connet */
#define WSM_EVENT_BSS_CONNECT		(1)

/*sdio channel*/
#define WSM_EVENT_SDIO_INPUTCHAN_EVNET		(3)

/*STA add*/
#define WSM_EVENT_STA_ADD		(4)

/*STA loss*/
#define WSM_EVENT_STA_LOSS		(5)

/*Smart cfg success*/
#define WSM_EVENT_SMT_SUCCESS		(6)

/*Smart cfg fail*/
#define WSM_EVENT_SMT_FAIL		(7)

/*ETF Rx Msg*/
#define WSM_EVENT_ETF_RX_MSG		(8)

/*FW Uart Msg*/
#define WSM_EVENT_FW_UART_MSG		(9)

/*HOST rmmod*/
#define WSM_EVENT_HOST_RMMOD		(10)

/*HOST insmod*/
#define WSM_EVENT_HOST_INSMOD		(11)

/*HOST wakeup reason*/
#define WSM_EVENT_HOST_WAKEUP_REASON		(12)

/*HOST disconnect reason*/
#define WSM_EVENT_HOST_DISCONN_REASON		(13)

/*HOST connect fail reason*/
#define WSM_EVENT_HOST_CONN_ERR_REASON		(14)

/*HOST customer command request data*/
#define WSM_EVENT_HOST_CUSTOMER_CMD_REQ     (15)

/*HOST customer private event*/
#define WSM_EVENT_HOST_CUSTOMER_PRIVATE     (0x4321)

/*HOST customer private event*/
#define WSM_EVENT_ATCMD_RECIVE     			(0x5678)

/* MAC Addr Filter */
#define WSM_MIB_ID_MAC_ADDR_FILTER	0x1030

/* MIB IDs */
/* 4.1  dot11StationId */
#define WSM_MIB_ID_DOT11_STATION_ID		0x0000

/* 4.2  dot11MaxtransmitMsduLifeTime */
#define WSM_MIB_ID_DOT11_MAX_TRANSMIT_LIFTIME	0x0001

/* 4.3  dot11MaxReceiveLifeTime */
#define WSM_MIB_ID_DOT11_MAX_RECEIVE_LIFETIME	0x0002

/* 4.4  dot11SlotTime */
#define WSM_MIB_ID_DOT11_SLOT_TIME		0x0003

/* 4.5  dot11GroupAddressesTable */
#define WSM_MIB_ID_DOT11_GROUP_ADDRESSES_TABLE	0x0004
#define WSM_MAX_GRP_ADDRTABLE_ENTRIES		8

/* 4.6  dot11WepDefaultKeyId */
#define WSM_MIB_ID_DOT11_WEP_DEFAULT_KEY_ID	0x0005

/* 4.7  dot11CurrentTxPowerLevel */
#define WSM_MIB_ID_DOT11_CURRENT_TX_POWER_LEVEL	0x0006

/* 4.8  dot11RTSThreshold */
#define WSM_MIB_ID_DOT11_RTS_THRESHOLD		0x0007
#define WSM_MIB_ID_DOT11_TRANSMIT_RETRY_CNT		0x0008

/* 4.9  NonErpProtection */
#define WSM_MIB_ID_NON_ERP_PROTECTION		0x1000

/* 4.10 ArpIpAddressesTable */
#define WSM_MIB_ID_ARP_IP_ADDRESSES_TABLE	0x1001
#define WSM_MAX_ARP_IP_ADDRTABLE_ENTRIES	1

/* 4.11 TemplateFrame */
#define WSM_MIB_ID_TEMPLATE_FRAME		0x1002

/* 4.12 RxFilter */
#define WSM_MIB_ID_RX_FILTER			0x1003

/* 4.13 BeaconFilterTable */
#define WSM_MIB_ID_BEACON_FILTER_TABLE		0x1004

/* 4.14 BeaconFilterEnable */
#define WSM_MIB_ID_BEACON_FILTER_ENABLE		0x1005

/* 4.15 OperationalPowerMode */
#define WSM_MIB_ID_OPERATIONAL_POWER_MODE	0x1006

/* 4.16 BeaconWakeUpPeriod */
#define WSM_MIB_ID_BEACON_WAKEUP_PERIOD		0x1007

/* 4.17 RcpiRssiThreshold */
#define WSM_MIB_ID_RCPI_RSSI_THRESHOLD		0x1009

/* 4.18 StatisticsTable */
#define WSM_MIB_ID_STATISTICS_TABLE		0x100A

/* 4.19 IbssPsConfig */
#define WSM_MIB_ID_IBSS_PS_CONFIG		0x100B

/* 4.20 CountersTable */
#define WSM_MIB_ID_COUNTERS_TABLE		0x100C

/* 4.21 BlockAckPolicy */
#define WSM_MIB_ID_BLOCK_ACK_POLICY		0x100E

/* 4.22 OverrideInternalTxRate */
#define WSM_MIB_ID_OVERRIDE_INTERNAL_TX_RATE	0x100F

/* 4.23 SetAssociationMode */
#define WSM_MIB_ID_SET_ASSOCIATION_MODE		0x1010

/* 4.24 UpdateEptaConfigData */
#define WSM_MIB_ID_UPDATE_EPTA_CONFIG_DATA	0x1011

/* 4.25 SelectCcaMethod */
#define WSM_MIB_ID_SELECT_CCA_METHOD		0x1012

/* 4.26 SetUpasdInformation */
#define WSM_MIB_ID_SET_UAPSD_INFORMATION	0x1013

/* 4.27 SetAutoCalibrationMode  WBF00004073 */
#define WSM_MIB_ID_SET_AUTO_CALIBRATION_MODE	0x1015

/* 4.28 SetTxRateRetryPolicy */
#define WSM_MIB_ID_SET_TX_RATE_RETRY_POLICY	0x1016

/* 4.29 SetHostMessageTypeFilter */
#define WSM_MIB_ID_SET_HOST_MSG_TYPE_FILTER	0x1017

/* 4.30 P2PFindInfo */
#define WSM_MIB_ID_P2P_FIND_INFO		0x1018

/* 4.31 P2PPsModeInfo */
#define WSM_MIB_ID_P2P_PS_MODE_INFO		0x1019

/* 4.32 SetEtherTypeDataFrameFilter */
#define WSM_MIB_ID_SET_ETHERTYPE_DATAFRAME_FILTER 0x101A

/* 4.33 SetUDPPortDataFrameFilter */
#define WSM_MIB_ID_SET_UDPPORT_DATAFRAME_FILTER	0x101B

/* 4.34 SetMagicDataFrameFilter */
#define WSM_MIB_ID_SET_MAGIC_DATAFRAME_FILTER	0x101C

/* This is the end of specification. */

/* 4.35 P2PDeviceInfo */
#define WSM_MIB_ID_P2P_DEVICE_INFO		0x101D

/* 4.36 SetWCDMABand */
#define WSM_MIB_ID_SET_WCDMA_BAND		0x101E

/* 4.37 GroupTxSequenceCounter */
#define WSM_MIB_ID_GRP_SEQ_COUNTER		0x101F

/* 4.38 ProtectedMgmtPolicy */
#define WSM_MIB_ID_PROTECTED_MGMT_POLICY	0x1020

/* 4.39 SetHtProtection */
#define WSM_MIB_ID_SET_HT_PROTECTION		0x1021

/* 4.40 GPIO Command */
#define WSM_MIB_ID_GPIO_COMMAND			0x1022

/* 4.41 TSF Counter Value */
#define WSM_MIB_ID_TSF_COUNTER			0x1023

/* Test Purposes Only */
#define WSM_MIB_ID_BLOCK_ACK_INFO		0x100D

/* 4.42 UseMultiTxConfMessage */
#define WSM_MIB_USE_MULTI_TX_CONF		0x1024

/* 4.43 Keep-alive period */
#define WSM_MIB_ID_KEEP_ALIVE_PERIOD		0x1025

/* 4.44 Disable BSSID filter */
#define WSM_MIB_ID_DISABLE_BSSID_FILTER		0x1026

/* Inactivity */
#define WSM_MIB_ID_SET_INACTIVITY		0x1035

/* MAC Addr Filter */
#define WSM_MIB_ID_MAC_ADDR_FILTER		0x1030

#ifdef MCAST_FWDING
/* 4.51 Set Forwarding Offload */
#define WSM_MIB_ID_FORWARDING_OFFLOAD		0x1033
#endif

#ifdef IPV6_FILTERING
/* IpV6 Addr Filter */
/* 4.52 Neighbor solicitation IPv6 address table */
#define WSM_MIB_IP_IPV6_ADDR_FILTER		0x1032
#define WSM_MIB_ID_NS_IP_ADDRESSES_TABLE	0x1034
#define WSM_MAX_NDP_IP_ADDRTABLE_ENTRIES	1
#endif /*IPV6_FILTERING*/

#define WSM_MIB_ID_ZERO_COUNTERS_TABLE		0x1037
#define WSM_MIB_ID_DBG_PRINT_TO_HOST		0x1038
#define WSM_MIB_ID_FW_CMD					0x1039
#define WSM_MIB_ID_MAC_ADDRESS_FROM_EFUSE   0x103a
#define WSM_MIB_ID_SET_EFUSE_DATA			0x103b
#define WSM_MIB_ID_GET_DATA_FROM_EFUSE		0x103c
#define WSM_MIB_ID_SET_EFUSE_MAC			0x103d
#define WSM_MIB_ID_START_WOL				0x103e
#define WSM_MIB_ID_GET_ETF_RX_STATS			0x103f
#define WSM_MIB_ID_SET_EFUSE_DATA_ZHUANG	0x1040
#define WSM_MIB_ID_SMARTCONFIG_START		0x1041
#define WSM_MIB_ID_GET_EFUSE_CUR_STATUS		0x1042
#define WSM_MIB_ID_SET_DUTY_RATIO			0x1043


#define WSM_MIB_ID_GET_RATE					0x1050

#define WSM_MIB_ID_GET_SIGMSTAR_256BITSEFUSE  0x1051
#define WSM_MIB_ID_SET_SIGMSTAR_256BITSEFUSE  0x1052

#define WSM_MIB_ID_GET_CHANNEL_IDLE			0x1053
#define WSM_MIB_ID_CHANNEL_TEST_START		0x1054

//#define WSM_START_FIND_ID                 0x0019 //used by efuse change data
//#define WSM_START_FIND_RESP_ID            0x0419 //used by efuse change data
#define WSM_STOP_FIND_ID					 0x001A
#define WSM_STOP_FIND_RESP_ID                0x041A

/*4.54 request buffer id*/
#define WSM_REQUEST_BUFFER_REQ_ID           0x0023
#define WSM_REQUEST_BUFFER_REQ_CNF_ID       0X0423

/*4.55 This device-to-host message returns the */
/*results for a previously queued transmit request */

#define WSM_CNF_BASE                      0x0400
#define WSM_TX_REQ_ID                     0x0404
#define WSM_GIVE_BUFFER_REQ_ID            0x0422
#define WSM_LEGACY_MULTI_TX_CNF_ID        0x041E

#define WSM_IND_BASE 					   0x0800
#define WSM_STARTUP_IND_ID 					0x0801
#define WSM_TRACE_IND_ID 					0x0802
#define WSM_RECEIVE_INDICATION_ID           0x0804
#define WSM_EVENT_INDICATION_ID             0x0805
#define WSM_SCAN_COMPLETE_IND_ID 			0x0806
#define WSM_SWITCH_CHANNLE_IND_ID           0x080A
#define WSM_SET_PM_MODE_CMPL_IND_ID          0x0809
#define WSM_FIND_CMPL_IND_ID                 0x080B
#define WSM_SUSP_RESUME_TX_IND_ID            0x080C
#define WSM_DEBUG_IND_ID 						0x080E
#define WSM_DEBUG_PRINT_IND_ID					0x0810
#define WSM_MULTI_RECEIVE_INDICATION_ID		 	0x0811
#define WSM_SMARTCONFIG_INDICATION_ID		 	0x0812
#define WSM_SINGLE_CHANNEL_MULTI_RECEIVE_INDICATION_ID	 0x0813
#define WSM_RECEIVE2_INDICATION_ID		 	 	0x0814


#ifdef CONFIG_ATBM_SDIO_ATCMD
#define WSM_SDIO_ATCMD_BASE				0x1000
#define	WSM_SDIO_ATCMD_DIRECT_ID		0x1001
#endif


/* Frame template types */
#define WSM_FRAME_TYPE_PROBE_REQUEST	(0)
#define WSM_FRAME_TYPE_BEACON		(1)
#define WSM_FRAME_TYPE_NULL		(2)
#define WSM_FRAME_TYPE_QOS_NULL		(3)
#define WSM_FRAME_TYPE_PS_POLL		(4)
#define WSM_FRAME_TYPE_PROBE_RESPONSE	(5)
#define WSM_FRAME_TYPE_ARP_REPLY        (6)

#ifdef IPV6_FILTERING
#define WSM_FRAME_TYPE_NA               (7)
#endif /*IPV6_FILTERING*/

#define WSM_FRAME_GREENFIELD		(0x80)	/* See 4.11 */

/* Status */
/* The WSM firmware has completed a request */
/* successfully. */
#define WSM_STATUS_SUCCESS              (0)

/* This is a generic failure code if other error codes do */
/* not apply. */
#define WSM_STATUS_FAILURE              (1)

/* A request contains one or more invalid parameters. */
#define WSM_INVALID_PARAMETER           (2)

/* The request cannot perform because the device is in */
/* an inappropriate mode. */
#define WSM_ACCESS_DENIED               (3)

/* The frame received includes a decryption error. */
#define WSM_STATUS_DECRYPTFAILURE       (4)

/* A MIC failure is detected in the received packets. */
#define WSM_STATUS_MICFAILURE           (5)

/* The transmit request failed due to retry limit being */
/* exceeded. */
#define WSM_STATUS_RETRY_EXCEEDED       (6)

/* The transmit request failed due to MSDU life time */
/* being exceeded. */
#define WSM_STATUS_TX_LIFETIME_EXCEEDED (7)

/* The link to the AP is lost. */
#define WSM_STATUS_LINK_LOST            (8)

/* No key was found for the encrypted frame */
#define WSM_STATUS_NO_KEY_FOUND         (9)

/* Jammer was detected when transmitting this frame */
#define WSM_STATUS_JAMMER_DETECTED      (10)

#define WSM_STATUS_NOEFFECT              (14)

/* The message should be requeued later. */
/* This is applicable only to Transmit */
#define WSM_REQUEUE                     (11)
/*The status is cmdCrc Error */
#define WSM_CMD_CRC_ERRO              (14)
/*The status is dataCrc Error */
#define WSM_DATA_CRC_ERRO              (15)
/* Advanced filtering options */
#define WSM_MAX_FILTER_ELEMENTS		(4)

#define WSM_FILTER_ACTION_IGNORE	(0)
#define WSM_FILTER_ACTION_FILTER_IN	(1)
#define WSM_FILTER_ACTION_FILTER_OUT	(2)

#define WSM_FILTER_PORT_TYPE_DST	(0)
#define WSM_FILTER_PORT_TYPE_SRC	(1)

#define MAX_WSM_BUF_LEN (1632)//

struct wsm_hdr {
	__le16 len;
	__le16 id;
};
struct wsm_hdr_tx {
#ifndef SPI_BUS
	__le32 flag;
#endif
#ifdef  ATBM_WSM_SDIO_TX_MULT
	__le16 tx_len;
	__le16 tx_id;
#endif
#ifdef USB_BUS_BUG
	__le16 usb_len;
	__le16 usb_id;
#endif	
	__le16 len;
	__le16 id;
};

struct wsm_hdr_tx_test {
	__le32 flag;
	__le16 len;
	__le16 id;
//	__le32 bufused;
};
#define WSM_TX_SEQ_MAX			(7)
#define WSM_RX_SEQ_MAX			(7)
#define WSM_TX_SDIO_SEQ_MAX			(0x3f)
#define WSM_TX_SEQ(seq)			\
		((seq & WSM_TX_SEQ_MAX) << 13)
#define WSM_TX_FLAG(channel) (channel &0x3f)
#define WSM_TX_FLAG_CHECK(id) ((id &0xffff)<<16)
#define WSM_TX_LINK_ID_MAX		(0x0F)
#define WSM_TX_LINK_ID(link_id)		\
		((link_id & WSM_TX_LINK_ID_MAX) << 6)

#define WSM_TX_IF_ID_MAX		(0x0F)
#define WSM_TX_IF_ID(if_id)		\
		((if_id & WSM_TX_IF_ID_MAX) << 6)

#define MAX_BEACON_SKIP_TIME_MS 1000


#define WSM_CMD_LAST_CHANCE_TIMEOUT (HZ * 20/2)
#define WSM_CMD_EXTENDED_TIMEOUT (HZ * 20 / 2)

#define WSM_RI_GET_PEER_ID_FROM_FLAGS(_f)         (((_f)&(0xF<<25)>>25))


/* ******************************************************************** */
/* WSM capcbility							*/

//#define WSM_STARTUP_IND_ID 0x0801
struct wsm_caps {
	u16 numInpChBufs;
	u16 sizeInpChBuf;
	u16 hardwareId;
	u16 hardwareSubId;
	u32 firmwareCap;
	u16 firmwareType;
	u16 firmwareApiVer;
	u16 firmwareBuildNumber;
	u16 firmwareVersion;
	u32 HiHwCnfBufaddr;
	int firmwareReady;
	u32 exceptionaddr;
	u32 NumOfHwXmitedAddr;
};

#define CAPABLITIES_2_4_GHZ 			(1<<0)
#define CAPABLITIES_NEW_RATE_POLICY 	(1<<1)
#define CAPABLITIES_SDIO_TX_LIST_CHECK 	(1<<2)

/* ******************************************************************** */
/* WSM commands								*/

#define WSM_CONFIGURATION_REQ_ID 0x0009
#define WSM_CONFIGURATION_RESP_ID 0x0409
struct wsm_tx_power_range {
	int min_power_level;
	int max_power_level;
	u32 stepping;
};

/* 3.1 */
struct wsm_configuration {
	/* [in] */ u32 dot11MaxTransmitMsduLifeTime;
	/* [in] */ u32 dot11MaxReceiveLifeTime;
	/* [in] */ u32 dot11RtsThreshold;
	/* [in, out] */ u8 *dot11StationId;
	/* [in] */ u8 *dpdData;
	/* [in] */ u32 dpdData_size;
	/* [out] */ u8 dot11FrequencyBandsSupported;
	/* [out] */ u32 supportedRateMask;
	/* [out] */ struct wsm_tx_power_range txPowerRange[2];
};

int wsm_configuration(struct atbm_common *hw_priv,
		      struct wsm_configuration *arg,
		      int if_id);

#define WSM_FIRMWARE_CHECK_ID 0x0002
#define WSM_FIRMWARE_CHECK_CONFIRM_ID 0x0402

/* 3.3 */
#define WSM_RESET_REQ_ID 0x000A
#define WSM_RESET_RESP_ID 0x040A
struct wsm_reset {
	/* [in] */ int link_id;
	/* [in] */ bool reset_statistics;
};

int wsm_reset(struct atbm_common *hw_priv, const struct wsm_reset *arg,
	      int if_id);

/* 3.5 */
#define WSM_READ_MIB_REQ_ID 0x0005
#define WSM_READ_MIB_RESP_ID 0x0405
int wsm_read_mib(struct atbm_common *hw_priv, u16 mibId, void *buf,
		 size_t buf_size,int if_id);

/* 3.7 */
#define WSM_WRITE_MIB_REQ_ID 0x0006
#define WSM_WRITE_MIB_RESP_ID 0x0406
int wsm_write_mib(struct atbm_common *hw_priv, u16 mibId, void *buf,
		  size_t buf_size, int if_id);

struct wsm_generic_req{
	u32 status;
};

#define WSM_SCAN_REQ_ID 0x000A
#define WSM_SCAN_RESP_ID 0x040A

#define WSM_SCAN_INFO_REQ_ID 0x000B
#define WSM_SCAN_INFO_RESP_ID 0x040B


#define WSM_SCAN_RESULT_MAX_CNT 30

struct wsm_scan_result_info{
	u8 ssid[33];
	u8 bssid[6];
	u8 ssidlen;
	u8 channel;
	u8 ht:1,
	   wpa:1,
	   rsn:1,
	   wps:1,
	   p2p:1,
	   b40M:1,
	   encrypt:1;
	s8 rssi;
	short reserved[2];
};

struct wsm_scan_result_req{
	u32 status;
	u16 scan_cnt;
	u8 remain;
	u8 offset;
	struct wsm_scan_result_info scan_info[WSM_SCAN_RESULT_MAX_CNT];
};

struct wsm_scan_req{
	u32 status;
};

int wsm_set_scan(struct atbm_common *hw_priv, struct wsm_scan_req *scan_req);
int wsm_get_scan_info(struct atbm_common *hw_priv, void *buffer,size_t buf_size);


/* 3.9 */
#define WSM_START_SCAN_REQ_ID 0x0007
#define WSM_START_SCAN_RESP_ID 0x0407
struct wsm_ssid {
	u8 ssid[32];
	u32 length;
};

struct wsm_scan_ch {
	u16 number;
	u32 minChannelTime;
	u32 maxChannelTime;
	u32 txPowerLevel;
};

/* 3.13 */
//#define WSM_SCAN_COMPLETE_IND_ID 0x0806
struct wsm_scan_complete {
	/* WSM_STATUS_... */
	u32 status;

	/* WSM_PSM_... */
	u8 psm;

	/* Number of channels that the scan operation completed. */
	u8 numChannels;

	/* Duty Ratio for per channel */
	u8 busy_ratio[14];
	
#ifdef ROAM_OFFLOAD
	u16 reserved;
#endif /*ROAM_OFFLOAD*/
};

typedef void (*wsm_scan_complete_cb) (struct atbm_common *hw_priv,
				      struct wsm_scan_complete *arg);

/* 3.9 */
struct wsm_scan {
	/* WSM_PHY_BAND_... */
	/* [in] */ u8 band;

	/* WSM_SCAN_TYPE_... */
	/* [in] */ u8 scanType;

	/* WSM_SCAN_FLAG_... */
	/* [in] */ u8 scanFlags;

	/* WSM_TRANSMIT_RATE_... */
	/* [in] */ u8 maxTransmitRate;

	/* Interval period in TUs that the device shall the re- */
	/* execute the requested scan. Max value supported by the device */
	/* is 256s. */
	/* [in] */ u32 autoScanInterval;

	/* Number of probe requests (per SSID) sent to one (1) */
	/* channel. Zero (0) means that none is send, which */
	/* means that a passive scan is to be done. Value */
	/* greater than zero (0) means that an active scan is to */
	/* be done. */
	/* [in] */ u32 numOfProbeRequests;

	/* Number of channels to be scanned. */
	/* Maximum value is WSM_SCAN_MAX_NUM_OF_CHANNELS. */
	/* [in] */ u8 numOfChannels;

	/* Number of SSID provided in the scan command (this */
	/* is zero (0) in broadcast scan) */
	/* The maximum number of SSIDs is WSM_SCAN_MAX_NUM_OF_SSIDS. */
	/* [in] */ u8 numOfSSIDs;

	/* The delay time (in microseconds) period */
	/* before sending a probe-request. */
	/* [in] */ u8 probeDelay;

	/* SSIDs to be scanned [numOfSSIDs]; */
	/* [in] */ struct wsm_ssid *ssids;

	/* Channels to be scanned [numOfChannels]; */
	/* [in] */ struct wsm_scan_ch *ch;
};

int wsm_scan(struct atbm_common *hw_priv, const struct wsm_scan *arg,
			int if_id);

/* 3.11 */
#define WSM_STOP_SCAN_REQ_ID 0x0008
#define WSM_STOP_SCAN_RESP_ID 0x0408
int wsm_stop_scan(struct atbm_common *hw_priv, int if_id);

/* 3.14 */
struct wsm_tx_confirm {
	/* Packet identifier used in wsm_tx. */
	/* [out] */ u32 packetID;

	/* WSM_STATUS_... */
	/* [out] */ u32 status;

	/* WSM_TRANSMIT_RATE_... */
	/* [out] */ u8 txedRate;

	/* The number of times the frame was transmitted */
	/* without receiving an acknowledgement. */
	/* [out] */ u8 ackFailures;

	/* WSM_TX_STATUS_... */
	/* [out] */ u16 flags;

	/* The total time in microseconds that the frame spent in */
	/* the WLAN device before transmission as completed. */
	/* [out] */ u32 mediaDelay;

	/* The total time in microseconds that the frame spent in */
	/* the WLAN device before transmission was started. */
	/* [out] */ u32 txQueueDelay;

	/* [out]*/ u32 link_id;

	/*[out]*/ int if_id;
};

/* 3.15 */
typedef void (*wsm_tx_confirm_cb) (struct atbm_common *hw_priv,
				   struct wsm_tx_confirm *arg);

#define WSM_TRANSMIT_REQ_MSG_ID		0x0004

/* Note that ideology of wsm_tx struct is different against the rest of
 * WSM API. wsm_hdr is /not/ a caller-adapted struct to be used as an input
 * argument for WSM call, but a prepared bytestream to be sent to firmware.
 * It is filled partly in atbm_tx, partly in low-level WSM code.
 * Please pay attention once again: ideology is different.
 *
 * Legend:
 * - [in]: atbm_tx must fill this field.
 * - [wsm]: the field is filled by low-level WSM.
 */
struct wsm_tx {
	/* common WSM header */
	/* [in/wsm] */ struct wsm_hdr_tx hdr;

	/* Packet identifier that meant to be used in completion. */
	/* [in] */ __le32 packetID;

	/* WSM_TRANSMIT_RATE_... */
	/* [in] */ u8 maxTxRate;

	/* WSM_QUEUE_... */
	/* [in] */ u8 queueId;

	/* True: another packet is pending on the host for transmission. */
	/* [wsm] */ u8 more;

	/* Bit 0 = 0 - Start expiry time from first Tx attempt (default) */
	/* Bit 0 = 1 - Start expiry time from receipt of Tx Request */
	/* Bits 3:1  - PTA Priority */
	/* Bits 6:4  - Tx Rate Retry Policy */
	/* Bit 7 - Reserved */
	/* [in] */ u8 flags;

	/* Should be 0. */
	/* [in] */ __le32 reserved;

	/* The elapsed time in TUs, after the initial transmission */
	/* of an MSDU, after which further attempts to transmit */
	/* the MSDU shall be terminated. Overrides the global */
	/* dot11MaxTransmitMsduLifeTime setting [optional] */
	/* Device will set the default value if this is 0. */
	/* [wsm] */ __le32 expireTime;

	/* WSM_HT_TX_... */
	/* [in] */ __le32 htTxParameters;
	
};

/* = sizeof(generic hi hdr) + sizeof(wsm hdr) + sizeof(alignment) */
#define WSM_TX_EXTRA_HEADROOM (28+4)

/* 3.16 */
struct wsm_rx {
	/* WSM_STATUS_... */
	/* [out] */ u32 status;

	/* Specifies the channel of the received packet. */
	/* [out] */ u16 channelNumber;

	/* WSM_TRANSMIT_RATE_... */
	/* [out] */ u8 rxedRate;

	/* This value is expressed in signed Q8.0 format for */
	/* RSSI and unsigned Q7.1 format for RCPI. */
	/* [out] */ u8 rcpiRssi;

	/* WSM_RX_STATUS_... */
	/* [out] */ u32 flags;
	
	/*width 40M params*/
	/*[in]*/	u32 channel_type;

	/* An 802.11 frame. */
	/* [out] */ void *frame;

	/* Size of the frame */
	/* [out] */ size_t frame_size;

	/* Link ID */
	/* [out] */ int link_id;
	/* [out] */ int if_id;
};
struct wsm_multi_rx {
	u16 MsgLen;
	u16 MsgId;
	u8  RxFrameNum;
	u8  reserved[3];	
};
/* = sizeof(generic hi hdr) + sizeof(wsm hdr) */
#define WSM_RX_EXTRA_HEADROOM (16)

#ifdef CONFIG_ATBM_SDIO_ATCMD
#define MAX_SDIO_EVENT_BUFFER_LEN 1500
#define SDIO_EVENT_IND_LEN	504
#else
#define MAX_SDIO_EVENT_BUFFER_LEN 504
#define SDIO_EVENT_IND_LEN	504
#endif

#define CONNECT_FLAG_WMM BIT(0)

struct atbmwifi_ieee80211_mcs_info{
	u8 rx_mask[10];
	u16 rx_highest;
	u8 tx_params;
	u8 reserved[3];
}__packed;

struct atbmwifi_ieee80211_sta_ht_cap{
	u16 cap;
	u8 ht_supported;
	u8 ampdu_factor;
	u8 ampdu_density;
	struct atbmwifi_ieee80211_mcs_info mcs;
};

struct cfg80211_rate{
	u32 basic_rates;
	u32 support_rates;
	struct atbmwifi_ieee80211_sta_ht_cap ht_cap;
	u16 ht;
	u16 channel_type;
};

struct bss_info{
	u16 channel_num;

	u8 channel_type;
	u8 bssid[6];
	u8 dtim_period;

	u8 aid;
	u8 parameter_set_count;

	u8 uapsd_max_sp_len;
	s8 rssi;

	u16 capability;

	u32 wpa:1,
		wps:1,
		p2p:1,
		uapsd_supported:1,
		wmm_used:1,
		has_erp_value:1,
		rate_11b:1,
		ht:1,
		short_preamble:1,
		use_cts_prot:1,
		use_short_slot:1,
		ps_enabled:1,
		ht_40M:1,
		greenfiled:1,
		short_gi:1,
		dtim_check:1;

	u16 beacon_interval;

	u16 len_information_elements;
	u8 *information_elements;

	struct cfg80211_rate rate;

	void *rc_priv;	
}__packed;

struct HostConnectEvent{
	u8 ssid[32];
	u8 ssidlen;
	u8 bssid[6];
	u8 crypto_pairwise;
	
	u8 crypto_group;
	u8 keymgmt;
	u8 bgnMode;//11B bit0,11G bit 1; 11n bit2
	u8 connect_flag;

	u32 ipaddr;
	u32 ipmask;
	u32 gwaddr;
	u32 dnsaddr[2];
}__packed;

struct  HostDisConnectEvent{
	u8 bssid[6];
	u8 reason;
};

struct  wsm_sdio_getconfig_cnf{
	u32 msgflag;
	u8 macaddr[6];
	u8 bconnect;
	u8 TxBAMap;
	
	u8 RxBAMap;
	u8 reserved[3];
	// startup indicate
	u8 InputbufferNum;
	u8 WifiMode;
	u8 reserved1[2];
	u32 NumOfHwXmitedAddr;
	u32 firmwareVersion;
	u32 firmwareCap;
	
	struct HostConnectEvent con_event;
	struct bss_info bss;
}__packed;


#define WSM_TCP_FILTER_REQ_ID     0x0009
#define WSM_TCP_FILTER_RESP_ID    0x0409

#define WSM_TCP_FILTER_GET_ID       0x000C
#define WSM_TCP_FILTER_GET_RESP_ID  0x040C


#define HI_SDIO_TCP_FILTER_PORT_MAX_CNT  4
#define HI_SDIO_FILTER_F_ARP 	BIT(0)
#define HI_SDIO_FILTER_F_ICMP 	BIT(1)
#define HI_SDIO_FILTER_F_DNS 	BIT(2)

struct  wsm_tcp_filter_req{//HI_SDIO_TCP_FILTER_REQ
	u32 status;
	u16 Flags;
	u8 src_cnt;
	u8 des_cnt;
	u16 src_tcpport[HI_SDIO_TCP_FILTER_PORT_MAX_CNT];//big endian
	u16 des_tcpport[HI_SDIO_TCP_FILTER_PORT_MAX_CNT];
}__packed;

int wsm_set_tcp_filter(struct atbm_common *hw_priv, void *buffer,size_t buf_size);
int wsm_get_tcp_filter(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_PSMODE_REQ_ID     0x0008
#define WSM_PSMODE_RESP_ID    0x0408

#define HAL_NO_SLEEP 0
#define HAL_MODEM_SLEEP 1
#define HAL_LIGHT_SLEEP 2
#define HAL_DEEP_SLEEP  3

#define HAL_PS_LEVEL0	0//max throughput
#define HAL_PS_LEVEL1	1//max sleep

struct  wsm_powersave_mode_req{//HI_POWERSAVE_MODE_REQ
	u32 status;
	u32 Flags;
	u8  powersave_mode;/*0:nosleep 1:modem sleep 2:lightsleep:3 deep sleep*/
	u8  powerave_level;
	u16 fastsleep_time;//reserved
}__packed;
int wsm_set_psmode(struct atbm_common *hw_priv, void *buffer,size_t buf_size);


/* 3.17 */
struct wsm_event {
	/* WSM_STATUS_... */
	/* [out] */ u32 eventId;

	/* Indication parameters. */
	/* For error indication, this shall be a 32-bit WSM status. */
	/* For RCPI or RSSI indication, this should be an 8-bit */
	/* RCPI or RSSI value. */
	/* [out] */ u8 buffer[MAX_SDIO_EVENT_BUFFER_LEN];
};

struct atbm_wsm_event {
	struct list_head link;
	struct wsm_event evt;
	u8 if_id;
};

/* 3.18 - 3.22 */
/* Measurement. Skipped for now. Irrelevent. */

typedef void (*wsm_event_cb) (struct atbm_common *hw_priv,
			      struct wsm_event *arg);

/* 3.23 */
#define WSM_JOIN_REQ_ID 0x0003
#define WSM_JOIN_RESP_ID 0x0403
struct wsm_join {
	;
	
	/* WSM_JOIN_FLAGS_... */
	/* [in] */ u8 flags;


	/* Specifies the BSSID of the BSS or IBSS to be joined */
	/* or the IBSS to be started. */
	/* [in] */ u8 bssid[6];


	/* Length of the SSID */
	/* [in] */ u8 ssidLength;

	/* Specifies the SSID of the IBSS to join or start */
	/* [in] */ u8 ssid[32];

	/* [in] */ u8 keyMgmt;
	/* [in] */ u8 keyLength;
	/* [in] */ u8 keyId;
	/* [in] */ u8 reserved;
	/* [in] */ u8 key[64];

};

int wsm_join(struct atbm_common *hw_priv, struct wsm_join *arg, int if_id);

/* 3.25 */
#define WSM_SET_PM_REQ_ID 0x0010
#define WSM_SET_PM_RESP_ID 0x0410
struct wsm_set_pm {
	/* WSM_PSM_... */
	/* [in] */ u8 pmMode;

	/* in unit of 500us; 0 to use default */
	/* [in] */ u8 fastPsmIdlePeriod;

	/* in unit of 500us; 0 to use default */
	/* [in] */ u8 apPsmChangePeriod;

	/* in unit of 500us; 0 to disable auto-pspoll */
	/* [in] */ u8 minAutoPsPollPeriod;
};

int wsm_set_pm(struct atbm_common *hw_priv, const struct wsm_set_pm *arg,
	       int if_id);

/* 3.27 */
struct wsm_set_pm_complete {
	u8 psm;			/* WSM_PSM_... */
};

typedef void (*wsm_set_pm_complete_cb) (struct atbm_common *hw_priv,
					struct wsm_set_pm_complete *arg);

/* 3.28 */
#define WSM_SET_BSS_PARAMS_REQ_ID 0x0011
#define WSM_SET_BSS_PARAMS_RESP_ID 0x0411
struct wsm_set_bss_params {
	/* The number of lost consecutive beacons after which */
	/* the WLAN device should indicate the BSS-Lost event */
	/* to the WLAN host driver. */
	u8 beaconLostCount;

	/* The AID received during the association process. */
	u16 aid;

	/* The operational rate set mask */
	u32 operationalRateSet;
};

int wsm_set_bss_params(struct atbm_common *hw_priv,
		       const struct wsm_set_bss_params *arg, int if_id);

/* 3.30 */
#define WSM_ADD_KEY_REQ_ID         0x000C
#define WSM_ADD_KEY_RESP_ID        0x040C
struct wsm_add_key {
	u8 type;		/* WSM_KEY_TYPE_... */
	u8 entryIndex;		/* Key entry index: 0 -- WSM_KEY_MAX_INDEX */
	u16 reserved;
	union {
		struct {
			u8 peerAddress[6];	/* MAC address of the
						 * peer station */
			u8 reserved;
			u8 keyLength;		/* Key length in bytes */
			u8 keyData[16];		/* Key data */
		} __packed wepPairwiseKey;
		struct {
			u8 keyId;		/* Unique per key identifier
						 * (0..3) */
			u8 keyLength;		/* Key length in bytes */
			u16 reserved;
			u8 keyData[16];		/* Key data */
		} __packed wepGroupKey;
		struct {
			u8 peerAddress[6];	/* MAC address of the
						 * peer station */
			u8 reserved[2];
			u8 tkipKeyData[16];	/* TKIP key data */
			u8 rxMicKey[8];		/* Rx MIC key */
			u8 txMicKey[8];		/* Tx MIC key */
		} __packed tkipPairwiseKey;
		struct {
			u8 tkipKeyData[16];	/* TKIP key data */
			u8 rxMicKey[8];		/* Rx MIC key */
			u8 keyId;		/* Key ID */
			u8 reserved[3];
			u8 rxSeqCounter[8];	/* Receive Sequence Counter */
		} __packed tkipGroupKey;
		struct {
			u8 peerAddress[6];	/* MAC address of the
						 * peer station */
			u16 reserved;
			u8 aesKeyData[16];	/* AES key data */
		} __packed aesPairwiseKey;
		struct {
			u8 aesKeyData[16];	/* AES key data */
			u8 keyId;		/* Key ID */
			u8 reserved[3];
			u8 rxSeqCounter[8];	/* Receive Sequence Counter */
		} __packed aesGroupKey;
		/*11w */
		struct {
			u8 igtKeyData[16];
			u8 keyId;
			u8 reserved[3];
			u8 ipn[8]; /* actual IPN is only 6 bytes long*/
		}__packed igtkGroupKey;

		struct {
			u8 peerAddress[6];	/* MAC address of the
						 * peer station */
			u8 keyId;		/* Key ID */
			u8 reserved;
			u8 wapiKeyData[16];	/* WAPI key data */
			u8 micKeyData[16];	/* MIC key data */
		} __packed wapiPairwiseKey;
		struct {
			u8 wapiKeyData[16];	/* WAPI key data */
			u8 micKeyData[16];	/* MIC key data */
			u8 keyId;		/* Key ID */
			u8 reserved[3];
		} __packed wapiGroupKey;
	} __packed;
} __packed;

int wsm_add_key(struct atbm_common *hw_priv, const struct wsm_add_key *arg,
			int if_id);




/* 3.32 */
#define WSM_REMOVE_KEY_REQ_ID         0x000D
#define WSM_REMOVE_KEY_RESP_ID        0x040D
struct wsm_remove_key {
	/* Key entry index : 0-10 */
	u8 entryIndex;
};
#if 0
int wsm_remove_key(struct atbm_common *hw_priv,
		   const struct wsm_remove_key *arg, int if_id);
#else
int wsm_remove_key(struct atbm_common *hw_priv, const struct wsm_add_key *arg,
			int if_id);

#endif
/* 3.34 */
#define WSM_QUEUE_PARAMS_REQ_ID 0x0012
#define WSM_QUEUE_PARAMS_RESP_ID 0x0412
struct wsm_set_tx_queue_params {
	/* WSM_ACK_POLICY_... */
	u8 ackPolicy;

	/* Medium Time of TSPEC (in 32us units) allowed per */
	/* One Second Averaging Period for this queue. */
	u16 allowedMediumTime;

	/* dot11MaxTransmitMsduLifetime to be used for the */
	/* specified queue. */
	u32 maxTransmitLifetime;
};

struct wsm_tx_queue_params {
	/* NOTE: index is a linux queue id. */
	struct wsm_set_tx_queue_params params[4];
};

#define WSM_TX_QUEUE_SET(queue_params, queue, ack_policy, allowed_time,     \
			 max_life_time)					    \
do {									    \
	struct wsm_set_tx_queue_params *p = &(queue_params)->params[queue]; \
	p->ackPolicy = (ack_policy);				\
	p->allowedMediumTime = (allowed_time);				\
	p->maxTransmitLifetime = (max_life_time);			\
} while (0)

int wsm_set_tx_queue_params(struct atbm_common *hw_priv,
			    const struct wsm_set_tx_queue_params *arg,
			    u8 id, int if_id);

/* 3.36 */
#define WSM_EDCA_PARAMS_REQ_ID 0x0013
#define WSM_EDCA_PARAMS_RESP_ID 0x0413
struct wsm_edca_queue_params {
	/* CWmin (in slots) for the access class. */
	/* [in] */ u16 cwMin;

	/* CWmax (in slots) for the access class. */
	/* [in] */ u16 cwMax;

	/* AIFS (in slots) for the access class. */
	/* [in] */ u8 aifns;

	/* TX OP Limit (in microseconds) for the access class. */
	/* [in] */ u16 txOpLimit;

	/* dot11MaxReceiveLifetime to be used for the specified */
	/* the access class. Overrides the global */
	/* dot11MaxReceiveLifetime value */
	/* [in] */ u32 maxReceiveLifetime;

	/* UAPSD trigger support for the access class. */
	/* [in] */ bool uapsdEnable;
};

struct wsm_edca_params {
	/* NOTE: index is a linux queue id. */
	struct wsm_edca_queue_params params[4];
};

#define TXOP_UNIT 32
#define WSM_EDCA_SET(edca, queue, aifs, cw_min, cw_max, txop, life_time,\
		uapsd)	\
	do {							\
		struct wsm_edca_queue_params *p = &(edca)->params[queue]; \
		p->cwMin = (cw_min);				\
		p->cwMax = (cw_max);				\
		p->aifns = (aifs);				\
		p->txOpLimit = ((txop) * TXOP_UNIT);		\
		p->maxReceiveLifetime = (life_time);		\
		p->uapsdEnable = (uapsd);			\
	} while (0)

int wsm_set_edca_params(struct atbm_common *hw_priv,
			const struct wsm_edca_params *arg, int if_id);

int wsm_set_uapsd_param(struct atbm_common *hw_priv,
			const struct wsm_edca_params *arg);

/* 3.38 */
/* Set-System info. Skipped for now. Irrelevent. */

/* 3.40 */
#define WSM_SWITCH_CHANNEL_REQ_ID 0x0016
#define WSM_SWITCH_CHANNEL_RESP_ID 0x0416
struct wsm_switch_channel {
	/* 1 - means the STA shall not transmit any further */
	/* frames until the channel switch has completed */
	/* [in] */ u8 channelMode;

	/* Number of TBTTs until channel switch occurs. */
	/* 0 - indicates switch shall occur at any time */
	/* 1 - occurs immediately before the next TBTT */
	/* [in] */ u8 channelSwitchCount;

	/* The new channel number to switch to. */
	/* Note this is defined as per section 2.7. */
	/* [in] */ u16 newChannelNumber;
};

int wsm_switch_channel(struct atbm_common *hw_priv,
		       const struct wsm_switch_channel *arg, int if_id);

typedef void (*wsm_channel_switch_cb) (struct atbm_common *hw_priv);

#define WSM_START_REQ_ID 0x0017
#define WSM_START_RESP_ID 0x0417
struct wsm_start {
	/* WSM_START_MODE_... */
	/* [in] */ u8 mode;

	/* WSM_PHY_BAND_... */
	/* [in] */ u8 band;

	/* Channel number */
	/* [in] */ u16 channelNumber;

	/* Client Traffic window in units of TU */
	/* Valid only when mode == ..._P2P */
	/* [in] */ u32 CTWindow;

	/* Interval between two consecutive */
	/* beacon transmissions in TU. */
	/* [in] */ u32 beaconInterval;

	/* DTIM period in terms of beacon intervals */
	/* [in] */ u8 DTIMPeriod;

	/* WSM_JOIN_PREAMBLE_... */
	/* [in] */ u8 preambleType;

	/* The delay time (in microseconds) period */
	/* before sending a probe-request. */
	/* [in] */ u8 probeDelay;

	/* Length of the SSID */
	/* [in] */ u8 ssidLength;

	/* SSID of the BSS or P2P_GO to be started now. */
	/* [in] */ u8 ssid[32];

	/* The basic supported rates for the MiniAP. */
	/* [in] */ u32 basicRateSet;

			 u32	channel_type;

};

int wsm_start(struct atbm_common *hw_priv, const struct wsm_start *arg,
		int if_id);

#define WSM_BEACON_TRANSMIT_REQ_ID 0x0018
#define WSM_BEACON_TRANSMIT_RESP_ID 0x0418
#if 0
struct wsm_beacon_transmit {
	/* 1: enable; 0: disable */
	/* [in] */ u8 enableBeaconing;
};

int wsm_beacon_transmit(struct atbm_common *hw_priv,
			const struct wsm_beacon_transmit *arg,
			int if_id);
#endif
//[ Notice ] this msgid used by efuse change data
//int wsm_start_find(struct atbm_common *hw_priv, int if_id);

int wsm_stop_find(struct atbm_common *hw_priv, int if_id);

typedef void (*wsm_find_complete_cb) (struct atbm_common *hw_priv,
				      u32 status);

struct wsm_suspend_resume {
	/* See 3.52 */
	/* Link ID */
	/* [out] */ int link_id;
	/* Stop sending further Tx requests down to device for this link */
	/* [out] */ bool stop;
	/* Transmit multicast Frames */
	/* [out] */ bool multicast;
	/* The AC on which Tx to be suspended /resumed. */
	/* This is applicable only for U-APSD */
	/* WSM_QUEUE_... */
	/* [out] */ int queue;
	/* [out] */ int if_id;
};


/* 3.54 Update-IE request. */
#define WSM_UPDATE_IE_REQ_ID     0x001B
#define WSM_UPDATE_IE_RESP_ID    0x041B
struct wsm_update_ie {
	/* WSM_UPDATE_IE_... */
	/* [in] */ u16 what;
	/* [in] */ u16 count;
	/* [in] */ u8 *ies;
	/* [in] */ size_t length;
};

int wsm_update_ie(struct atbm_common *hw_priv,
		  const struct wsm_update_ie *arg, int if_id);

/* 3.56 */
struct wsm_map_link {
	/* MAC address of the remote device */
	/* [in] */ u8 mac_addr[6];
	/* [in] */ u8 unmap;
	/* [in] */ u8 link_id;
};
#define WSM_MAP_LINK_REQ_ID       0x001C
#define WSM_MAP_LINK_RESP_ID       0x041C
int wsm_map_link(struct atbm_common *hw_priv, const struct wsm_map_link *arg,
		int if_id);



struct efuse_headr{
	u8 specific;
	u8 version;
	u8 dcxo_trim;
	u8 delta_gain1;
	u8 delta_gain2;
	u8 delta_gain3;
	u8 Tj_room;
	u8 topref_ctrl_bias_res_trim;
	u8 PowerSupplySel;
	u8 mac[6];
};
#define WSM_CONFIG_REQ_ID 0x0002
#define WSM_CONFIG_RESP_ID 0x0402

int wsm_get_config(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_wifi_set_req{
	u32 status;
	u8 is_ap;
	u8 channel;
	u8 countryId;
	u8 reserved[1];
};

#define WSM_WIFIMODE_REQ_ID     0x000D
#define WSM_WIFIMODE_RESP_ID    0x040D

int wsm_set_wifimode(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_AP_CFG_REQ_ID     0x000E
#define WSM_AP_CFG_RESP_ID    0x040E

struct wsm_ap_cfg_req{
	u32 status;
	struct wsm_join join_parameter;
};

int wsm_set_ap_cfg(struct atbm_common *hw_priv, void *buffer,size_t buf_size);


#define WSM_CHANNEL_REQ_ID     0x000F
#define WSM_CHANNEL_RESP_ID    0x040F

int wsm_set_wifichannel(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_SET_COUNTRY_REQ_ID     0x0010
#define WSM_SET_COUNTRY_RESP_ID    0x0410

#define COUNTRY_MAX  9

int wsm_set_countryId(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_GET_COUNTRY_REQ_ID     0x0011
#define WSM_GET_COUNTRY_RESP_ID    0x0411

int wsm_get_countryId(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define MAX_NUM_LINK_AP  4

struct atbm_stainfo{
	u8 macAddr[6];
};

struct wsm_sta_list_req{
	u32 status;
	u8 sta_cnt;
	u8 reserved[3];
	struct atbm_stainfo info[MAX_NUM_LINK_AP];
};

#define WSM_GET_STALIST_REQ_ID     0x0012
#define WSM_GET_STALIST_RESP_ID    0x0412

int wsm_get_stalist(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_SMART_CFG_START_REQ_ID   0x0013
#define WSM_SMART_CFG_START_RESP_ID  0x0413

int wsm_smart_cfg_start(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_SMART_CFG_STOP_REQ_ID    0x0014
#define WSM_SMART_CFG_STOP_RESP_ID   0x0414

int wsm_smart_cfg_stop(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_AP_TOUCH_START_REQ_ID    0x0015
#define WSM_AP_TOUCH_START_RESP_ID   0x0415

struct wsm_ap_touch_req{
	u32 status;
	u8 is_no_notify;
	u8 reserved[3];
};

int wsm_ap_touch_start(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_AP_TOUCH_STOP_REQ_ID     0x0016
#define WSM_AP_TOUCH_STOP_RESP_ID    0x0416

int wsm_ap_touch_stop(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_etf_req{
	u32 status;
	u32 rate;
	u32 len;
	u8 channel;
	u8 is40M;
	u8 greenfield;
	u8 reserved[1];
};

#define WSM_ETF_START_TX_REQ_ID     0x0017
#define WSM_ETF_START_TX_RESP_ID    0x0417

int wsm_etf_start_tx(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_ETF_SINGLE_TONE_REQ_ID  0x0018
#define WSM_ETF_SINGLE_TONE_RESP_ID 0x0418

int wsm_etf_single_tone(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_ETF_STOP_TX_REQ_ID      0x0019
#define WSM_ETF_STOP_TX_RESP_ID     0x0419

int wsm_etf_stop_tx(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_ETF_START_RX_REQ_ID     0x001A
#define WSM_ETF_START_RX_RESP_ID    0x041A

int wsm_etf_start_rx(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_ETF_STOP_RX_REQ_ID      0x001B
#define WSM_ETF_STOP_RX_RESP_ID     0x041B

int wsm_etf_stop_rx(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_ETF_RESET_RX_REQ_ID     0x001C
#define WSM_ETF_RESET_RX_RESP_ID    0x041C

int wsm_etf_reset_rx(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_adaptive_req{
	u32 status;
	u32 adaptive_flag;
};

#define WSM_ADAPTIVE_REQ_ID         0x001D
#define WSM_ADAPTIVE_RESP_ID        0x041D

int wsm_set_adaptive(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_version_req{
	u32 status;
	u8 hw_ver[64];
	u8 sdk_ver[64];
};

#define WSM_GET_VER_REQ_ID          0x001E
#define WSM_GET_VER_RESP_ID         0x041E

int wsm_get_ver(struct atbm_common *hw_priv, void *buffer,size_t buf_size);


#define WSM_GET_SDK_VER_REQ_ID      0x001F
#define WSM_GET_SDK_VER_RESP_ID     0x041F

int wsm_get_sdk_ver(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_update_req{
	u32 status;
	u32 len;
	u8 data[1024];
	u8 start;
	u8 end;
	u8 restart;
	u8 reserved[1];
};

#define WSM_UPDATE_REQ_ID      0x0020
#define WSM_UPDATE_RESP_ID     0x0420

int wsm_update_fw(struct atbm_common *hw_priv, void *buffer,size_t buf_size);


struct wsm_ap_configure{
	u8 ssid[32];
	u8 ssid_len;
	u8 bssid[6];
	u8 password_len;
	u8 password[64];
	u8 key_mgmt;
	u8 key_id;
	u16 auth_alg;
};

struct wsm_ap_cfg_get_req{
	u32 status;
	struct wsm_ap_configure ap_cfg;
};

#define WSM_GET_AP_CFG_REQ_ID      0x0021
#define WSM_GET_AP_CFG_RESP_ID     0x0421

int wsm_get_ap_cfg(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_listen_itvl_req{
	u32 status;
	u8 interval;
	u8 reserved[3];
};

#define WSM_SET_LISTEN_ITVL_REQ_ID      0x0022
#define WSM_SET_LISTEN_ITVL_RESP_ID     0x0422

int wsm_set_listen_itvl(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_at_cmd_req{
	u32 status;
	u8 cmd[256];
};

#define WSM_AT_CMD_REQ_ID      0x0023
#define WSM_AT_CMD_RESP_ID     0x0423

int wsm_send_at_cmd(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_dbg_print_enable_req{
	u32 status;
	u8 enable;
	u8 reserved[3];
};

#define WSM_SET_DBG_PRINT_REQ_ID      0x0024
#define WSM_SET_DBG_PRINT_RESP_ID     0x0424

int wsm_set_dbg_print(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_ETF_START_RX_NO_DROP_REQ_ID     0x0025
#define WSM_ETF_START_RX_NO_DROP_RESP_ID    0x0425

int wsm_etf_start_rx_no_drop(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_FW_SLEEP_REQ_ID     0x0026
#define WSM_FW_SLEEP_RESP_ID    0x0426

int wsm_fw_sleep(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_get_rate_req{
	u32 status;
	u8 rate;
	u8 reserved[3];
};

#define WSM_GET_RATE_REQ_ID     0x0027
#define WSM_GET_RATE_RESP_ID    0x0427

int wsm_get_tx_rate(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_ipc_data_req{
	u32 status;
	u8 server[16];
	u16 port;
	u16 len;
	u8 data[1000];
};

#define WSM_IPC_DATA_REQ_ID      0x0028
#define WSM_IPC_DATA_RESP_ID     0x0428

int wsm_send_ipc_data(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_scan_state_req{
	u32 status;
	u8 scan_state;
	u8 reserved[3];
};

#define WSM_GET_SCAN_STATE_REQ_ID     0x0029
#define WSM_GET_SCAN_STATE_RESP_ID    0x0429

int wsm_get_scan_state(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_rssi_req{
	u32 status;
	int rssi;
};

#define WSM_GET_RSSI_REQ_ID     0x002A
#define WSM_GET_RSSI_RESP_ID    0x042A

int wsm_get_rssi(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct time_info{
	int tm_sec;
	int tm_min;
	int tm_hour;
	int tm_mday;
	int tm_mon;
	int tm_year;
	int tm_wday;
	int tm_yday;
	int tm_isdst;
};

struct wsm_time_req{
	u32 status;
	struct time_info time;
};

#define WSM_GET_TIME_REQ_ID     0x002B
#define WSM_GET_TIME_RESP_ID    0x042B

int wsm_get_time(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_CLEAR_WIFI_CFG_REQ_ID     0x002C
#define WSM_CLEAR_WIFI_CFG_RESP_ID    0x042C

int wsm_clear_wifi_config(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_etf_rx_info_req{
	u32 status;
	u32 rx_success_cnt;
	u32 fcs_err_cnt;
	s8  rssi;
	s8  reserved[3];
};

#define WSM_GET_ETF_RX_INFO_REQ_ID     0x002D
#define WSM_GET_ETF_RX_INFO_RESP_ID    0x042D

int wsm_get_etf_rx_info(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_netpattern_info{
	u32 status;
	u32 netpattern_index;
	u8  netpattern_data[64];
    u32 netpattern_len;
    u32 src_ipaddr;
	u16 src_port;
    u8  protocol;
	u8  reserved[1];
};

#define WSM_ADD_NETPATTERN_INFO_REQ_ID     0x002E
#define WSM_ADD_NETPATTERN_INFO_RESP_ID    0x042E

int wsm_add_netpattern_info(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_DEL_NETPATTERN_INFO_REQ_ID     0x002F
#define WSM_DEL_NETPATTERN_INFO_RESP_ID    0x042F

int wsm_del_netpattern_info(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_conn_param_info{
	u32	status;
	u32	sess_id;
	u8	tcp_payload[64];
	u32	dst_ip;
	u16	dst_port;
	u8	protocol;
	u8	reserved[1];
	u32	interval_time;
};

#define WSM_ADD_CONN_PARAM_INFO_REQ_ID     0x0030
#define WSM_ADD_CONN_PARAM_INFO_RESP_ID    0x0430

int wsm_add_conn_param_info(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_DEL_CONN_PARAM_INFO_REQ_ID     0x0031
#define WSM_DEL_CONN_PARAM_INFO_RESP_ID    0x0431

int wsm_del_conn_param_info(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_conn_switch_info{
	u32	status;
	u32	sess_id;
	u32	start_enable;
};

#define WSM_CONN_SWITCH_REQ_ID     0x0032
#define WSM_CONN_SWITCH_RESP_ID    0x0432

int wsm_conn_switch(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_conn_lose_info{
	u32 status;
	u32 lose_map;
};

#define WSM_CONN_LOSE_REQ_ID     0x0033
#define WSM_CONN_LOSE_RESP_ID    0x0433

int wsm_conn_lose(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_wakeup_ssid_info{
	u32 status;
	u8  ssid[32];
	u8  ssid_len;
	u8  reserved[3];
};

#define WSM_SET_WK_SSID_REQ_ID     0x0034
#define WSM_SET_WK_SSID_RESP_ID    0x0434

int wsm_set_wakeup_ssid(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_CLEAR_WK_SSID_REQ_ID     0x0035
#define WSM_CLEAR_WK_SSID_RESP_ID    0x0435

int wsm_clear_wakeup_ssid(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_auto_reconnect_req{
	u32 status;
	u8  auto_enable;
	u8  reserved[3];
};

#define WSM_AUTO_RECONNECT_REQ_ID      0x0036
#define WSM_AUTO_RECONNECT_RESP_ID     0x0436

int wsm_auto_reconnect(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_wakeup_event_req{
	u32 status;
	u32 event;
};

#define WSM_WAKEUP_EVENT_REQ_ID      0x0037
#define WSM_WAKEUP_EVENT_RESP_ID     0x0437

int wsm_set_wakeup_event(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_customer_cmd_req{
	u32 status;
	u32 cmd_id;
	u8  cmd_buff[128];
};

#define WSM_CUSTOMER_CMD_REQ_ID      0x0038
#define WSM_CUSTOMER_CMD_RESP_ID     0x0438

int wsm_send_customer_cmd(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_customer_cert_save_req{
	u32 status;
	u32 cert_type;
	u8 data[1024];
	u16 length;
	u8 first;
	u8 remain;
};

#define WSM_CUSTOMER_CERT_SAVE_REQ_ID      0x0039
#define WSM_CUSTOMER_CERT_SAVE_RESP_ID     0x0439

int wsm_customer_cert_save(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_check_alive_req{
	u32 status;
	u32 alive_notify;//host to 6441--1212, 6441 to host--2121
	u32 period; //unit s
	u32 tmo_cnt;
};

#define WSM_CHECK_ALIVE_REQ_ID      0x003A
#define WSM_CHECK_ALIVE_RESP_ID     0x043A

int wsm_check_alive(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

struct wsm_direct_trans_buffer_req{
	u32 status;
	u8 trans[1600];
};

#define WSM_DIRECT_TRANS_BUFFER_REQ_ID      0x003B
#define WSM_DIRECT_TRANS_BUFFER_RESP_ID     0x043B

int wsm_direct_trans_buffer(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_FORCE_REBOOT_REQ_ID     0x003C
#define WSM_FORCE_REBOOT_RESP_ID    0x043C

int wsm_force_reboot(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_NETWORK_OK_REQ_ID     0x003D
#define WSM_NETWORK_OK_RESP_ID    0x043D

int wsm_host_network_ok_notify(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_HOST_REBOOT_NOTIFY_REQ_ID     0x003E
#define WSM_HOST_REBOOT_NOTIFY_RESP_ID    0x043E

int wsm_host_reboot_notify(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_EXTEND_MSG_REQ_ID     		0x003F
#define WSM_EXTEND_MSG_RESP_ID    		0x043F
struct  wsm_extend_msg_req{
	int status;
	u8 externId;
	u8 reserved[3];
};

#define WSM_EXTEND_FAST_CFG_RECV_ID		0x00
struct  wsm_fast_cfg_recv_req{	//HI_POWERSAVE_MODE_REQ
	u8 enable;
	u8 reserved;
	u16 time;
}__packed;
int wsm_ext_fast_cfg_recv(struct atbm_common *hw_priv, void *buffer,size_t buf_size);

#define WSM_EXTEND_FAST_CFG_SEND_ID     0x01
struct  wsm_fast_cfg_send_req{	//HI_POWERSAVE_MODE_REQ
	u8 enable;
	u8 reserved;
	u16 time;
	u8 ssid_len;
	u8 password_len;
	u8 ssid[32];
	u8 password[64];
}__packed;
int wsm_ext_fast_cfg_send(struct atbm_common *hw_priv, void *buffer,size_t buf_size);


enum{
	WAKEUP_IO,			// hardware io
	WAKEUP_NETWORK,		//  keepalive wakeup netpattern
	WAKEUP_CONNECT,		// ap reconnect fail timeout
	WAKEUP_KEEPALIVE,	// keepalive resend timeout
	WAKEUP_TCP_NETPATTERN,// tcp netpattern match
	WAKEUP_UDP_NETPATTERN,// udp netpattern match
	WAKEUP_WK_SSID,		// wakeup ssid match
	WAKEUP_MAGIC_PKT,	// wowo magic packet match
};

/* ******************************************************************** */
/* WSM TX port control							*/

void wsm_lock_tx(struct atbm_common *hw_priv);
void wsm_lock_tx_async(struct atbm_common *hw_priv);
bool wsm_flush_tx(struct atbm_common *hw_priv);
void wsm_unlock_tx(struct atbm_common *hw_priv);

/* ******************************************************************** */
/* WSM / BH API								*/

int wsm_handle_exception(struct atbm_common *hw_priv, u8 * data, u32 len);
int wsm_handle_rx(struct atbm_common *hw_priv, int id, struct wsm_hdr *wsm,
		  struct sk_buff **skb_p);

/* ******************************************************************** */
/* wsm_buf API								*/

struct wsm_buf {
	u8 *begin;
	u8 *data;
	u8 *end;
};

void wsm_buf_init(struct wsm_buf *buf);
void wsm_buf_deinit(struct wsm_buf *buf);

/* ******************************************************************** */
/* wsm_cmd API								*/

struct wsm_cmd {
	spinlock_t lock;
	int done;
	int last_send_cmd;
//	int last_send_end_cmd;
	u8 *ptr;
	u32 len;
	void *arg;
	int ret;
	u16 cmd;
};

/* ******************************************************************** */
/* WSM TX buffer access							*/

int wsm_get_tx(struct atbm_common *hw_priv, u8 **data,
	       u32 *tx_len, int *burst, int *vif_selected,struct sk_buff **skb);

int wsm_txed(struct atbm_common *hw_priv, u8 *data);

/* ******************************************************************** */
/* Queue mapping: WSM <---> linux					*/
/* Linux: VO VI BE BK							*/
/* WSM:   BE BK VI VO							*/

static inline u8 wsm_queue_id_to_linux(u8 queueId)
{
	static const u8 queue_mapping[] = {
		2, 3, 1, 0
	};
	return queue_mapping[queueId];
}

static inline u8 wsm_queue_id_to_wsm(u8 queueId)
{
	static const u8 queue_mapping[] = {
		3, 2, 0, 1
	};
	return queue_mapping[queueId];
}
int wsm_read_shmem(struct atbm_common *hw_priv, u32 address, void *buffer, size_t buf_size);
int wsm_write_shmem(struct atbm_common *hw_priv, u32 address,size_t size, void *buffer);
#ifdef OPER_CLOCK_USE_SEM
void atbm_pm_timer(unsigned long arg);
#endif

#endif /* ATBM_APOLLO_HWIO_H_INCLUDED */
