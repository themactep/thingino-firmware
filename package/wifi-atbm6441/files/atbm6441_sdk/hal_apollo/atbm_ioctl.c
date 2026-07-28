//#include <stdio.h>
#ifdef LINUX_OS
#include <linux/module.h>
#include <linux/init.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/fs.h>
#include <linux/kthread.h>
#include <asm/ioctl.h>
#endif

#include "apollo.h"
#include "wsm.h"
#include "debug.h"
#include "atbm_ioctl.h"
#include "sta_info.h"
#include "hwio.h"
#include "sbus.h"
#include "dcxo_dpll.h"

#ifdef LINUX_OS
#define MAX_STATUS_LSIT_CNT  (10)

struct atbm_info {
	dev_t devid;
	struct cdev *my_cdev;
	struct class *my_class;
	struct device *my_device;
	struct atbm_common *hw_priv;
};

struct status_async{
	u8 is_connected;
	u8 type; /* 0: connect msg, 1: driver msg, 2:scan complete, 3:wakeup host reason, 4:disconnect reason, 5:connect fail reason, 6:customer event*/
	u8 driver_mode; /* TYPE1 0: rmmod, 1: insmod; TYPE3\4\5 reason */
	u8 list_empty;
	struct HostConnectEvent event;
	u8 event_buffer[MAX_SDIO_EVENT_BUFFER_LEN];
};

struct atbm_status_event {
	struct list_head link;
	struct status_async status;
};

struct atbm_info atbm_info;

static struct fasync_struct *connect_async;
static spinlock_t s_status_queue_lock;
static struct list_head s_status_head;
static int s_cur_status_list_cnt = 0;
#endif

struct timer_info
{
	struct atbm_timer_list timer;
	struct wsm_scan_state_req scan_state;
	struct workqueue_struct *workqueue;
	struct work_struct work;
	int scan_ok;
};

struct check_alive_info
{
	struct atbm_timer_list timer;
	struct workqueue_struct *workqueue;
	struct work_struct work;
	int period; //ms
	int tmo_cnt;
	int cur_cnt;
	int is_start;
	int in_check;
};

static struct timer_info timer_info;
static struct check_alive_info check_alive_info;

static struct wsm_scan_result_req result;
static struct wsm_update_req update_req;

extern struct atbm_common *g_hw_priv;
extern int hw_net_cfg_ok;

int is_pre_rmmod = 0;

extern void atbm_clear_wakeup_reg( struct atbm_common  *dev);
extern void wsm_cmd_lock(struct atbm_common *hw_priv);
extern void wsm_cmd_unlock(struct atbm_common *hw_priv);

#ifdef LINUX_OS
static int atbm_ioctl_notify_add(u8 type, u8 is_connected, u8 driver_mode, struct HostConnectEvent *conn_event, u8 *event_buffer)
{
	int first;
	struct atbm_status_event *event = NULL;

	if (s_cur_status_list_cnt >= MAX_STATUS_LSIT_CNT)
	{
		atbm_printk_err("%s: status event list is full.\n", __func__);
		return -1;
	}
	if ((type == 6) && (event_buffer == NULL))
	{
		atbm_printk_err("%s: event_buffer is full.\n", __func__);
		return -1;
	}
	
#ifdef CONFIG_ATBM_SDIO_ATCMD
	if ((type == 7) && (event_buffer == NULL))
	{
		atbm_printk_err("%s: event_buffer is full.\n", __func__);
		return -1;
	}
#endif

	event = atbm_kzalloc(sizeof(struct atbm_status_event), GFP_KERNEL);
	if(event == NULL)
	{
		atbm_printk_err("%s: event atbm_kzalloc is null.\n", __func__);
		WARN_ON(1);
		return -1;
	}

	if (conn_event != NULL)
	{
		memcpy(&(event->status.event), conn_event, sizeof(struct HostConnectEvent));
	}
	if (event_buffer != NULL)
	{
		memcpy(&(event->status.event_buffer), event_buffer, MAX_SDIO_EVENT_BUFFER_LEN);
	}
	event->status.type = type;
	event->status.driver_mode = driver_mode;
	event->status.is_connected = is_connected;

	spin_lock_bh(&s_status_queue_lock);
	first = list_empty(&s_status_head);
	list_add_tail(&event->link, &s_status_head);
	s_cur_status_list_cnt++;
	spin_unlock_bh(&s_status_queue_lock);
	if (1)
	{
		return 1;//need async notify usr layer
	}
	else
	{
		return 0;//not need async notify usr layer
	}
}
#endif

//notify connect status
void atbm_ioctl_connect_async(struct HostConnectEvent *event, char is_connected)
{
	#ifdef LINUX_OS
	int ret;

	if (is_connected)
	{
		if (NULL == event)
		{
			atbm_printk_err("%s: event data is null.\n", __func__);
			return;
		}
		ret = atbm_ioctl_notify_add(0, 1, 0, event, NULL);
	}
	else
	{
		ret = atbm_ioctl_notify_add(0, 0, 0, NULL, NULL);
	}

	if (ret > 0)
	{
		kill_fasync (&connect_async, SIGIO, POLL_IN);
	}
	#endif
}

//notify driver need to insmod&rmmod
void atbm_ioctl_driver_async(int insmod)
{
	#ifdef LINUX_OS
	if (atbm_ioctl_notify_add(1, 0, insmod, NULL, NULL) > 0)
	{
		kill_fasync (&connect_async, SIGIO, POLL_IN);
	}
	#endif
}

//notify wakeup host reason
void atbm_ioctl_wakeup_async(int reason)
{
	#ifdef LINUX_OS
	if (atbm_ioctl_notify_add(3, 0, reason, NULL, NULL) > 0)
	{
		kill_fasync (&connect_async, SIGIO, POLL_IN);
	}
	#endif
}

//notify network disconnect reason
void atbm_ioctl_disconn_async(int reason)
{
	#ifdef LINUX_OS
	if (atbm_ioctl_notify_add(4, 0, reason, NULL, NULL) > 0)
	{
		kill_fasync (&connect_async, SIGIO, POLL_IN);
	}
	#endif
}

//notify network connect error reason
void atbm_ioctl_conn_err_async(int reason)
{
	#ifdef LINUX_OS
	if (atbm_ioctl_notify_add(5, 0, reason, NULL, NULL) > 0)
	{
		kill_fasync (&connect_async, SIGIO, POLL_IN);
	}
	#endif
}

//upload customer private event info
void atbm_ioctl_customer_private_event_async(u8 *event_buffer)
{
	#ifdef LINUX_OS
	if (atbm_ioctl_notify_add(6, 0, 0, NULL, event_buffer) > 0)
	{
		kill_fasync (&connect_async, SIGIO, POLL_IN);
	}
	#endif
}

#ifdef CONFIG_ATBM_SDIO_ATCMD
void atbm_ioctl_atcmd_event_async(u8 *event_buffer)
{
	#ifdef LINUX_OS
	if (atbm_ioctl_notify_add(7, 0, 0, NULL, event_buffer) > 0)
	{
		kill_fasync (&connect_async, SIGIO, POLL_IN);
	}
	#endif
}
#endif

