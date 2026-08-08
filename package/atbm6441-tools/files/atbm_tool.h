#ifndef ATBM_TOOL_H
#define ATBM_TOOL_H

#define __packed __attribute__((packed))

#define BIT(nr)			(1UL << (nr))

#define FILTER_F_ARP 	BIT(0)
#define FILTER_F_ICMP 	BIT(1)
#define FILTER_F_DNS 	BIT(2)

#define MAX_ARGS                 10

#define CMD_LINE_LEN             1600

#define TCP_FILTER_PORT_MAX_CNT  4

#define SCAN_RESULT_MAX_CNT      30

#define MAX_NUM_LINK_AP          4

#define SER_SOCKET_PATH          "/tmp/atbm_server_socket"

#ifdef CONFIG_ATBM_SDIO_ATCMD
#define MAX_SDIO_EVENT_BUFFER_LEN 1500
#else
#define MAX_SDIO_EVENT_BUFFER_LEN 504
#endif

typedef unsigned int u32;
typedef unsigned short u16;
typedef unsigned char u8;
typedef signed char s8;

struct connect_info {
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

struct status_info{
	u32 msgflag;
	u8 macaddr[6];
	u8 bconnect;
	u8 TxBAMap;

	u8 RxBAMap;
	u8 reserved[3];
	// startup indicate
	u8 InputbufferNum;
	u8 wifimode;
	u8 reserved1[2];
	u32 NumOfHwXmitedAddr;
	u32 firmwareVersion;
	u32 firmwareCap;
	