int atbm_wsm_ps(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;
	struct wsm_powersave_mode_req  ps_mode;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&ps_mode, 0, sizeof(ps_mode));
	if (0 != copy_from_user(&ps_mode, (struct wsm_powersave_mode_req *)data, sizeof(struct wsm_powersave_mode_req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_set_psmode(hw_priv,&ps_mode,sizeof(ps_mode));
	if (ret)
	{
		atbm_printk_err("%s: wsm_set_psmode err.\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_connect(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;
	int if_id = 0;
	int i = 0;
	struct wsm_join join;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	for (i=0; i<ATBM_WIFI_MAX_VIFS; i++)
	{
		if (hw_priv->vif_list[i])
		{
			if_id = i;
			break;
		}
	}

	if (ATBM_WIFI_MAX_VIFS == i)
	{
		atbm_printk_err("%s: hw_priv->vif_list is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&join, 0, sizeof(join));
	if (0 != copy_from_user(&join, (struct wsm_join *)data, sizeof(struct wsm_join)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	if (if_id)
	{
		join.flags |= WSM_FLAG_MAC_INSTANCE_1;
	}
	else
	{
		join.flags &= ~WSM_FLAG_MAC_INSTANCE_1;
	}

	if (join.ssidLength > sizeof(join.ssid))
	{
		join.ssidLength = sizeof(join.ssid);
	}

	if (wsm_join(hw_priv, &join, if_id))
	{
		atbm_printk_err("%s: join err.\n", __func__);
		ret = -1;
	}

err:
	return ret;
}

int atbm_wsm_get_status(struct atbm_common *hw_priv, unsigned int buff)
{
	int ret = 0;
	struct	wsm_sdio_getconfig_cnf cnf;	

	memset(&cnf, 0, sizeof(cnf));
	ret = wsm_get_config(hw_priv, &cnf, sizeof(cnf));
	if (!ret)
	{
		if (0 != copy_to_user((struct wsm_sdio_getconfig_cnf *)buff, &cnf, sizeof(struct	wsm_sdio_getconfig_cnf)))
		{
			atbm_printk_err("%s: copy_to_user err.\n", __func__);
			ret = -1;
		}
	}
	else
	{
		atbm_printk_err("%s: wsm_get_config err\n", __func__);
	}

	return ret;
}

int atbm_wsm_tcp_filter(struct atbm_common *hw_priv, unsigned int data, int set_flag)
{
	int ret = 0;
	struct	wsm_tcp_filter_req req;	

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&req, 0, sizeof(req));

	if (set_flag)
	{
		if (0 != copy_from_user(&req, (struct wsm_tcp_filter_req *)data, sizeof(struct wsm_tcp_filter_req)))
		{
			atbm_printk_err("%s: copy_from_user err.\n", __func__);
			ret = -1;
			goto err;
		}

		ret = wsm_set_tcp_filter(hw_priv, &req, sizeof(req));
		if (ret)
		{
			atbm_printk_err("%s: wsm_set_tcp_filter err.\n", __func__);
		}
		else
		{
			memcpy(&hw_priv->tcp_filter_req, &req, sizeof(req));
		}
	}
	else
	{
		ret = wsm_get_tcp_filter(hw_priv, &req, sizeof(req));
		if (ret)
		{
			atbm_printk_err("%s: wsm_get_tcp_filter err.\n", __func__);
			ret = -1;
			goto err;
		}

		if (0 != copy_to_user((struct wsm_tcp_filter_req *)data, &req, sizeof(req)))
		{
			atbm_printk_err("%s: copy_to_user err.\n", __func__);
			ret = -1;
		}
	}

err:
	return ret;
}

void scan_complete_work(struct work_struct *work)
{
	if (timer_info.scan_ok)
	{
		#ifdef LINUX_OS
		if (atbm_ioctl_notify_add(2, 0, 0, NULL, NULL) > 0)
		{
			kill_fasync (&connect_async, SIGIO, POLL_IN);
		}
		#endif
		timer_info.scan_state.scan_state = 0;
	}
	else
	{
		struct wsm_scan_state_req *state_req = &(timer_info.scan_state);
		wsm_get_scan_state(g_hw_priv, state_req, sizeof(struct wsm_scan_state_req));
	}
}

void scan_complete_check(unsigned long data)
{
	if (!timer_info.scan_state.scan_state)
	{
		timer_info.scan_ok = 1;
		queue_work(timer_info.workqueue, &timer_info.work);
		return;
	} 

	queue_work(timer_info.workqueue, &timer_info.work);
	atbm_mod_timer(&timer_info.timer, jiffies+msecs_to_jiffies(500));
}

int atbm_wsm_set_scan(struct atbm_common *hw_priv)
{
	int ret = 0;
	struct wsm_scan_req req;
	static int first_create = 1;

	if (!timer_info.scan_state.scan_state)
	{
		memset(&req, 0, sizeof(req));
		ret = wsm_set_scan(hw_priv, &req);
		if (ret)
		{
			atbm_printk_err("%s: wsm_set_scan err.\n", __func__);
		}
		else
		{
			if (first_create)
			{
				memset(&timer_info, 0, sizeof(timer_info));
				timer_info.workqueue = alloc_workqueue("scan_workqueue", 0, 0);
				INIT_WORK(&timer_info.work, scan_complete_work);
				atbm_init_timer(&timer_info.timer);
				timer_info.timer.function = scan_complete_check;
				timer_info.timer.data = 0;
				first_create = 0;
			}
			timer_info.scan_state.scan_state = 1;
			timer_info.scan_ok = 0;
			atbm_mod_timer(&timer_info.timer, jiffies);
		}
	}

	return ret;
}


int atbm_wsm_get_scan_state(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;

	if (0 != copy_to_user((char *)data, &(timer_info.scan_state.scan_state), sizeof(timer_info.scan_state.scan_state)))
	{
		atbm_printk_err("%s: copy_to_user err.\n", __func__);
		ret = -1;
		goto err;
	}
	
err:
	return ret;
}

int atbm_wsm_get_scan_info(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&result, 0, sizeof(result));

	if (0 != copy_from_user(&result, (struct wsm_scan_result_req *)data, sizeof(struct wsm_scan_result_req)))
	{
		atbm_printk_err("%s: copy_to_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_get_scan_info(hw_priv, &result, sizeof(result));
	if (ret)
	{
		atbm_printk_err("%s: wsm_get_scan_info err.\n", __func__);
		goto err;
	}

	if (result.status)
	{
		atbm_printk_err("%s: driver scanning.\n", __func__);
		ret = -1;
		goto err;
	}

	if (0 != copy_to_user((struct wsm_scan_result_req *)data, &result, sizeof(struct wsm_scan_result_req)))
	{
		atbm_printk_err("%s: copy_to_user err.\n", __func__);
		ret = -1;
		goto err;
	}
	
err:
	return ret;
}

int atbm_wsm_set_wifi_mode(struct atbm_common *hw_priv, char is_ap)
{
	int ret = 0;
	struct wsm_wifi_set_req mode_req;
	struct atbm_vif * vif;

	if (0 != is_ap && 1 != is_ap)
	{
		atbm_printk_err("%s: is_ap value err.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&mode_req, 0, sizeof(mode_req));
	mode_req.is_ap = is_ap;
	vif =__ABwifi_hwpriv_to_vifpriv(hw_priv,0);
	if(vif == NULL)
	{
		atbm_printk_err("%s: vif is null.\n", __func__);
		ret = -1;
		goto err;
	}

	if(is_ap){
		vif->type = NL80211_IFTYPE_AP;
	}
	else {
		vif->type = NL80211_IFTYPE_STATION;
	}	
	atbm_printk_err("%s:[%d][%d][%p]\n",__func__,vif->type,is_ap,vif);
	ret = wsm_set_wifimode(hw_priv, &mode_req, sizeof(mode_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_set_wifimode err.\n", __func__);
	}
	
err:
	return ret;
}

int atbm_wsm_set_ap_cfg(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;
	struct wsm_ap_cfg_req ap_cfg_req;
	struct atbm_vif * vif;
	vif =__ABwifi_hwpriv_to_vifpriv(hw_priv,0);

	if(vif == NULL){
		atbm_printk_err("%s: vif is null.\n", __func__);
		ret = -1;
		goto err;
	}
	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}
	memset(&ap_cfg_req, 0, sizeof(ap_cfg_req));
	if (0 != copy_from_user(&ap_cfg_req, (struct wsm_ap_cfg_req *)data, sizeof(struct wsm_ap_cfg_req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}
	if(ap_cfg_req.join_parameter.keyMgmt == KEY_MGMT_NONE){
		vif->ap_info.group_key.key_type = IEEE80211_ENC_TYPE;
		vif->ap_info.key.key_type = IEEE80211_ENC_TYPE;
	}
	else if((ap_cfg_req.join_parameter.keyMgmt == KEY_MGMT_WEP) || 
		    (ap_cfg_req.join_parameter.keyMgmt == KEY_MGMT_WEP_SHARED)){
		atbm_printk_err("%s:wep\n",__func__);
		vif->ap_info.group_key.key_type = IEEE80211_ENC_WEP;
		vif->ap_info.key.key_type = IEEE80211_ENC_WEP;
		vif->ap_info.group_key.conf.iv_len = WEP_IV_LEN;
		vif->ap_info.group_key.conf.icv_len = WEP_ICV_LEN;
		vif->ap_info.key.conf.iv_len = WEP_IV_LEN;
		vif->ap_info.key.conf.icv_len = WEP_ICV_LEN;
	}else if(ap_cfg_req.join_parameter.keyMgmt == KEY_MGMT_WPA){
		atbm_printk_err("%s:tkip\n",__func__);
		vif->ap_info.group_key.key_type = IEEE80211_ENC_TKIP;
		vif->ap_info.key.key_type = IEEE80211_ENC_TKIP;
		vif->ap_info.group_key.conf.iv_len = TKIP_IV_LEN;
		vif->ap_info.group_key.conf.icv_len = TKIP_ICV_LEN;
		vif->ap_info.key.conf.iv_len = TKIP_IV_LEN;
		vif->ap_info.key.conf.icv_len = TKIP_ICV_LEN;
	}else if(KEY_MGMT_WPA2 == ap_cfg_req.join_parameter.keyMgmt){
		atbm_printk_err("%s:aes\n",__func__);
		vif->ap_info.group_key.key_type = IEEE80211_ENC_AES;
		vif->ap_info.key.key_type = IEEE80211_ENC_AES;
		vif->ap_info.group_key.conf.iv_len = CCMP_HDR_LEN;
		vif->ap_info.group_key.conf.icv_len = CCMP_MIC_LEN;
		vif->ap_info.key.conf.iv_len = CCMP_HDR_LEN;
		vif->ap_info.key.conf.icv_len = CCMP_MIC_LEN;
	}
	vif->type = NL80211_IFTYPE_AP;
	memcpy(&vif->group_key,&vif->ap_info.group_key,sizeof(struct ieee80211_key));
	if (ap_cfg_req.join_parameter.ssidLength > sizeof(ap_cfg_req.join_parameter.ssid))
	{
		ap_cfg_req.join_parameter.ssidLength = sizeof(ap_cfg_req.join_parameter.ssid);
	}

	ret = wsm_set_ap_cfg(hw_priv, &ap_cfg_req, sizeof(ap_cfg_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_set_ap_cfg err.\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_set_wifi_channel(struct atbm_common *hw_priv, char channel)
{
	int ret = 0;
	struct wsm_wifi_set_req channel_req;

	if (channel <= 0 || channel > 14)
	{
		atbm_printk_err("%s: channel value err.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&channel_req, 0, sizeof(channel_req));
	channel_req.channel = channel;

	ret = wsm_set_wifichannel(hw_priv, &channel_req, sizeof(channel_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_set_wifichannel err.\n", __func__);
	}
	
err:
	return ret;
}

int atbm_wsm_set_country(struct atbm_common *hw_priv, char country)
{
	int ret = 0;
	struct wsm_wifi_set_req country_req;

	if (country >= COUNTRY_MAX)
	{
		atbm_printk_err("%s: country value err.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&country_req, 0, sizeof(country_req));
	country_req.countryId = country;

	ret = wsm_set_countryId(hw_priv, &country_req, sizeof(country_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_set_countryId err.\n", __func__);
	}
	
err:
	return ret;
}

int atbm_wsm_get_country(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;
	struct wsm_wifi_set_req country_req;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&country_req, 0, sizeof(country_req));
	ret = wsm_get_countryId(hw_priv, &country_req, sizeof(country_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_get_countryId err.\n", __func__);
		goto err;
	}

	if (0 != copy_to_user((char *)data, &(country_req.countryId), sizeof(country_req.countryId)))
	{
		atbm_printk_err("%s: copy_to_user err.\n", __func__);
		ret = -1;
		goto err;
	}
	
err:
	return ret;
}

int atbm_wsm_get_sta_list(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;
	struct wsm_sta_list_req stalist_req;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&stalist_req, 0, sizeof(stalist_req));
	ret = wsm_get_stalist(hw_priv, &stalist_req, sizeof(stalist_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_get_stalist err.\n", __func__);
		goto err;
	}

	if (0 != copy_to_user((struct wsm_sta_list_req *)data, &stalist_req, sizeof(struct wsm_sta_list_req)))
	{
		atbm_printk_err("%s: copy_to_user err.\n", __func__);
		ret = -1;
		goto err;
	}
	
err:
	return ret;
}

int atbm_wsm_smartcfg_start(struct atbm_common *hw_priv)
{
	int ret = 0;
	struct wsm_generic_req smartcfg_req;

	memset(&smartcfg_req, 0, sizeof(smartcfg_req));
	ret = wsm_smart_cfg_start(hw_priv, &smartcfg_req, sizeof(smartcfg_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_smart_cfg_start err.\n", __func__);
	}

	return ret;
}

int atbm_wsm_smartcfg_stop(struct atbm_common *hw_priv)
{
	int ret = 0;
	struct wsm_generic_req smartcfg_req;

	memset(&smartcfg_req, 0, sizeof(smartcfg_req));
	ret = wsm_smart_cfg_stop(hw_priv, &smartcfg_req, sizeof(smartcfg_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_smart_cfg_stop err.\n", __func__);
	}

	return ret;
}

int atbm_wsm_ap_touch_start(struct atbm_common *hw_priv, char data)
{
	int ret = 0;
	struct wsm_ap_touch_req ap_touch_req;

	memset(&ap_touch_req, 0, sizeof(ap_touch_req));
	ap_touch_req.is_no_notify = data?1:0;
	ret = wsm_ap_touch_start(hw_priv, &ap_touch_req, sizeof(ap_touch_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_ap_touch_start err.\n", __func__);
	}

	return ret;
}

int atbm_wsm_ap_touch_stop(struct atbm_common *hw_priv)
{
	int ret = 0;
	struct wsm_generic_req ap_touch_req;

	memset(&ap_touch_req, 0, sizeof(ap_touch_req));
	ret = wsm_ap_touch_stop(hw_priv, &ap_touch_req, sizeof(ap_touch_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_ap_touch_stop err.\n", __func__);
	}

	return ret;
}

int atbm_wsm_etf_start_tx(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;
	struct wsm_etf_req etf_req;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&etf_req, 0, sizeof(etf_req));
	if (0 != copy_from_user(&etf_req, (struct wsm_etf_req *)data, sizeof(struct wsm_etf_req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_etf_start_tx(hw_priv, &etf_req, sizeof(etf_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_etf_start_tx err.\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_etf_single_tone(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;
	struct wsm_etf_req etf_req;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&etf_req, 0, sizeof(etf_req));
	if (0 != copy_from_user(&etf_req, (struct wsm_etf_req *)data, sizeof(struct wsm_etf_req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_etf_single_tone(hw_priv, &etf_req, sizeof(etf_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_etf_single_tone err.\n", __func__);
		ret = -1;
	}

err:
	return ret;
}

int atbm_wsm_etf_stop_tx(struct atbm_common *hw_priv)
{
	int ret = 0;
	struct wsm_generic_req stop_tx_req;

	memset(&stop_tx_req, 0, sizeof(stop_tx_req));
	ret = wsm_etf_stop_tx(hw_priv, &stop_tx_req, sizeof(stop_tx_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_etf_stop_tx err.\n", __func__);
	}

	return ret;
}

int atbm_wsm_etf_start_rx(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;
	struct wsm_etf_req etf_req;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&etf_req, 0, sizeof(etf_req));
	if (0 != copy_from_user(&etf_req, (struct wsm_etf_req *)data, sizeof(struct wsm_etf_req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_etf_start_rx(hw_priv, &etf_req, sizeof(etf_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_etf_start_rx err.\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_etf_start_rx_no_drop(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;
	struct wsm_etf_req etf_req;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&etf_req, 0, sizeof(etf_req));
	if (0 != copy_from_user(&etf_req, (struct wsm_etf_req *)data, sizeof(struct wsm_etf_req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_etf_start_rx_no_drop(hw_priv, &etf_req, sizeof(etf_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_etf_start_rx err.\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_etf_stop_rx(struct atbm_common *hw_priv)
{
	int ret = 0;
	struct wsm_generic_req stop_rx_req;

	memset(&stop_rx_req, 0, sizeof(stop_rx_req));
	ret = wsm_etf_stop_rx(hw_priv, &stop_rx_req, sizeof(stop_rx_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_etf_stop_rx err.\n", __func__);
	}

	return ret;
}

int atbm_wsm_etf_reset_rx(struct atbm_common *hw_priv)
{
	int ret = 0;
	struct wsm_generic_req reset_rx_req;

	memset(&reset_rx_req, 0, sizeof(reset_rx_req));
	ret = wsm_etf_reset_rx(hw_priv, &reset_rx_req, sizeof(reset_rx_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_etf_reset_rx err.\n", __func__);
	}

	return ret;
}

int atbm_wsm_set_adaptive(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;
	struct wsm_adaptive_req adaptive_req;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&adaptive_req, 0, sizeof(adaptive_req));
	if (0 != copy_from_user(&adaptive_req, (struct wsm_adaptive_req *)data, sizeof(struct wsm_adaptive_req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_set_adaptive(hw_priv, &adaptive_req, sizeof(adaptive_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_set_adaptive err.\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_get_version(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;
	struct wsm_version_req ver_req;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&ver_req, 0, sizeof(ver_req));
	ret = wsm_get_ver(hw_priv, &ver_req, sizeof(ver_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_get_ver err.\n", __func__);
		goto err;
	}

	if (0 != copy_to_user((struct wsm_version_req *)data, &ver_req, sizeof(ver_req)))
	{
		atbm_printk_err("%s: copy_to_user err.\n", __func__);
		ret = -1;
		goto err;
	}
	
err:
	return ret;
}

int atbm_wsm_get_sdk_version(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;
	struct wsm_version_req ver_req;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&ver_req, 0, sizeof(ver_req));
	ret = wsm_get_sdk_ver(hw_priv, &ver_req, sizeof(ver_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_get_sdk_ver err.\n", __func__);
		goto err;
	}

	if (0 != copy_to_user((struct wsm_version_req *)data, &ver_req, sizeof(ver_req)))
	{
		atbm_printk_err("%s: copy_to_user err.\n", __func__);
		ret = -1;
		goto err;
	}

err:
	return ret;
}

int atbm_wsm_update_fw(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&update_req, 0, sizeof(update_req));
	if (0 != copy_from_user(&update_req, (struct wsm_update_req *)data, sizeof(update_req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_update_fw(hw_priv, &update_req, sizeof(update_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_update_fw err.\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_set_listen_itvl(struct atbm_common *hw_priv, char interval)
{
	int ret = 0;
	struct wsm_listen_itvl_req itvl_req;

	if (interval <= 0 || interval > 20)
	{
		atbm_printk_err("%s: interval value err.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&itvl_req, 0, sizeof(itvl_req));
	itvl_req.interval = interval;

	ret = wsm_set_listen_itvl(hw_priv, &itvl_req, sizeof(itvl_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_set_listen_itvl err.\n", __func__);
	}
	
err:
	return ret;
}

int atbm_wsm_send_at_cmd(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;
	struct wsm_at_cmd_req cmd_req;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&cmd_req, 0, sizeof(cmd_req));
	if (0 != copy_from_user(&cmd_req, (struct wsm_at_cmd_req *)data, sizeof(cmd_req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_send_at_cmd(hw_priv, &cmd_req, sizeof(cmd_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_send_at_cmd err.\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_set_dbg_print(struct atbm_common *hw_priv, char enable)
{
	int ret = 0;
	struct wsm_dbg_print_enable_req dbg_req;

	memset(&dbg_req, 0, sizeof(dbg_req));
	dbg_req.enable = enable?1:0;

	ret = wsm_set_dbg_print(hw_priv, &dbg_req, sizeof(dbg_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_set_dbg_print err.\n", __func__);
	}

	return ret;
}

int atbm_wsm_fw_sleep(struct atbm_common *hw_priv)
{
	int ret = 0;
	atbm_control_dbg(ATBM_CONTROL_DEBUG_SLEEP, "%s enter fw_version %d ...\n", __func__, hw_priv->wsm_caps.firmwareVersion);
	if (hw_priv->wsm_caps.firmwareVersion < 13549)
	{
		struct wsm_generic_req sleep_req;

		if (check_alive_info.is_start)
		{
			atbm_del_timer(&check_alive_info.timer);
		}

		memset(&sleep_req, 0, sizeof(sleep_req));
		ret = wsm_fw_sleep(hw_priv, &sleep_req, sizeof(sleep_req));
		if (ret)
		{
			atbm_printk_err("%s: wsm_fw_sleep err.\n", __func__);
			if (check_alive_info.is_start)
			{
				atbm_mod_timer(&check_alive_info.timer,jiffies+msecs_to_jiffies(check_alive_info.period));
			}
		}
		else
		{
			if (check_alive_info.is_start)
			{
				destroy_workqueue(check_alive_info.workqueue);
				check_alive_info.is_start = 0;
			}
			printk("atbm_wsm_fw_sleep ok! old rmmod version...\n");
		}
	}
	else if (!is_pre_rmmod)
	{
		if (check_alive_info.is_start)
		{
			atbm_del_timer(&check_alive_info.timer);
		}
		msleep(2);
		printk("sleep lock wait cmd over...\n");
		wsm_cmd_lock(hw_priv);
		hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
		is_pre_rmmod = 1;
		atbm_clear_wakeup_reg(hw_priv);
		hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
		wsm_cmd_unlock(hw_priv);
		hw_priv->sbus_ops->irq_unsubscribe(hw_priv->sbus_priv);
		hw_priv->close_driver = 1;
		if(hw_priv->sbus_ops->sbus_xmit_func_deinit)
			hw_priv->sbus_ops->sbus_xmit_func_deinit(hw_priv->sbus_priv);
		if(hw_priv->sbus_ops->sbus_rev_func_deinit)	
			hw_priv->sbus_ops->sbus_rev_func_deinit(hw_priv->sbus_priv);
		printk("atbm_wsm_fw_sleep ok! new rmmod version...\n");
	}
	atbm_control_dbg(ATBM_CONTROL_DEBUG_SLEEP, "%s exit, ret=%d...\n", __func__, ret);
	return ret;
}

int atbm_wsm_get_rate(struct atbm_common *hw_priv, unsigned int buff)
{
	int ret = 0;
	struct	wsm_get_rate_req rate_req;

	memset(&rate_req, 0, sizeof(rate_req));
	ret = wsm_get_tx_rate(hw_priv, &rate_req, sizeof(rate_req));
	if (!ret)
	{
		if (0 != copy_to_user((struct wsm_get_rate_req *)buff, &rate_req, sizeof(struct	wsm_get_rate_req)))
		{
			atbm_printk_err("%s: copy_to_user err.\n", __func__);
			ret = -1;
		}
	}
	else
	{
		atbm_printk_err("%s: wsm_get_tx_rate err\n", __func__);
	}

	return ret;
}

int atbm_wsm_send_ipc_data(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;
	struct wsm_ipc_data_req data_req;

	if (0 == data)
	{
		atbm_printk_err("%s: ipc data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&data_req, 0, sizeof(data_req));
	if (0 != copy_from_user(&data_req, (struct wsm_ipc_data_req *)data, sizeof(data_req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_send_ipc_data(hw_priv, &data_req, sizeof(data_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_send_ipc_data err.\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_get_rssi(struct atbm_common *hw_priv, unsigned int buff)
{
	int ret = 0;
	struct	wsm_rssi_req rssi_req;

	memset(&rssi_req, 0, sizeof(rssi_req));
	ret = wsm_get_rssi(hw_priv, &rssi_req, sizeof(rssi_req));
	if (!ret)
	{
		if (0 != copy_to_user((struct wsm_rssi_req *)buff, &rssi_req, sizeof(struct	wsm_rssi_req)))
		{
			atbm_printk_err("%s: copy_to_user err.\n", __func__);
			ret = -1;
		}
	}
	else
	{
		atbm_printk_err("%s: wsm_get_rssi err\n", __func__);
	}

	return ret;
}

int atbm_wsm_get_time(struct atbm_common *hw_priv, unsigned int buff)
{
	int ret = 0;
	struct wsm_time_req time_req;

	memset(&time_req, 0, sizeof(time_req));
	ret = wsm_get_time(hw_priv, &time_req, sizeof(time_req));
	if (!ret && !time_req.status)
	{
		if (0 != copy_to_user((struct wsm_time_req *)buff, &time_req, sizeof(struct	wsm_time_req)))
		{
			atbm_printk_err("%s: copy_to_user err.\n", __func__);
			ret = -1;
		}
	}
	else
	{
		atbm_printk_err("%s: wsm_get_time err\n", __func__);
		ret = -1;
	}

	return ret;
}

int atbm_wsm_clear_wifi_config(struct atbm_common *hw_priv)
{
	int ret = 0;
	struct wsm_generic_req clear_req;

	memset(&clear_req, 0, sizeof(clear_req));
	ret = wsm_clear_wifi_config(hw_priv, &clear_req, sizeof(clear_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_clear_wifi_config err.\n", __func__);
	}

	return ret;
}

int atbm_wsm_get_etf_rx_info(struct atbm_common *hw_priv, unsigned int buff)
{
	int ret = 0;
	struct wsm_etf_rx_info_req rx_info_req;

	memset(&rx_info_req, 0, sizeof(rx_info_req));
	ret = wsm_get_etf_rx_info(hw_priv, &rx_info_req, sizeof(rx_info_req));
	if (!ret && !rx_info_req.status)
	{
		if (0 != copy_to_user((struct wsm_etf_rx_info_req *)buff, &rx_info_req, sizeof(struct	wsm_etf_rx_info_req)))
		{
			atbm_printk_err("%s: copy_to_user err.\n", __func__);
			ret = -1;
		}
	}
	else
	{
		atbm_printk_err("%s: wsm_get_etf_rx_info err\n", __func__);
		ret = -1;
	}

	return ret;
}

int atbm_wsm_pre_rmmod(struct atbm_common *hw_priv)
{
	if (hw_priv->wsm_caps.firmwareVersion < 13549){
		printk("atbm_wsm_pre_rmmod old rmmod version...\n");
		is_pre_rmmod = 1;
	}
	else {
		printk("atbm_wsm_pre_rmmod new rmmod version...\n");
		atbm_wsm_fw_sleep(hw_priv);
	}
	return 0;
}

int atbm_wsm_is_tx_buffer_empty(struct atbm_common *hw_priv, unsigned long buff)
{
	int ret = 0;
	char is_empty = 0;

	if (atbm_skb_queue_empty(&hw_priv->tx_frame_queue))
	{
		is_empty = 1;	
	}

	if (0 != copy_to_user((char *)buff, &is_empty, sizeof(char)))
	{
		atbm_printk_err("%s: copy_to_user err.\n", __func__);
		ret = -1;
	}
	atbm_control_dbg(ATBM_CONTROL_DEBUG_SLEEP, "%s empty=%d ret=%d\n", __func__, is_empty, ret);
	return ret;
}

int atbm_wsm_set_wakeup_event(struct atbm_common *hw_priv, int wakeup_event)
{
	int ret = 0;
	struct wsm_wakeup_event_req req;

	memset(&req, 0, sizeof(req));
	req.event = wakeup_event;
	ret = wsm_set_wakeup_event(hw_priv, &req, sizeof(struct wsm_wakeup_event_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_set_wakeup_event err\n", __func__);
	}

	return ret;
}

int atbm_wsm_add_netpattern_info(struct atbm_common *hw_priv, unsigned long buff)
{
	int ret = 0;
	struct wsm_netpattern_info req;

	memset(&req, 0, sizeof(req));
	if (0 != copy_from_user(&req, (struct wsm_netpattern_info *)buff, sizeof(req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_add_netpattern_info(hw_priv, &req, sizeof(struct wsm_netpattern_info));
	if (ret)
	{
		atbm_printk_err("%s: wsm_add_netpattern_info err\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_del_netpattern_info(struct atbm_common *hw_priv, unsigned long buff)
{
	int ret = 0;
	struct wsm_netpattern_info req;

	memset(&req, 0, sizeof(req));
	if (0 != copy_from_user(&req, (struct wsm_netpattern_info *)buff, sizeof(req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_del_netpattern_info(hw_priv, &req, sizeof(struct wsm_netpattern_info));
	if (ret)
	{
		atbm_printk_err("%s: wsm_del_netpattern_info err\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_add_conn_param_info(struct atbm_common *hw_priv, unsigned long buff)
{
	int ret = 0;
	struct wsm_conn_param_info req;

	memset(&req, 0, sizeof(req));
	if (0 != copy_from_user(&req, (struct wsm_conn_param_info *)buff, sizeof(req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_add_conn_param_info(hw_priv, &req, sizeof(struct wsm_conn_param_info));
	if (ret)
	{
		atbm_printk_err("%s: wsm_add_conn_param_info err\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_del_conn_param_info(struct atbm_common *hw_priv, unsigned long buff)
{
	int ret = 0;
	struct wsm_conn_param_info req;

	memset(&req, 0, sizeof(req));
	if (0 != copy_from_user(&req, (struct wsm_conn_param_info *)buff, sizeof(req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_del_conn_param_info(hw_priv, &req, sizeof(struct wsm_conn_param_info));
	if (ret)
	{
		atbm_printk_err("%s: wsm_del_conn_param_info err\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_set_wk_ssid(struct atbm_common *hw_priv, unsigned long buff)
{
	int ret = 0;
	struct wsm_wakeup_ssid_info req;

	memset(&req, 0, sizeof(req));
	if (0 != copy_from_user(&req, (struct wsm_wakeup_ssid_info *)buff, sizeof(req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_set_wakeup_ssid(hw_priv, &req, sizeof(struct wsm_wakeup_ssid_info));
	if (ret)
	{
		atbm_printk_err("%s: wsm_set_wakeup_ssid err\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_clear_wk_ssid(struct atbm_common *hw_priv, unsigned long buff)
{
	int ret = 0;
	struct wsm_wakeup_ssid_info req;

	memset(&req, 0, sizeof(req));
	if (0 != copy_from_user(&req, (struct wsm_wakeup_ssid_info *)buff, sizeof(req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_clear_wakeup_ssid(hw_priv, &req, sizeof(struct wsm_wakeup_ssid_info));
	if (ret)
	{
		atbm_printk_err("%s: wsm_clear_wakeup_ssid err\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_conn_lose_map(struct atbm_common *hw_priv, unsigned long buff)
{
	int ret = 0;
	struct wsm_conn_lose_info req;

	ret = wsm_conn_lose(hw_priv, &req, sizeof(struct wsm_conn_lose_info));
	if (!ret)
	{
		if (0 != copy_to_user((struct wsm_conn_lose_info *)buff, &req, sizeof(struct wsm_conn_lose_info)))
		{
			atbm_printk_err("%s: copy_to_user err.\n", __func__);
			ret = -1;
		}
	}
	else
	{
		atbm_printk_err("%s: wsm_conn_lose err\n", __func__);
	}

	return ret;
}

int atbm_wsm_conn_switch(struct atbm_common *hw_priv, unsigned long buff)
{
	int ret = 0;
	struct wsm_conn_switch_info req;

	memset(&req, 0, sizeof(req));
	if (0 != copy_from_user(&req, (struct wsm_conn_switch_info *)buff, sizeof(req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_conn_switch(hw_priv, &req, sizeof(struct wsm_conn_switch_info));
	if (ret)
	{
		atbm_printk_err("%s: wsm_conn_switch err\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_auto_reconnect(struct atbm_common *hw_priv, unsigned long buff)
{
	int ret = 0;
	struct wsm_auto_reconnect_req req;

	memset(&req, 0, sizeof(req));
	if (0 != copy_from_user(&req, (struct wsm_auto_reconnect_req *)buff, sizeof(req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_auto_reconnect(hw_priv, &req, sizeof(struct wsm_auto_reconnect_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_auto_reconnect err\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_send_customer_cmd(struct atbm_common *hw_priv, unsigned long buff)
{
	int ret = 0;
	struct wsm_customer_cmd_req req;

	memset(&req, 0, sizeof(req));
	if (0 != copy_from_user(&req, (struct wsm_customer_cmd_req *)buff, sizeof(req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_send_customer_cmd(hw_priv, &req, sizeof(struct wsm_customer_cmd_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_send_customer_cmd err\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_customer_cert_save(struct atbm_common *hw_priv, unsigned long buff)
{
	int ret = 0;

	memset(&hw_priv->cert_save_req, 0, sizeof(struct wsm_customer_cert_save_req));
	if (0 != copy_from_user(&hw_priv->cert_save_req, (struct wsm_customer_cert_save_req *)buff, sizeof(struct wsm_customer_cert_save_req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_customer_cert_save(hw_priv, &hw_priv->cert_save_req, sizeof(struct wsm_customer_cert_save_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_customer_cert_save err\n", __func__);
	}

err:
	return ret;
}

void check_alive_work(struct work_struct *work)
{
	int ret = 0;
	struct wsm_check_alive_req req;

	check_alive_info.in_check = 1;
	memset(&req, 0, sizeof(req));
	req.alive_notify = 1212;
	req.period = check_alive_info.period / 1000;
	req.tmo_cnt = check_alive_info.tmo_cnt;
	ret = wsm_check_alive(g_hw_priv, &req, sizeof(struct wsm_check_alive_req));
	if (!ret)
	{
		check_alive_info.cur_cnt = 0;
	}
	check_alive_info.in_check = 0;
}

void sdio_alive_check_cb(unsigned long data)
{
	check_alive_info.cur_cnt++;
	if (check_alive_info.cur_cnt >= check_alive_info.tmo_cnt)
	{
		printk("check alive fail over\n");
	}
	else
	{
		if (!check_alive_info.in_check)
		{
			queue_work(check_alive_info.workqueue, &check_alive_info.work);
		}
		atbm_mod_timer(&check_alive_info.timer, jiffies+msecs_to_jiffies(check_alive_info.period));
	}
}

int atbm_wsm_start_check_alive(struct atbm_common *hw_priv, unsigned long buff)
{
	int ret = 0;
	struct wsm_check_alive_req req;
	static int is_first = 1;

	memset(&req, 0, sizeof(req));
	if (0 != copy_from_user(&req, (struct wsm_check_alive_req *)buff, sizeof(req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}
	if (req.period < 1 || req.tmo_cnt < 2)
	{
		atbm_printk_err("%s: invalid params.\n", __func__);
		ret = -1;
		goto err;
	}

	req.alive_notify = 1212;

	if (!is_first && check_alive_info.is_start)
	{
		atbm_del_timer(&check_alive_info.timer);
	}

	ret = wsm_check_alive(hw_priv, &req, sizeof(struct wsm_check_alive_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_customer_cert_save err\n", __func__);
		if (!is_first && check_alive_info.is_start)
		{
			atbm_mod_timer(&check_alive_info.timer,jiffies+msecs_to_jiffies(check_alive_info.period));
		}
	}
	else
	{
		if (is_first)
		{
			check_alive_info.workqueue = alloc_workqueue("check_alive_", 0, 0);
			INIT_WORK(&check_alive_info.work, check_alive_work);
			atbm_init_timer(&check_alive_info.timer);
			check_alive_info.timer.function = sdio_alive_check_cb;
			check_alive_info.timer.data = 0;
			check_alive_info.in_check = 0;
			is_first = 0;
		}
		check_alive_info.period = req.period * 1000;
		check_alive_info.tmo_cnt = req.tmo_cnt;
		check_alive_info.cur_cnt = 0;
		check_alive_info.is_start = 1;
		atbm_mod_timer(&check_alive_info.timer,jiffies+msecs_to_jiffies(check_alive_info.period));
	}

err:
	return ret;
}

int atbm_wsm_direct_trans_buffer(struct atbm_common *hw_priv, unsigned long buff)
{
	int ret = 0;

	memset(&hw_priv->direct_buffer_req, 0, sizeof(struct wsm_direct_trans_buffer_req));
	if (0 != copy_from_user(&hw_priv->direct_buffer_req, (struct wsm_direct_trans_buffer_req *)buff, sizeof(struct wsm_direct_trans_buffer_req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_direct_trans_buffer(hw_priv, &hw_priv->direct_buffer_req, sizeof(struct wsm_direct_trans_buffer_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_direct_trans_buffer err\n", __func__);
	}
	else
	{
		if (0 != copy_to_user((struct wsm_direct_trans_buffer_req *)buff, &hw_priv->direct_buffer_req, sizeof(struct wsm_direct_trans_buffer_req)))
		{
			atbm_printk_err("%s: copy_to_user err.\n", __func__);
			ret = -1;
		}
	}

err:
	return ret;
}

u32 atbm_control_debug_mask = 0;

int atbm_wsm_set_control_debug_mask(struct atbm_common *hw_priv, u32 debug_mask)
{
	atbm_control_debug_mask = debug_mask;
	atbm_printk_always("%s: update debug mask %x.\n", __func__, atbm_control_debug_mask);
	return 0;
}

//force 6441 reboot
int atbm_wsm_force_reboot(struct atbm_common *hw_priv)
{
	int ret = 0;
	struct wsm_generic_req reboot_req;

	memset(&reboot_req, 0, sizeof(reboot_req));
	ret = wsm_force_reboot(hw_priv, &reboot_req, sizeof(reboot_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_force_reboot err.\n", __func__);
	}
	else
	{
		atbm_wsm_fw_sleep(hw_priv);
	}
	return ret;
}

//host reboot
int atbm_wsm_host_reboot_notify(struct atbm_common *hw_priv)
{
	int ret = 0;
	struct wsm_generic_req reboot_req;

	memset(&reboot_req, 0, sizeof(reboot_req));
	ret = wsm_host_reboot_notify(hw_priv, &reboot_req, sizeof(reboot_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_host_reboot_notify err.\n", __func__);
	}
	return ret;
}

int atbm_wsm_fast_cfg_recv(struct atbm_common *hw_priv, unsigned long data)
{
	int ret = 0;
	struct  wsm_fast_cfg_recv_req fast_cfg;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&fast_cfg, 0, sizeof(fast_cfg));
	if (0 != copy_from_user(&fast_cfg, (struct wsm_fast_cfg_recv_req *)data, sizeof(struct wsm_fast_cfg_recv_req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_ext_fast_cfg_recv(hw_priv,&fast_cfg,sizeof(fast_cfg));
	if (ret)
	{
		atbm_printk_err("%s: wsm_set_psmode err.\n", __func__);
	}

err:
	return ret;
}

int atbm_wsm_fast_cfg_send(struct atbm_common *hw_priv, unsigned long data)
{
	int ret = 0;
	struct  wsm_fast_cfg_send_req fast_cfg;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&fast_cfg, 0, sizeof(fast_cfg));
	if (0 != copy_from_user(&fast_cfg, (struct wsm_fast_cfg_send_req *)data, sizeof(struct wsm_fast_cfg_send_req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	ret = wsm_ext_fast_cfg_send(hw_priv,&fast_cfg,sizeof(fast_cfg));
	if (ret)
	{
		atbm_printk_err("%s: wsm_set_psmode err.\n", __func__);
	}

err:
	return ret;
}



#ifdef CONFIG_ATBM_SDIO_ATCMD
struct at_cmd_direct cmd_req;
int atbm_at_cmd_direct_send(struct atbm_common *hw_priv, unsigned int data)
{
	int ret = 0;
	u32 put;
	struct wsm_hdr_tx *wsm_h;

	if (0 == data)
	{
		atbm_printk_err("%s: info data is null.\n", __func__);
		ret = -1;
		goto err;
	}

	memset(&cmd_req, 0, sizeof(cmd_req));
	if (0 != copy_from_user(&cmd_req, (struct at_cmd_direct *)data, sizeof(cmd_req)))
	{
		atbm_printk_err("%s: copy_from_user err.\n", __func__);
		ret = -1;
		goto err;
	}

	if((hw_priv->at_cmd_put - hw_priv->at_cmd_get) >= ATBM_AT_CMD_MAX_SW_CACHE){
		atbm_printk_err("%s: atcmd software cache full.\n", __func__);
		ret = -1;
		goto err;		
	}

	spin_lock_bh(&hw_priv->wsm_cmd.lock);
	put = hw_priv->at_cmd_put & (ATBM_AT_CMD_MAX_SW_CACHE - 1);
	BUG_ON(hw_priv->at_cmd_buf[put] == NULL);
	memset(hw_priv->at_cmd_buf[put], 0, MAX_WSM_BUF_LEN);

	wsm_h = (struct wsm_hdr_tx *)hw_priv->at_cmd_buf[put];
	wsm_h->len =__cpu_to_le16(cmd_req.len + sizeof(struct wsm_hdr_tx));
	wsm_h->id =  __cpu_to_le16(WSM_SDIO_ATCMD_DIRECT_ID);
	memcpy(hw_priv->at_cmd_buf[put]+sizeof(struct wsm_hdr_tx), cmd_req.cmd, cmd_req.len);
	hw_priv->at_cmd_put ++;
	spin_unlock_bh(&hw_priv->wsm_cmd.lock);
	
	atbm_bh_wakeup(hw_priv);
err:
	return ret;	
}
#endif

#ifdef LINUX_OS
static long atbm_unlocked_ioctl(struct file *filp, unsigned int cmd, unsigned long arg)
{
	long ret = 0;

	switch (cmd)
	{
		case ATBM_PS_SET:
			ret = atbm_wsm_ps(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_CONNECT:
			ret = atbm_wsm_connect(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_STATUS:
			ret = atbm_wsm_get_status(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_SET_FILTER:
			ret = atbm_wsm_tcp_filter(((struct atbm_info *)(filp->private_data))->hw_priv, arg, 1);
			break;

		case ATBM_GET_FILTER:
			ret = atbm_wsm_tcp_filter(((struct atbm_info *)(filp->private_data))->hw_priv, arg, 0);
			break;

		case ATBM_SCAN:
			ret = atbm_wsm_set_scan(((struct atbm_info *)(filp->private_data))->hw_priv);
			break;

		case ATBM_SCAN_INFO:
			ret = atbm_wsm_get_scan_info(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_WIFI_MODE:
			ret = atbm_wsm_set_wifi_mode(((struct atbm_info *)(filp->private_data))->hw_priv, (char)arg);
			break;

		case ATBM_AP_CFG:
			ret = atbm_wsm_set_ap_cfg(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_WIFI_CHANNEL:
			ret = atbm_wsm_set_wifi_channel(((struct atbm_info *)(filp->private_data))->hw_priv, (char)arg);
			break;

		case ATBM_SET_COUNTRY:
			ret = atbm_wsm_set_country(((struct atbm_info *)(filp->private_data))->hw_priv, (char)arg);
			break;

		case ATBM_GET_COUNTRY:
			ret = atbm_wsm_get_country(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_GET_STALIST:
			ret = atbm_wsm_get_sta_list(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_SMART_START:
			ret = atbm_wsm_smartcfg_start(((struct atbm_info *)(filp->private_data))->hw_priv);
			break;

		case ATBM_SMART_STOP:
			ret = atbm_wsm_smartcfg_stop(((struct atbm_info *)(filp->private_data))->hw_priv);
			break;

		case ATBM_APTOUCH_START:
			ret = atbm_wsm_ap_touch_start(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_APTOUCH_STOP:
			ret = atbm_wsm_ap_touch_stop(((struct atbm_info *)(filp->private_data))->hw_priv);
			break;

		case ATBM_ETF_START_TX:
			ret = atbm_wsm_etf_start_tx(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_ETF_SINGLETONE:
			ret = atbm_wsm_etf_single_tone(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_ETF_STOP_TX:
			ret = atbm_wsm_etf_stop_tx(((struct atbm_info *)(filp->private_data))->hw_priv);
			break;

		case ATBM_ETF_START_RX:
			ret = atbm_wsm_etf_start_rx(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_ETF_STOP_RX:
			ret = atbm_wsm_etf_stop_rx(((struct atbm_info *)(filp->private_data))->hw_priv);
			break;

		case ATBM_ETF_RESET_RX:
			ret = atbm_wsm_etf_reset_rx(((struct atbm_info *)(filp->private_data))->hw_priv);
			break;

		case ATBM_ADAPTIVE:
			ret = atbm_wsm_set_adaptive(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_VERSION:
			ret = atbm_wsm_get_version(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_SDK_VERSION:
			ret = atbm_wsm_get_sdk_version(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_UPDATE_FW:
			ret = atbm_wsm_update_fw(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_LISTEN_ITVL:
			ret = atbm_wsm_set_listen_itvl(((struct atbm_info *)(filp->private_data))->hw_priv, (char)arg);
			break;

		case ATBM_FW_AT_CMD:
			ret = atbm_wsm_send_at_cmd(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_FW_DBG_PRINT:
			ret = atbm_wsm_set_dbg_print(((struct atbm_info *)(filp->private_data))->hw_priv, (char)arg);
			break;

		case ATBM_ETF_START_RX_NO_DROP:
			ret = atbm_wsm_etf_start_rx_no_drop(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_FW_SLEEP:
			ret = atbm_wsm_fw_sleep(((struct atbm_info *)(filp->private_data))->hw_priv);
			break;

		case ATBM_TX_RATE:
			ret = atbm_wsm_get_rate(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_IPC_DATA:
			ret = atbm_wsm_send_ipc_data(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_RSSI:
			ret = atbm_wsm_get_rssi(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_TIME:
			ret = atbm_wsm_get_time(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_CLEAR_WIFI_CFG:
			ret = atbm_wsm_clear_wifi_config(((struct atbm_info *)(filp->private_data))->hw_priv);
			break;

		case ATBM_ETF_RX_INFO:
			ret = atbm_wsm_get_etf_rx_info(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;

		case ATBM_PRE_RMMOD:
			ret = atbm_wsm_pre_rmmod(((struct atbm_info *)(filp->private_data))->hw_priv);
			break;

		case ATBM_TX_EMPTY:
			ret = atbm_wsm_is_tx_buffer_empty(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_WKUP_EVENT:
			ret = atbm_wsm_set_wakeup_event(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_NETPATTERN_ADD:
			ret = atbm_wsm_add_netpattern_info(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_NETPATTERN_DEL:
			ret = atbm_wsm_del_netpattern_info(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_CONN_PARAM_ADD:
			ret = atbm_wsm_add_conn_param_info(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_CONN_PARAM_DEL:
			ret = atbm_wsm_del_conn_param_info(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_CONN_LOSE_MAP:
			ret = atbm_wsm_conn_lose_map(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_CONN_SWITCH:
			ret = atbm_wsm_conn_switch(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_SET_WK_SSID:
			ret = atbm_wsm_set_wk_ssid(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_CLR_WK_SSID:
			ret = atbm_wsm_clear_wk_ssid(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_AUTO_RECONN:
			ret = atbm_wsm_auto_reconnect(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_CUSTOMER_CMD:
			ret = atbm_wsm_send_customer_cmd(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_CUSTOMER_CERT:
			ret = atbm_wsm_customer_cert_save(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_CHECK_ALIVE:
			ret = atbm_wsm_start_check_alive(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_DIRECT_BUFFER:
			ret = atbm_wsm_direct_trans_buffer(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_CONTROL_DEBUG:
			ret = atbm_wsm_set_control_debug_mask(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_FORCE_REBOOT:
			ret = atbm_wsm_force_reboot(((struct atbm_info *)(filp->private_data))->hw_priv);
			break;
#ifdef CONFIG_ATBM_SDIO_ATCMD
		case ATBM_AT_CMD_DIRECT:
			ret = atbm_at_cmd_direct_send(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
#endif
		case ATBM_FAST_CFG_RECV:
			ret = atbm_wsm_fast_cfg_recv(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		case ATBM_FAST_CFG_SEND:
			ret = atbm_wsm_fast_cfg_send(((struct atbm_info *)(filp->private_data))->hw_priv, arg);
			break;
		default:
			atbm_printk_err("%s cmd %d invalid.\n", __func__, cmd);
			ret = -1;
	}

	return ret;
}


static int atbm_ioctl_fasync(int fd, struct file *filp, int on)
{
	return fasync_helper(fd, filp, on, &connect_async);
}

static int atbm_ioctl_open(struct inode *inode, struct file *filp)
{
	int time_cnt = 100;
	struct atbm_common *hw_priv = NULL;

	while (NULL == (hw_priv=atbm_hw_priv_dereference()))
	{
		msleep(10);
		time_cnt--;
		if (time_cnt <= 0)
		{
			return -1;
		}
	}
	while (!hw_priv->init_done || !hw_net_cfg_ok)
	{
		msleep(10);
		time_cnt--;
		if (time_cnt <= 0)
		{
			return -1;
		}
	}
	atbm_info.hw_priv = hw_priv;
	filp->private_data = &atbm_info;
	printk("atbm_ioctl_open cost time: %d ms\n", 10*(100-time_cnt));
	return 0;
}

static int atbm_ioctl_release(struct inode *inode, struct file *filp)
{
	atbm_ioctl_fasync(-1, filp, 0);
	filp->private_data = NULL;
	return 0;
}

static ssize_t atbm_ioctl_read(struct file *filp, char __user *buff, size_t len, loff_t *off)
{
	int ret = 0;
	struct atbm_status_event *event = NULL;

	if (sizeof(struct status_async) > len)
	{
		atbm_printk_err("%s: buff len is not enough.\n", __func__);
		return -1;
	}

	if (list_empty(&s_status_head))
	{
		atbm_printk_err("%s: status list is empty.\n", __func__);
		return -1;
	}

	spin_lock_bh(&s_status_queue_lock);
	event = list_first_entry(&s_status_head, struct atbm_status_event, link);
	if (event)
	{
		if (s_cur_status_list_cnt >= 2)
		{
			event->status.list_empty = 0;
		}
		else
		{
			event->status.list_empty = 1;
		}
		spin_unlock_bh(&s_status_queue_lock);
		ret = copy_to_user(buff, &event->status, sizeof(struct status_async));
		spin_lock_bh(&s_status_queue_lock);
		if (ret)
		{
			atbm_printk_err("%s: copy_to_user err %d.\n", __func__, ret);
		}
		else
		{
			list_del(&event->link);
			atbm_kfree(event);
			s_cur_status_list_cnt--;
		}
	}
	else
	{
		ret = -1;
	}
	spin_unlock_bh(&s_status_queue_lock);
	
	if (ret)
	{
		return -1;
	}

	return sizeof(struct status_async);
}

static struct file_operations atbm_ioctl_fops = {
    .owner = THIS_MODULE,
    .open = atbm_ioctl_open,
    .release = atbm_ioctl_release,
    .read = atbm_ioctl_read,
    .unlocked_ioctl = atbm_unlocked_ioctl,
    .fasync = atbm_ioctl_fasync,
};

int atbm_ioctl_add(void)
{
	memset(&atbm_info, 0, sizeof(struct atbm_info));
	
	atbm_info.devid = MKDEV(239,0);
	register_chrdev_region(atbm_info.devid, 1, "atbm ioctl");
	//alloc_chrdev_region(&atbm_info.devid, 0, 1, "atbm_ioctl");
	atbm_info.my_cdev = cdev_alloc();
	cdev_init(atbm_info.my_cdev, &atbm_ioctl_fops);
	atbm_info.my_cdev->owner = THIS_MODULE;
	cdev_add(atbm_info.my_cdev, atbm_info.devid, 1);
	atbm_info.my_class = class_create(THIS_MODULE, "atbm_ioctl_class");
	atbm_info.my_device = device_create(atbm_info.my_class, NULL, atbm_info.devid, NULL, "atbm_ioctl");
	spin_lock_init(&s_status_queue_lock);
	INIT_LIST_HEAD(&s_status_head);

	return 0;
}

void atbm_ioctl_free(void)
{
	device_destroy(atbm_info.my_class, atbm_info.devid);
	class_destroy(atbm_info.my_class);
	cdev_del(atbm_info.my_cdev);
	unregister_chrdev_region(atbm_info.devid, 1);
	memset(&atbm_info, 0, sizeof(struct atbm_info));

	spin_lock_bh(&s_status_queue_lock);
	while (!list_empty(&s_status_head)) {
		struct atbm_status_event *event =
			list_first_entry(&s_status_head, struct atbm_status_event,
			link);
		list_del(&event->link);
		atbm_kfree(event);
		s_cur_status_list_cnt--;
	}
	spin_unlock_bh(&s_status_queue_lock);
}
#endif