	struct HostConnectEvent con_event;
	struct bss_info bss;
}__packed;

struct  powersave_mode{
	u32 status;
	u32 Flags;
	u8  powersave_mode;/*0:nosleep 1:modem sleep 2:lightsleep:3 deep sleep*/
	u8  powerave_level;
	u16 fastsleep_time;//reserved
}__packed;

struct  fast_cfg_recv_info{
	u8 enable;
	u8 reserved;
	u16 time;
}__packed;

struct  fast_cfg_send_info{
	u8 enable;
	u8 reserved;
	u16 time;
	u8 ssid_len;
	u8 password_len;
	u8 ssid[32];
	u8 password[64];
}__packed;

struct  tcp_filter_info{
	u32 status;
	u16 Flags;
	u8 src_cnt;
	u8 des_cnt;
	u16 src_tcpport[TCP_FILTER_PORT_MAX_CNT];//big endian
	u16 des_tcpport[TCP_FILTER_PORT_MAX_CNT];
}__packed;

struct scan_result_info{
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

struct scan_result{
	u32 status;
	u16 scan_cnt;
	u8 remain;
	u8 offset;
	struct scan_result_info scan_info[SCAN_RESULT_MAX_CNT];
};

struct ap_cfg{
	u32 status;
	struct connect_info ap_parameter;
};

struct stainfo{
	u8 macAddr[6];
};

struct stalist_info{
	u32 status;
	u8 sta_cnt;
	u8 reserved[3];
	struct stainfo info[MAX_NUM_LINK_AP];
};

struct ap_touch_info{
	u32 status;
	u8 is_no_notify;
	u8 reserved[3];
};

struct etf_cfg{
	u32 status;
	u32 rate;
	u32 len;
	u8 channel;
	u8 is40M;
	u8 greenfield;
	u8 reserved[1];
};

struct adaptive_info{
	u32 status;
	u32 adaptive_flag;
};

struct version_info{
	u32 status;
	u8 hw_ver[64];
	u8 sdk_ver[64];
};

struct update_info{
	u32 status;
	u32 len;
	u8 data[1024];
	u8 start;
	u8 end;
	u8 restart;
	u8 reserved[1];
};

struct rate_info{
	u32 status;
	u8 rate;
	u8 reserved[3];
};

struct at_cmd_info{
	u32 status;
	u8 cmd[256];
};

struct ipc_data_info{
	u32 status;
	u8 server[16];
	u16 port;
	u16 len;
	u8 data[1000];
};

struct rssi_info{
	u32 status;
	int rssi;
};

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

struct time_info_req{
	u32 status;
	struct time_info time;
};

struct etf_rx_info_req{
	u32 status;
	u32 rx_success_cnt;
	u32 fcs_err_cnt;
	s8  rssi;
	s8  reserved[3];
};

struct netpattern_req{
	u32 status;
	u32 netpattern_index;
	u8  netpattern_data[64];
	u32 netpattern_len;
	u32 src_ipaddr;
	u16 src_port;
	u8  protocol;
	u8  reserved[1];
};

struct conn_param_req{
	u32	status;
	u32	sess_id;
	u8	tcp_payload[64];
	u32	dst_ip;
	u16	dst_port;
	u8	protocol;
	u8	reserved[1];
	u32	interval_time;
};

struct conn_switch_req{
	u32	status;
	u32	sess_id;
	u32	start_enable;
};

struct conn_lose_req{
	u32 status;
	u32 lose_map;
};

struct wakeup_ssid_req{
	u32 status;
	u8  ssid[32];
	u8  ssid_len;
	u8  reserved[3];
};

struct auto_reconnect_req{
	u32 status;
	u8  auto_enable;
	u8  reserved[3];
};

struct wakeup_event_req{
	u32 status;
	u32 event;
};

struct customer_cmd_req{
	u32 status;
	u32 cmd_id;
	u8  cmd_buff[128];
};

struct customer_cert_save_req{
	u32 status;
	u32 cert_type;
	u8 data[1024];
	u16 length;
	u8 first;
	u8 remain;
};

struct check_alive_req{
	u32 status;
	u32 alive_notify;//host to 6441--1212, 6441 to host--2121
	u32 period; //unit s
	u32 tmo_cnt;	
};

struct direct_trans_buffer_req{
	u32 status;
	u8 trans[1600];
};

struct status_async{
	u8 is_connected;
	u8 type; /*0: connect msg; 1: rmmod; 2: scan complet, 3:wakeup host reason, 4:disconnect reason, 5:connect fail reason, 6:customer event*/
	u8 driver_mode; /* TYPE1 0: rmmod, 1: insmod; TYPE3\4\5 reason */
	u8 list_empty;
	struct HostConnectEvent event;
	u8 event_buffer[MAX_SDIO_EVENT_BUFFER_LEN];
};

struct COMMAND_STR {
	char *cmd;
	int (*cmd_send)(int fp, int argc, char *argv[]);
	char *descript;
};

struct transform{
	char *type;
	int type_value;
};

enum{
	PS_TYPE_NO_SLEEP,
	PS_TYPE_MODEM_SLEEP,
	PS_TYPE_LIGHT_SLEEP,
	PS_TYPE_DEEP_SLEEP,
	PS_TYPE_MAX
};

enum{
	KEY_MGMT_NONE,
	KEY_MGMT_WEP,
	KEY_MGMT_WEP_SHARED,
	KEY_MGMT_WPA,
	KEY_MGMT_WPA2,
	KEY_MGMT_MAX
};

enum{
	COUNTRY_CHINESE,
	COUNTRY_USA,
	COUNTRY_EUROPE,
	COUNTRY_JAPAN,
	COUNTRY_CANADA,
	COUNTRY_AUSTRALIA,
	COUNTRY_ISRAEL,
	COUNTRY_MEXICO,
	COUNTRY_FRANCE,
	COUNTRY_MAX
};

enum{
	RATE_INDEX_B_1M,
	RATE_INDEX_B_2M,
	RATE_INDEX_B_5_5M,
	RATE_INDEX_B_11M,
	RATE_INDEX_PBCC_22M,
	RATE_INDEX_PBCC_33M,
	RATE_INDEX_A_6M,
	RATE_INDEX_A_9M,
	RATE_INDEX_A_12M,
	RATE_INDEX_A_18M,
	RATE_INDEX_A_24M,
	RATE_INDEX_A_36M,
	RATE_INDEX_A_48M,
	RATE_INDEX_A_54M,
	RATE_INDEX_N_6_5M,
	RATE_INDEX_N_13M,
	RATE_INDEX_N_19_5M,
	RATE_INDEX_N_26M,
	RATE_INDEX_N_39M,
	RATE_INDEX_N_52M,
	RATE_INDEX_N_58_5M,
	RATE_INDEX_N_65M,
	RATE_INDEX_N_MCS32_6M,
	RATE_INDEX_MAX
};

typedef enum{
	CHECK_SSID,
	CHECK_KEY,
	CHECK_KEY_ID,
	CHECK_KEY_MGMT,
	CHECK_MAX
}check_type;

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

enum{
	DISCONN_BSS_LOST,
	DISCONN_HOST_DONE,
	DISCONN_AP_DEAUTH
};

enum{
	CONN_NOT_FOUND_SSID,
	CONN_JOIN_FAIL,
	CONN_NOT_GET_IP
};

#endif /* ATBM_TOOL_H */

