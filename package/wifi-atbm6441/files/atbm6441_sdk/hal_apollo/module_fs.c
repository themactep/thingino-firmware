#include <linux/module.h>
#include <linux/kobject.h>
#include <linux/kthread.h>
#include <linux/dcache.h>
#include <linux/netdevice.h>
#include <linux/rtnetlink.h>
#include <net/net_namespace.h>
#include "apollo.h"
#include "bh.h"
#include "hwio.h"
#include "wsm.h"
#include "sbus.h"
#include "iface.h"
#include "module_fs.h"
#include "svn_version.h"
#define PARAMAS_SET			BIT(0)
#define PARAMAS_ON			BIT(1)
static bool enable_echo = true;
static int  num_echo    = -1;

#define ATBM_SHOW_MSG_MAX_SIZE		PAGE_SIZE


#define ATBM_CODE__EXAMPLE_CODE		0
#define ATBM_CODE__MAX				1

extern struct atbm_common 			*g_hw_priv;

#define atbm_show_init(show,_buff)	rcu_assign_pointer((show)->show_buff,_buff); \
										(show)->show_count = 0; \
										(show)->show_size = ATBM_SHOW_MSG_MAX_SIZE;	\
										(show)->overflow = 0
#define atbm_show_deinit(show)		rcu_assign_pointer((show)->show_buff,NULL);			\
									(show)->show_count = 0;				\
									(show)->show_size=0;				\
									(show)->overflow = 0				
#define atbm_module_show_put(_show,...)	\
	do{										\
		int ret = 0;						\
		char *_show_buff;					\
		rcu_read_lock();					\
		_show_buff = rcu_dereference((_show)->show_buff);	\
		if((_show_buff == NULL)||((_show)->overflow == 1) || ((_show)->show_size<=(_show)->show_count)){\
			if(_show_buff) atbm_printk_debug("overflow(%d),show_size(%d),show_count(%d)\n",(_show)->overflow,(_show)->show_size,(_show)->show_count); \
			rcu_read_unlock();							\
			break;										\
		}												\
		ret = snprintf(_show_buff+(_show)->show_count,(_show)->show_size-(_show)->show_count,__VA_ARGS__);\
		if(ret>=0){											\
			(_show)->show_count+=ret;						\
			if((_show)->show_count >= (_show)->show_size){  \
				(_show)->show_count = (_show)->show_size;	\
				(_show)->overflow = 1;						\
			}												\
		}													\
		else{												\
			(_show)->overflow = 1;							\
			atbm_printk_always("buff overflow(%d)(%d)\n",(_show)->show_size,(_show)->show_count);			\
		}																								\
		rcu_read_unlock();																				\
	}while(0)

#define atbm_module_put(_show,_src,_len)				\
	do{													\
		char *_show_buff;								\
		if((_show)->show_count+_len>(_show)->show_size)	\
			(_show)->overflow = 1;						\
		if((_show)->overflow)		break;				\
		rcu_read_lock();								\
		_show_buff = rcu_dereference((_show)->show_buff);		\
		if(_show_buff == NULL){									\
			rcu_read_unlock();									\
			break;												\
		}														\
		memcpy(_show_buff+(_show)->show_count,_src,_len);		\
		(_show)->show_count += _len;							\
		rcu_read_unlock();										\
	}while(0)
		
struct mutex atbm_module_fs_lock; 
#define atbm_modulefs_lock_int()		mutex_init(&atbm_module_fs_lock)
#define atbm_modulefs_lock()			mutex_lock(&atbm_module_fs_lock)
#define atbm_modulefs_unlock()			mutex_unlock(&atbm_module_fs_lock)
#define atbm_modulefs_trylock() 		mutex_trylock(&atbm_module_fs_lock)
#define atbm_modulefs_lock_release()	mutex_destroy(&atbm_module_fs_lock)
#define atbm_modulefs_lock_check()		lockdep_assert_held(&atbm_module_fs_lock)

struct atbm_module_show
{
	char __rcu *show_buff;
	int  show_count;
	int  show_size;
	int  overflow;
};

struct atbm_sting_s{
	const char *string;
	const char *string_pos;
	struct hlist_node hnode;
	bool found;
	unsigned int len;
	unsigned int params;
	bool (*string_func)(const char *pos_l,const char *pos_r,void *priv);
	void *priv;
};
#define ATBM_STRING_MAX_LEN				32
#define ATBM_STRING_HASHBITS			4
#define ATBM_STRING_HASHENTRIES			(1 << ATBM_STRING_HASHBITS)

#define ATBM_STRING_TABLE_INIT(_string,_string_func,_priv)	\
{										\
	.string = _string,					\
	.string_pos = NULL,					\
	.found = 0,							\
	.len = 0,							\
	.params = 0,						\
	.string_func = _string_func,		\
	.priv = _priv,						\
}

struct atbm_printk_mask_table_s {
	const char *mask_string;
	const char *mask_info;
	u32 	   mask_val;
	struct hlist_node string_hnode;
};
#define ATBM_PRINTK_MAX_STRING_LEN    32
#define ATBM_PRINTK_HASHBITS    4
#define ATBM_PRINTK_HASHENTRIES (1 << ATBM_PRINTK_HASHBITS)
#define LOG_ON		"ON"
#define LOG_OFF		"OFF"
#define LOG_ALL		"OPEN_ALL"
#define LOG_DEFAULT	"DEFAULT"
#define LOG_CLEAR	"CLEAR"
#define ATBM_BRA_L  '['
#define ATBM_BRA_R	']'
#define ATBM_ANG_L  '<'
#define ATBM_ANG_R	'>'

#define ATBM_PARAML ATBM_BRA_L
#define ATBM_PARAMR ATBM_BRA_R
#define ATBM_PARAML_S ATBM_ANG_L
#define ATBM_PARAMR_S ATBM_ANG_R

#define atbm_string_invalid(_header)	(((_header) != ATBM_SPACE)&&((_header) != ATBM_LINEF)&&((_header) != ATBM_ENTER)&&((_header) != ATBM_TAIL))
#define OPTION_TABLE_INIT(string,val) \
		{											\
			.opton_string = string, 				\
			.option_val   = val,					\
		}
#define LOG_TABLE_INIT(string,info,val)		\
		{											\
			.mask_string = string,					\
			.mask_info	   = info,					\
			.mask_val	= val,						\
		}
struct atbm_option_table_s {
	const char *opton_string;
	u32 	   option_val;
};

static const struct atbm_option_table_s option_table[]={
	OPTION_TABLE_INIT(LOG_ON,1),
	OPTION_TABLE_INIT(LOG_OFF,0),
};
/*
*
*atbm cmd fs control
*
*/
struct atbm_store_cmd_code {
	const char *label;
	const char *cmd_info;
	void __rcu *cmd_private;
	bool (*code_cmd)(struct atbm_store_cmd_code *cmd_store,const char *buf,int len);
	ssize_t (*show_cmd)(struct atbm_store_cmd_code *cmd_store,char *buf,bool show);
	bool echo_enable;
	bool echo_ready;
	struct atbm_module_show echo;
	struct hlist_node hnode;
	struct list_head  lhead;
};
#define ATBM_SCAN_HASHBITS    ATBM_COMMON_HASHBITS
#define ATBM_SCAN_HASHENTRIES (1 << ATBM_SCAN_HASHBITS)
struct atbm_conf_ascii{
	u8 *asciis;
	int len;
};
struct atbm_conf_ifname{
	u8 if_name[IFNAMSIZ];
	u8 size;
};

struct atbm_conf_channels{
	u8 *channels;
	u8 n_channels;
};

struct atbm_conf_ssids{
	struct cfg80211_ssid *ssids;
	u8 n_ssids;
};

struct atbm_conf_macs{
	struct ieee80211_internal_mac *mac;
	u8 n_macs;
};

struct atbm_conf_ies{
	u8 *ies;
	u8 ie_len;
	u8 atbm_ie;
};
struct atbm_conf_integer{
	int *integers;
	u8  n_integers;
};
struct atbm_conf_string
{
	char *strings;
	struct hlist_node hnode;
	bool set;
};
struct atbm_config_string_hash
{
	struct hlist_head hlist_head[ATBM_COMMON_HASHENTRIES];
	bool empty;
};
struct atbm_module_ap_conf{
	struct atbm_conf_ifname   ifname;
	struct atbm_conf_channels channel;
	struct atbm_conf_ssids    ssid;
	struct atbm_conf_macs     bssid;
	struct atbm_conf_ascii	  psk;
};
struct  atbm_module_halt_conf{
	struct atbm_conf_ifname   ifname;
};
struct atbm_echo_params{
	int num;
};
#define ATBM_CMD_MAX_STRING_LEN    32
#define ATBM_CMD_HASHBITS    4
#define ATBM_CMD_HASHENTRIES (1 << ATBM_CMD_HASHBITS)

#define ATBM_CODE_STR__ATTR_EXAMPLE_INFO			 "show example"
#define ATBM_CODE_STR__ATTR_HELP_INFO				 "show all cmd help info"
#define ATBM_CODE_STR__ATTR_ENABLE_ECHO_INFO		 "enable echo parmas:enable_echo num_echo=[1]"
#define ATBM_CODE_STR__ATTR_DISABLE_ECHO_INFO		 "disable echo:disable_echo"
#define ATBM_CODE_STR__ATTR_AP_CONF_INFO			"set ap configs:ap_config ifname=[xxx] channel=[x] ssid=[ap] bssid=[xx:xx:xx:xx:xx:xx] psk=[password]"


#define ATBM_CODE_STR__ATTR_EXAMPLE					"example"
#define ATBM_CODE_STR__ATTR_HELP    				"help"
#define ATBM_CODE_STR__ATTR_ENABLE_ECHO				"enable_echo"
#define ATBM_CODE_STR__ATTR_DISABLE_ECHO			"disable_echo"
#define ATBM_CODE_STR__ATTR_CLEAR_FREQ				"clear_freq"
#define ATBM_CODE_STR__ATTR_AP_CONF					"ap_config"



struct hlist_head atbm_cmd_hash_head[ATBM_CMD_HASHENTRIES];
struct list_head  atbm_cmd_echo_ready_list;
static char *backup_show = NULL;
static int  backup_show_size = 0;
static int    ready_list_num = 0;

#define ATBM_CMD_INIT(cmd_code,info,_store_cmd,_show_cmd)\
{											\
	.label = cmd_code,						\
	.cmd_info = info,						\
	.code_cmd = _store_cmd,					\
	.show_cmd = _show_cmd,					\
	.cmd_private = NULL,					\
}
static bool atbm_module_attr_echo_enable(struct atbm_store_cmd_code *cmd_store,const char *buf,int len);
static bool atbm_module_attr_echo_disable(struct atbm_store_cmd_code *cmd_store,const char *buf,int len);
static bool atbm_module_attr_example(struct atbm_store_cmd_code *cmd_store,const char *buf,int len);
static bool atbm_module_attr_help(struct atbm_store_cmd_code *cmd_store,const char *buf,int len);
static ssize_t atbm_module_attr_default_show(struct atbm_store_cmd_code *cmd_code,char *buf,bool show);
#ifndef CONFIG_ATBM_SDIO_ATCMD	
static bool atbm_module_attr_set_ap_config(struct atbm_store_cmd_code *cmd_store,const char *buf,int len);
#endif
struct atbm_store_cmd_code cmd_code_buff[]={
	ATBM_CMD_INIT(ATBM_CODE_STR__ATTR_HELP,ATBM_CODE_STR__ATTR_HELP_INFO,atbm_module_attr_help,atbm_module_attr_default_show),
	ATBM_CMD_INIT(ATBM_CODE_STR__ATTR_EXAMPLE,ATBM_CODE_STR__ATTR_EXAMPLE_INFO,atbm_module_attr_example,atbm_module_attr_default_show),
	ATBM_CMD_INIT(ATBM_CODE_STR__ATTR_DISABLE_ECHO,ATBM_CODE_STR__ATTR_DISABLE_ECHO_INFO,atbm_module_attr_echo_disable,atbm_module_attr_default_show),
	ATBM_CMD_INIT(ATBM_CODE_STR__ATTR_ENABLE_ECHO,ATBM_CODE_STR__ATTR_ENABLE_ECHO_INFO,atbm_module_attr_echo_enable,atbm_module_attr_default_show),
#ifndef CONFIG_ATBM_SDIO_ATCMD	
	ATBM_CMD_INIT(ATBM_CODE_STR__ATTR_AP_CONF,ATBM_CODE_STR__ATTR_AP_CONF_INFO,atbm_module_attr_set_ap_config,atbm_module_attr_default_show),
#endif
};

static unsigned int atbm_hash_string_len(const char *pos,unsigned int pos_len)
{
	unsigned int i;
	unsigned int j;
	
	if(pos == NULL){
		return 0;
	}
	for(i = 0;i<pos_len;i++){	
		if(pos[i] != ATBM_SPACE)
			continue;
		for(j = i;j<pos_len;j++){
			if(pos[j] != ATBM_SPACE)
				return 0;
		}
		break;
	}

	return i;
}
static int atbm_cmd_string_split(const char *pos,int len,const char **pos_l,const char **pos_r)
{
	int i = 0;
	int j = 0;
	const char *l = NULL;
	const char *r = NULL;
	char next_pos;
	
	if(len == 0){
		return -1;
	}
	atbm_printk_debug("%s:%d %s\n",__func__,len,pos);
	for(i = 0;i<len;i++){
		
		if((pos[i] == ATBM_PARAMR)||(pos[i] == ATBM_PARAMR_S)){
			atbm_printk_debug("%s:left pos err\n",__func__);
			return -1;
		}
		
		if((pos[i] != ATBM_PARAML)&&(pos[i] != ATBM_PARAML_S)){
			continue;
		}
		l = &pos[i];
		next_pos = pos[i] == ATBM_PARAML ? ATBM_PARAMR:ATBM_PARAMR_S;		
		for(j = i+1;j<len;j++){

			if((pos[j] == ATBM_PARAML)||(pos[j] == ATBM_PARAML_S)){
				atbm_printk_debug("%s:right pos err\n",__func__);
				return -1;
			}

			if(pos[j] != next_pos){
				continue;
			}
			r = &pos[j];
			break;
		}
		break;
	}

	if((l == NULL) && (r == NULL)){
		return 0;
	}else if((l == NULL) || (r == NULL)){
		return -1;
	}
	
	*pos_l = l;
	*pos_r = r;

	return *l == ATBM_PARAML ? 1: 2;
}
static bool atbm_string_parase_echo(const char *pos_l,const char *pos_r,void *priv)
{
	#define ECHO_ENABLE 	"enable"
	#define ECHO_DISABLE 	"disable"
	struct atbm_store_cmd_code *cmd_store = (struct atbm_store_cmd_code *)priv;
	
	if(pos_r <= pos_l){
		atbm_printk_debug("%s:len err\n",__func__);
		return false;
	}

	if((strlen(ECHO_ENABLE) == pos_r-pos_l)&&(!memcmp(ECHO_ENABLE,pos_l, pos_r-pos_l))){
		atbm_printk_debug("%s:echo enanle\n",__func__);
		cmd_store->echo_enable = true;
	}else if((strlen(ECHO_DISABLE) == pos_r-pos_l)&&(!memcmp(ECHO_DISABLE,pos_l, pos_r-pos_l))){
		atbm_printk_debug("%s:echo disable\n",__func__);
		cmd_store->echo_enable = false;
	}else {
		atbm_printk_debug("%s:unkown echo %s\n",__func__,pos_l);
		return false;
	}

	return true;
}
static bool atbm_string_parase(struct atbm_store_cmd_code *cmd_store,struct atbm_sting_s *string_table,unsigned int table_size,const char *string,unsigned int string_len)
{
	#define CMD_ECHO_STR "echo="
	unsigned int index = 0;
	const char *pos = string;
	const char *pos_end = string+string_len;
	const char *nospace_pos;
	const char *target_pos;
	struct hlist_head *hhead;
	struct hlist_node *node;
	struct hlist_head atbm_string_hash_head[ATBM_STRING_HASHENTRIES];
	struct atbm_sting_s *string_node;
	struct atbm_sting_s echo_str;
	unsigned int hash_index = 0;
	
	if(table_size < 0){
		return false;
	}

	memset(&echo_str,0,sizeof(struct atbm_sting_s));

	echo_str.string = CMD_ECHO_STR;
	echo_str.priv = cmd_store;
	echo_str.string_func = atbm_string_parase_echo;
	atbm_common_hash_list_init(atbm_string_hash_head,ATBM_STRING_HASHENTRIES);
	/*
	*first add echo string
	*/
	hash_index = atbm_hash_index(echo_str.string,strlen(echo_str.string),ATBM_STRING_HASHBITS);
	hlist_add_head(&echo_str.hnode,&atbm_string_hash_head[hash_index]);

	/*
	*second add requset string
	*/
	for(index = 0;index<table_size;index++){
		unsigned int hash_index = atbm_hash_index(string_table[index].string,
								  strlen(string_table[index].string),ATBM_STRING_HASHBITS);
		BUG_ON(strlen(string_table[index].string) > ATBM_STRING_MAX_LEN);
		
		hhead = &atbm_string_hash_head[hash_index];
		
		hlist_for_each(node,hhead){
			string_node = hlist_entry(node,struct atbm_sting_s,hnode);
			if ((!strncmp(string_node->string, string_table[index].string, strlen(string_table[index].string)))&&
				(strlen(string_table[index].string) == strlen(string_node->string))){
				atbm_printk_debug("%s:string_node(%s) already in list\n",__func__,string_node->string);
				return false;
			}
		}
		hlist_add_head(&string_table[index].hnode,&atbm_string_hash_head[hash_index]);
		atbm_printk_debug("%s:[%s]->[%d]\n",__func__,string_table[index].string,hash_index);
	}
	
	atbm_printk_debug("%s:len:%d tring:%s\n",__func__,string_len,pos);
	while(pos<pos_end){
next_str:
		/*
		*pos <= pos_end will return null,and break the loop
		*/
		nospace_pos = atbm_skip_space(pos,pos_end-pos);

		if(nospace_pos == NULL){
			atbm_printk_debug("%s nospace_pos == NULL\n",__func__);
			return pos == string ? false: true;
		}
		
		pos = nospace_pos;
		atbm_printk_debug("%s:len:%zu nospace_pos:%s\n",__func__,pos_end-pos,nospace_pos);
		if(pos[0] == ATBM_TAIL)
			return pos == string?false: true;
		else if((pos[0] == ATBM_LINEF)||(pos[0] == ATBM_ENTER))
			return pos == string?false: true;
		/*
		*find the postion of cmd end =
		*/
		target_pos = memchr(pos, ATBM_EQUAL, pos_end-pos); 
		if(target_pos == NULL){
			atbm_printk_always("%s:can not cmd =\n",__func__);
			return false;
		}
		atbm_printk_debug("%s:len:%zu,str %s\n",__func__,target_pos-pos+1,pos);
		hhead = atbm_hash_list(pos,target_pos-pos+1,atbm_string_hash_head,ATBM_STRING_HASHBITS);

		if(hhead == NULL){
			atbm_printk_always("%s:hhead = NULL\n",__func__);
			return false;
		}
		hlist_for_each(node,hhead){
			
			string_node = hlist_entry(node,struct atbm_sting_s,hnode);
			atbm_printk_debug("%s:string_node(%s)(%zu),target:%zu:%s\n",__func__,
				string_node->string,strlen(string_node->string),target_pos-pos+1,pos);
			if ((!strncmp(pos, string_node->string,target_pos-pos+1))&&
				(strlen(string_node->string) == target_pos-pos+1)){
				
				const char *tmp_pos = NULL;
				if(string_node->found == true){
					atbm_printk_debug("%s:fund same string(%s)\n",__func__,string_node->string);
					return false;
				}
				tmp_pos = atbm_skip_space(target_pos+1,string_len - (target_pos+1-string));

				if(tmp_pos == NULL){
					atbm_printk_always("%s:tmp_pos == NULL\n",__func__);
					return false;
				}
				string_node->found = true;
				string_node->string_pos = tmp_pos;
				string_node->len = pos_end-tmp_pos;

				if((tmp_pos[0] != ATBM_PARAML)&&(tmp_pos[0] != ATBM_PARAML_S)){
					/*
					*find the postion of cmd end,use space between tow string
					*some cmd not need space ,so find enter or end of line
					*/
					pos = memchr(tmp_pos, ATBM_SPACE, pos_end-tmp_pos); 
					if(pos == NULL){
						pos  =  memchr(tmp_pos, ATBM_ENTER, pos_end-tmp_pos);
						if(pos == NULL)
							 pos = memchr(tmp_pos, ATBM_LINEF, pos_end-tmp_pos);
					}
					if(string_node->string_func){
						if(pos == NULL) pos=pos_end;
						if(string_node->string_func(tmp_pos,pos,string_node->priv) == false){
							atbm_printk_err("%s:[%s] err tmp_pos (%p) pos (%p) %s\n",__func__,string_node->string,tmp_pos,pos,pos);
							return false;
						}
					}
					string_node->params = 1;
				}else {
					const char *pos_l;
					const char *pos_r;
					int res = 0;
					
					pos_r = tmp_pos;
					pos_l = tmp_pos;
					while(pos_r<pos_end){
						
						res = atbm_cmd_string_split(pos_l,pos_end-pos_l,&pos_l,&pos_r);

						if(res<=0){
							atbm_printk_err("%s not find l and r %s\n",__func__,pos);
							return false;
						}
						if((pos_r-pos_l) == 1){
							atbm_printk_err("%s param is null %s\n",__func__,pos);
							return false;
						}
						string_node->params++;
						if(string_node->string_func){
							if(string_node->string_func(pos_l+1,pos_r,string_node->priv) == false){
								atbm_printk_err("%s:[%s] err pos_l (%p) pos_r (%p) %s\n",__func__,string_node->string,pos_l+1,pos_r,pos_l+1);
								return false;
							}
						}
						pos_r++;
						pos_l = pos_r;

						if((pos_l[0]!=ATBM_PARAML)&&(pos_l[0]!=ATBM_PARAML_S)){
							if(atbm_string_invalid(pos_l[0])){
								atbm_printk_err("%s param format err %s\n",__func__,pos);
								return false;
							}
							break;
						}

					}

					pos = pos_r;
				}
				

				if(pos == NULL)
					pos = pos_end;
				else
					string_node->len = pos-tmp_pos;
				atbm_printk_debug("[%s]:len %d,pos %s\n",string_node->string,string_node->len,string_node->string_pos);
				goto next_str;
			}
		}

		atbm_printk_always("%s:string is err %s\n",__func__,pos);

		return false;
	}

	return true;
}
static void *atbm_store_cmd_init_cmd_private(struct atbm_store_cmd_code *cmd_store,int len,gfp_t gfp)
{
	void *cmd_private;
	
	cmd_private = rcu_dereference(cmd_store->cmd_private);
	if(cmd_private){
		if(cmd_store->show_cmd)
			cmd_store->show_cmd(cmd_store,NULL,false);
		rcu_assign_pointer(cmd_store->cmd_private,NULL);
		synchronize_rcu();
		
		atbm_kfree(cmd_private);
	}

	cmd_private = atbm_kzalloc(len,gfp);

	return cmd_private;
}
static struct hlist_head *atbm_cmd_hash_list(const char *string,unsigned int len)
{
	return atbm_hash_list(string,len,atbm_cmd_hash_head,ATBM_CMD_HASHBITS);
}


static struct atbm_store_cmd_code *atbm_store_cmd_find_cmd(const char *pos,unsigned int pos_len)
{
	unsigned char string_len = 0;
    struct hlist_head *hlist = NULL;
	struct atbm_store_cmd_code *cmd_code;
	struct hlist_node *node;

	if(ATBM_CMD_MAX_STRING_LEN<pos_len){
		atbm_printk_always("%s:[%s] pos_len is too long\n",__func__,pos);
		return NULL;
	}
	
	string_len = atbm_hash_string_len(pos,pos_len);
	
	if(string_len == 0){
		atbm_printk_always("%s:[%s] cmd len err\n",__func__,pos);
		return NULL;
	}

	hlist = atbm_cmd_hash_list(pos,string_len);

	hlist_for_each(node,hlist){
		cmd_code = hlist_entry(node,struct atbm_store_cmd_code,hnode);
		if ((!strncmp(pos, cmd_code->label, string_len))&&
			(string_len == strlen(cmd_code->label))){
			return cmd_code;
		}
	}
	atbm_printk_always("%s:[%s] can not fund\n",__func__,pos);
	return NULL;
}
static bool atbm_store_cmd_init_show(struct atbm_module_show *show)
{
	char *show_buff;
	
	if((show_buff = rcu_dereference(show->show_buff)) == NULL){
		show_buff = atbm_kzalloc(ATBM_SHOW_MSG_MAX_SIZE,GFP_KERNEL);
	}
	
	if(show_buff == NULL){
		return false;
	}
	atbm_show_deinit(show);
	atbm_show_init(show,show_buff);

	return true;
}

static void atbm_store_cmd_deinit_show(struct atbm_module_show *show)
{
	char *show_buff = rcu_dereference(show->show_buff);
	
	atbm_show_deinit(show);
	if(show_buff){
		synchronize_rcu();
		atbm_kfree(show_buff);
		atbm_printk_debug("%s:free(%p)\n",__func__,show_buff);
	}
}
static ssize_t atbm_module_attr_default_show(struct atbm_store_cmd_code *cmd_code,char *buf,bool show)
{
	struct atbm_module_show echo_show;
	atbm_show_init(&echo_show,buf);
	if(show == true)
		atbm_module_show_put(&echo_show,cmd_code->echo.show_buff);
	return echo_show.show_count;
}
static bool atbm_module_attr_example(struct atbm_store_cmd_code *cmd_store,const char *buf,int len)
{
	atbm_module_show_put(&cmd_store->echo,"atbm module cmd example\n");
	atbm_module_show_put(&cmd_store->echo,"\n");
	atbm_printk_always( "%s\n",__func__);
	return true;
}
static bool atbm_module_attr_help(struct atbm_store_cmd_code *cmd_store,const char *buf,int len)
{
	unsigned int index = 0;
	struct atbm_module_show *show = &cmd_store->echo;

	atbm_module_show_put(show,LIGHT"Atbm Cmd Help-->:"NORMAL ENTER);
	for(index = 0;index<ARRAY_SIZE(cmd_code_buff);index++){
		atbm_module_show_put(show,LIGHT"[%s]"NORMAL":%s\n",cmd_code_buff[index].label,cmd_code_buff[index].cmd_info);
	}
	atbm_printk_always( "%s\n",__func__);
	return true;
}

#ifndef CONFIG_ATBM_SDIO_ATCMD
static struct atbm_vif * atbm_module_get_sdata_by_name(const char *name)
{
	struct net_device *net_dev = NULL;
	struct atbm_vif *vif;
	
	ASSERT_RTNL();
	net_dev = __dev_get_by_name(&init_net,name);

	if(net_dev == NULL){
		return NULL;
	}
	
	vif = atbm_dev_to_vif(net_dev);

	if (vif->ndev == net_dev)
		return vif;

	atbm_printk_err("%s: can not get(%s) dev\n",__func__,name);
	return NULL;
}
static bool atbm_module_config_ascii(const char *posl,const char *posr,void *priv)
{
	struct atbm_conf_ascii  *asciis = (struct atbm_conf_ascii  *)priv;
	u8 len = posr - posl;
	
	atbm_printk_debug("%s:posl(%p),posr(%p) %s\n",__func__,posl,posr,posl);

	if(asciis == NULL){
		atbm_printk_err("%s:priv NULL(%p),\n",__func__,priv);
		return false;
	}

	if(asciis->len != 0){
		atbm_printk_err("%s:asciis has been set\n",__func__);
		return false;
	}

	asciis->asciis = atbm_kzalloc(len, GFP_KERNEL);

	if(asciis->asciis == NULL){
		return false;
	}

	memcpy(asciis->asciis,posl,len);
	asciis->len = len;

	return true;
}
static bool atbm_module_config_ifname(const char *posl,const char *posr,void *priv)
{
	struct atbm_conf_ifname *conf_ifname = (struct atbm_conf_ifname *)priv;
	u8 len = posr - posl;
	
	atbm_printk_debug("%s:posl(%p),posr(%p) %s\n",__func__,posl,posr,posl);
	
	if(conf_ifname == NULL){
		atbm_printk_err("%s:priv NULL(%p),\n",__func__,priv);
		return false;
	}

	if(conf_ifname->size != 0){
		atbm_printk_err("%s:if name has been set\n",__func__);
		return false;
	}

	if(len > IFNAMSIZ){
		atbm_printk_err("%s:if name size too long\n",__func__);
		return false;
	}

	memcpy(conf_ifname->if_name,posl,len);
	conf_ifname->size = len;
	
	return true;
}

static bool atbm_module_config_channels(const char *posl,const char *posr,void *priv)
{
	struct atbm_conf_channels *channels = (struct atbm_conf_channels *)priv;

	u8 *new_channels = channels->channels;
	u8 *pos_channel;
	int channel_index = 0;

	atbm_printk_debug("%s:posl(%p),posr(%p) %s\n",__func__,posl,posr,posl);
	if(priv == NULL){
		atbm_printk_err("%s:priv NULL(%p),\n",__func__,priv);
		return false;
	}
	if(channels->n_channels>=ATBM_MAX_SCAN_CHANNEL){
		atbm_printk_err("%s:channles too mach(%d)\n",__func__,channels->n_channels);
		return false;
	}
	
	if((posr - posl <= 0) || (posr-posl>2)){
		atbm_printk_err("%s:channles len err\n",__func__);
		return false;
	}
	
	if(new_channels && channels->n_channels){
		
		new_channels = atbm_krealloc(channels->channels,channels->n_channels+1,GFP_KERNEL);
		if(new_channels == NULL){
			atbm_printk_err("%s:channles alloc err\n",__func__);
			return false;
		}
		
	}else {
		new_channels = atbm_kzalloc(1,GFP_KERNEL);

		if(new_channels == NULL){
			atbm_printk_err("%s:channles kzalloc err\n",__func__);
			return false;
		}
	}
	channels->channels = new_channels;	
	pos_channel = new_channels+channels->n_channels;

	if(atbm_accsii_to_int(posl,posr-posl,&channel_index) == false){		
		atbm_printk_err("%s:channel_index (%d) err\n",__func__,channel_index);
		return false;
	}

	if(channel_index>50){
		atbm_printk_err("%s:channel_index (%d) err\n",__func__,channel_index);
		return false;
	}
	
	channels->n_channels++;
	*pos_channel = (u8)channel_index;
	return true;
}
static bool atbm_module_config_ssids(const char *posl,const char *posr,void *priv)
{
	struct atbm_conf_ssids *ssids = (struct atbm_conf_ssids *)priv;
	struct cfg80211_ssid *new_ssid = ssids->ssids;
	struct cfg80211_ssid *pos_ssid = NULL;
	
	atbm_printk_debug("%s:posl(%p),posr(%p) %s\n",__func__,posl,posr,posl);
	if(priv == NULL){
		atbm_printk_err("%s:priv NULL(%p),\n",__func__,priv);
		return false;
	}
	if(ssids->n_ssids>=ATBM_MAX_SCAN_SSID){
		atbm_printk_err("%s:ssid to mach(%d)\n",__func__,ssids->n_ssids);
		return false;
	}
	if((posr - posl <= 0) || (posr-posl>IEEE80211_MAX_SSID_LEN)){
		atbm_printk_err("%s:channles len err\n",__func__);
		return false;
	}

	if(new_ssid&&ssids->n_ssids){
		new_ssid = atbm_krealloc(ssids->ssids,sizeof(struct cfg80211_ssid)*(ssids->n_ssids+1),GFP_KERNEL);
		if(new_ssid == NULL){
			atbm_printk_err("%s:channles realloc err\n",__func__);
			return false;
		}
	}else {
		new_ssid = atbm_kzalloc(sizeof(struct cfg80211_ssid),GFP_KERNEL);

		if(new_ssid == NULL){
			atbm_printk_err("%s:channles kzalloc err\n",__func__);
			return false;
		}
	}
	ssids->ssids  = new_ssid;
	pos_ssid = new_ssid + ssids->n_ssids;

	memcpy(pos_ssid->ssid,posl,posr-posl);
	pos_ssid->ssid_len = posr-posl;
	ssids->n_ssids++;
	
	atbm_printk_always("%s: ssid (%s) ssid_len(%d) n_ssids(%d)\n",__func__,pos_ssid->ssid,pos_ssid->ssid_len,ssids->n_ssids);
	return true;
}

static bool atbm_module_config_macs(const char *posl,const char *posr,void *priv)
{
	struct atbm_conf_macs *macs = (struct atbm_conf_macs *)priv;

	struct ieee80211_internal_mac  *new_mac = macs->mac;
	struct ieee80211_internal_mac  *pos_mac = NULL;
	int i;
	u8 hex;
	u8 mac_begin = 0;
	u8 mac_len = 0;
	
	atbm_printk_debug("%s:posl(%p),posr(%p) %s\n",__func__,posl,posr,posl);
	if(priv == NULL){
		atbm_printk_err("%s:priv NULL(%p),\n",__func__,priv);
		return false;
	}
	if(posr-posl != 17){
		atbm_printk_err("%s:mac len err(%zu),\n",__func__,posr-posl);
		return false;
	}
	if(macs->n_macs>=ATBM_MAX_SCAN_MAC_FILTER){
		atbm_printk_err("%s:mac to mach(%d),\n",__func__,macs->n_macs);
		return false;
	}
	if(macs->n_macs&&new_mac){
		new_mac = atbm_krealloc(macs->mac,sizeof(struct ieee80211_internal_mac)*(macs->n_macs+1),GFP_KERNEL);

		if(new_mac == NULL){
			atbm_printk_err("%s:mac realloc err\n",__func__);
			return false;
		}
	}else {
		new_mac = atbm_kzalloc(sizeof(struct ieee80211_internal_mac),GFP_KERNEL);

		if(new_mac == NULL){
			atbm_printk_err("%s:mac kzalloc err\n",__func__);
			return false;
		}
	}

	macs->mac = new_mac;
	pos_mac = macs->mac+macs->n_macs;
	
	for(i=0;i<posr-posl;i++){
		
		if(posl[i] == ':'){
			mac_len++;
			mac_begin = 0;
			continue;
		}

		if(mac_len>=6){
			atbm_printk_err("%s:mac len,%d\n",__func__,mac_len);
			return false;
		}

		if(mac_begin>1){
			atbm_printk_err("%s:mac err,mac_begin %d\n",__func__,mac_begin);
			return false;
		}
		if (atbm_accsii_to_hex(posl[i],&hex) == false){
			atbm_printk_err("%s:scan_macs  %d\n",__func__,posl[i]);
			return false;
		}
		pos_mac->mac[mac_len] *= 16;

		pos_mac->mac[mac_len] += hex;

		mac_begin++;
	}

	if(mac_len != 5){
		atbm_printk_err("%s:mac len err  %d\n",__func__,mac_len);
		return false;
	}
	macs->n_macs++;
	atbm_printk_always("%s:mac[%pM]\n",__func__,pos_mac->mac);
	return true;
}
#endif

static bool atbm_module_echo_enable_num_echo(const char *posl,const char *posr,void *priv)
{
	struct atbm_echo_params *echo_params = (struct atbm_echo_params *)priv;
	atbm_printk_debug("%s:posl(%p),posr(%p) %s\n",__func__,posl,posr,posl);
	
	if(priv == NULL){
		atbm_printk_err("%s:priv NULL(%p),\n",__func__,priv);
		return false;
	}

	if(echo_params->num != -1){
		atbm_printk_err("%s:echo_params->num err(%d),\n",__func__,echo_params->num);
		return false;
	}

	if((posr - posl <= 0) || (posr-posl>5)){
		atbm_printk_err("%s: params too long\n",__func__);
		return false;
	}

	if(atbm_accsii_to_int(posl,posr-posl,&echo_params->num) == false){		
		atbm_printk_err("%s:echo_params->num (%d) err\n",__func__,echo_params->num);
		echo_params->num = -1;
		return false;
	}

	if((echo_params->num<0)&&(echo_params->num != -1)){
		atbm_printk_err("%s:echo_params->num (%d) is negtive\n",__func__,echo_params->num);
		echo_params->num = -1;
		return false;
	}

	return true;
}
static bool atbm_module_attr_echo_enable(struct atbm_store_cmd_code *cmd_store,const char *buf,int len)
{
	bool res = true;
	const char* info = buf;
	void *cmd_private = NULL;
	struct atbm_echo_params *echo_params;

	enable_echo = true;
	cmd_store->echo_enable = true;

	cmd_private = atbm_store_cmd_init_cmd_private(cmd_store,sizeof(struct atbm_echo_params),GFP_KERNEL);

	if(cmd_private == NULL){
		res = false;
		goto exit;
	}
	echo_params = (struct atbm_echo_params *)cmd_private;
	echo_params->num = -1;
	rcu_assign_pointer(cmd_store->cmd_private,cmd_private);

	
	info = atbm_skip_space(buf,len);

	/*
	*parmas start end and channels
	*/
	if(info){
		#define NUM_ECHO  "num_echo="
		struct atbm_sting_s req_string[]={
			ATBM_STRING_TABLE_INIT(NUM_ECHO,atbm_module_echo_enable_num_echo,cmd_store->cmd_private),
		};
		if(atbm_string_parase(cmd_store,req_string,ARRAY_SIZE(req_string),info,len-(info-buf))==false){
			atbm_printk_always("%s:channel_select %s err\n",__func__,info);
			res = false;
			goto exit;
		}
	} 

	num_echo = echo_params->num;
	res = true;
	atbm_printk_err("%s:num_echo(%d)\n",__func__,num_echo);
exit:
	if(cmd_private){
		atbm_kfree(cmd_private);
		rcu_assign_pointer(cmd_store->cmd_private,NULL);
	}
	return res;
}

static bool atbm_module_attr_echo_disable(struct atbm_store_cmd_code *cmd_store,const char *buf,int len)
{
	bool res = true;
	
	if(buf != NULL || len != 0){
		atbm_printk_err("%s:len(%d)(%p) err\n",__func__,len,buf);
		res = false;
		goto exit;
	}

	enable_echo = false;
	cmd_store->echo_enable = true;
exit:
	return res;
}
/*
*set ap configs:ap_config ifname=[xxx] channel=[x] ssid=[ap] bssid=[xx:xx:xx:xx:xx:xx]
*/
#ifndef CONFIG_ATBM_SDIO_ATCMD
static bool atbm_module_attr_set_ap_config(struct atbm_store_cmd_code *cmd_store,const char *buf,int len)
{
	bool res = true;
	struct atbm_module_ap_conf ap_config;
	const char* select_info = buf;
	struct atbm_vif *vif = NULL;
	struct atbm_ap_config *conf;
	rtnl_lock();
	
	select_info = atbm_skip_space(buf,len);
	memset(&ap_config,0,sizeof(struct atbm_module_ap_conf));
	
	if(select_info){
		#define CONF_IFNAME   "ifname="
		#define CONF_CHANNEL  "channel="
		#define CONF_SSID     "ssid="
		#define CONF_BSSID    "bssid="
		#define CONF_PSK	  "psk="	
		
		struct atbm_sting_s req_string[]={
			ATBM_STRING_TABLE_INIT(CONF_IFNAME,atbm_module_config_ifname,&ap_config.ifname),
			ATBM_STRING_TABLE_INIT(CONF_CHANNEL,atbm_module_config_channels,&ap_config.channel),
			ATBM_STRING_TABLE_INIT(CONF_SSID,atbm_module_config_ssids,&ap_config.ssid),
			ATBM_STRING_TABLE_INIT(CONF_BSSID,atbm_module_config_macs,&ap_config.bssid),
			ATBM_STRING_TABLE_INIT(CONF_PSK,atbm_module_config_ascii,&ap_config.psk),
		};
		
		if(atbm_string_parase(cmd_store,req_string,ARRAY_SIZE(req_string),select_info,len-(select_info-buf))==false){
			atbm_printk_always("%s:ap config %s err\n",__func__,select_info);
			res = false;
			goto exit;
		}
	}else {
		res = false;
		goto exit;
	}

	if(ap_config.ifname.size == 0){
		atbm_printk_err("%s:ifname is null\n",__func__);
		res = false;
		goto exit;
	}

	vif = atbm_module_get_sdata_by_name(ap_config.ifname.if_name);

	if(vif == NULL){
		atbm_printk_err("%s:[%s] not found\n",__func__,ap_config.ifname.if_name);
		res = false;
		goto exit;
	}

	if((ap_config.channel.n_channels >1) ||
	   (ap_config.ssid.n_ssids >1) ||
	   (ap_config.bssid.n_macs >1)){
		atbm_printk_err("%s:config err\n",__func__);
		res = false;
		goto exit;
	}

	if((ap_config.channel.n_channels == 0)&&
	   (ap_config.ssid.n_ssids == 0) &&
	   (ap_config.bssid.n_macs == 0)){
	    atbm_printk_err("%s:config clear\n",__func__);
		goto exit;
	}
	conf = &vif->ap_info;
	if(ap_config.bssid.n_macs)
		memcpy(conf->bssid,ap_config.bssid.mac,6);
	if(ap_config.channel.n_channels)
		conf->channel = ap_config.channel.channels[0];
	if(ap_config.ssid.n_ssids){
		conf->ssid_len = ap_config.ssid.ssids[0].ssid_len;
		memcpy(conf->ssid,ap_config.ssid.ssids[0].ssid,conf->ssid_len);
	}
	if(ap_config.psk.len){
		conf->password_len = ap_config.psk.len > 63?63:ap_config.psk.len;
		memcpy(conf->password,ap_config.psk.asciis,conf->password_len);
		conf->enc = true;
	}else {
		conf->enc = false;
	}
	atbm_printk_err("ap config:bssid[%pM],ssid[%s],channel[%d]\n",conf->bssid,conf->ssid,conf->channel);
exit:
	rtnl_unlock();
	#undef CONF_IFNAME   
	#undef CONF_CHANNEL  
	#undef CONF_SSID     
	#undef CONF_BSSID   
	if(ap_config.bssid.mac)
		atbm_kfree(ap_config.bssid.mac);
	if(ap_config.channel.channels)
		atbm_kfree(ap_config.channel.channels);
	if(ap_config.ssid.ssids)
		atbm_kfree(ap_config.ssid.ssids);
	if(ap_config.psk.asciis)
		atbm_kfree(ap_config.psk.asciis);
	rcu_assign_pointer(cmd_store->cmd_private,NULL);
	return res;
}
#endif

static bool atbm_store_cmd_is_ready(struct atbm_store_cmd_code *cmd_store)
{
	struct atbm_store_cmd_code *ready_cmd;
	
	list_for_each_entry(ready_cmd, &atbm_cmd_echo_ready_list, lhead){
		if((ready_cmd->label == cmd_store->label)&&
		   (ready_cmd->code_cmd == cmd_store->code_cmd))
		   return true;
	}

	return false;
}
static void atbm_store_cmd_echo_done(struct atbm_store_cmd_code *cmd_store)
{
	char *cmd_private;
	if(cmd_store->echo_ready == false){
		atbm_printk_always( "%s not in ready list\n",cmd_store->label);
		WARN_ON(atbm_store_cmd_is_ready(cmd_store) == true);
	}else {
		list_del(&cmd_store->lhead);
		ready_list_num--;
		WARN_ON(ready_list_num<0);
	}
	cmd_private = rcu_dereference(cmd_store->cmd_private);
	rcu_assign_pointer(cmd_store->cmd_private,NULL);
	if(cmd_private){
		synchronize_rcu();
		atbm_kfree(cmd_private);
		atbm_printk_always("%s:free cmd_private(%p)\n",__func__,cmd_private);
	}
	cmd_store->cmd_private = NULL;
	cmd_store->echo_ready = false;
}
static void atbm_store_cmd_echo_ready(struct atbm_store_cmd_code *cmd_store)
{
	if(cmd_store->echo_ready == true){		
		atbm_printk_always( "%s already in ready list\n",cmd_store->label);
		WARN_ON(atbm_store_cmd_is_ready(cmd_store) == false);
		return;
	}
	
	cmd_store->echo_ready = true;
	
	if((num_echo == -1) || (num_echo>ready_list_num)){
		
	}else if((!list_empty(&atbm_cmd_echo_ready_list))){
		struct atbm_store_cmd_code *cmd_code =
			list_first_entry(&atbm_cmd_echo_ready_list, struct atbm_store_cmd_code,
			lhead);
		if(cmd_code->show_cmd)
			cmd_code->show_cmd(cmd_code,NULL,false);
		atbm_store_cmd_echo_done(cmd_code);
		atbm_store_cmd_deinit_show(&cmd_code->echo);		
	}else if(num_echo != 0){
		WARN_ON(1);
	}
	ready_list_num ++;
	list_add_tail(&cmd_store->lhead,&atbm_cmd_echo_ready_list);
}

static ssize_t atbm_module_decode_common_store(const char *buf, size_t n)
{
	const char *p;
	const char *code_end = NULL;
	int code_len = 0;
	int left_len = 0;
	size_t len = n;
	struct atbm_store_cmd_code *store_code;

	p = atbm_skip_space(buf,n);

	if(p == NULL){
		atbm_printk_always("%s:all space %s\n",__func__,buf);
		return -EINVAL;
	}
	len -= p-buf;
	/*
	*find the postion of cmd end,use space between tow string
	*some cmd not need space ,so find enter or end of line
	*/
	code_end = memchr(buf, ATBM_SPACE, len); 
	if(code_end == NULL){
		code_end  =  memchr(buf, ATBM_ENTER, len);
		if(code_end == NULL)
			 code_end = memchr(buf, ATBM_LINEF, len);
	}
	if(code_end == NULL){
		atbm_printk_always("%s:can not fine aline\n",__func__);
	}
	code_len = code_end ? code_end - p : len;	
	if(code_len<=0){
		atbm_printk_always("%s code_len err\n",__func__);
		return -EINVAL;
	}
	left_len = len - code_len;

	if(left_len<0){
		atbm_printk_always("%s left_len err\n",__func__);
		return -EINVAL;
	}
	store_code = atbm_store_cmd_find_cmd(p,code_len);

	if(store_code == NULL){
		atbm_printk_always("%s:can not find cmd\n",__func__);
		return -EINVAL;
	}
	BUG_ON(store_code->code_cmd == NULL);
	
	p = atbm_skip_space(code_end,left_len);
	if(p == NULL){
		left_len = 0;
	}else {
		left_len -= p-code_end;	
	}
	if(left_len<0){
		atbm_printk_always("%s left_len err,params err\n",__func__);
		return -EINVAL;
	}
	if(atbm_store_cmd_init_show(&store_code->echo) == false){
		atbm_printk_always("%s show buff init err\n",__func__);
		return -EINVAL;
	}
	/*
	*set default enable_echo
	*/
	store_code->echo_enable = enable_echo;
	
	if(store_code->code_cmd(store_code,p,left_len) == true){
		if(store_code->echo_enable == true){
			atbm_module_show_put(&store_code->echo,"%s[%s]\n",store_code->label,"OK");
			atbm_store_cmd_echo_ready(store_code);
		}else{
			if(store_code->show_cmd)
				store_code->show_cmd(store_code,NULL,false);
			atbm_store_cmd_echo_done(store_code);
			atbm_store_cmd_deinit_show(&store_code->echo);
		}
	}else {
		if(store_code->echo_enable == true){
			atbm_module_show_put(&store_code->echo,"%s[%s]\n",store_code->label,"ERR");
		}
		atbm_store_cmd_echo_done(store_code);
		atbm_store_cmd_deinit_show(&store_code->echo);

		return -EINVAL;
	}
	return n;
}
static ssize_t atbm_module_cmd_store(struct kobject *kobj, struct kobj_attribute *attr,
			   const char *buf, size_t n)
{
	ssize_t mg_size = 0;
	atbm_modulefs_lock();
	atbm_module_muxlock();
	mg_size = atbm_module_decode_common_store(buf,n);
	atbm_module_muxunlock();
	atbm_modulefs_unlock();
	return mg_size;
}
static ssize_t atbm_module_cmd_show(struct kobject *kobj,
			     struct kobj_attribute *attr, char *buf)
{
	ssize_t len = 0;
	u8* show_buff = NULL;
	ssize_t show_len = 0;
	atbm_modulefs_lock();
	atbm_module_muxlock();	
	show_buff = atbm_kzalloc(ATBM_SHOW_MSG_MAX_SIZE, GFP_KERNEL);
	while (!list_empty(&atbm_cmd_echo_ready_list)) {
		struct atbm_store_cmd_code *cmd_code =
			list_first_entry(&atbm_cmd_echo_ready_list, struct atbm_store_cmd_code,
			lhead);

		if(cmd_code->show_cmd)
			show_len = cmd_code->show_cmd(cmd_code,show_buff,show_buff ? true:false);
		if(show_buff){			
			if((show_len)&&(len+show_len<ATBM_SHOW_MSG_MAX_SIZE)){
				memcpy(buf+len,show_buff,show_len);
				len += show_len;
			}
		}
		show_len = 0;
		atbm_store_cmd_echo_done(cmd_code);
		atbm_store_cmd_deinit_show(&cmd_code->echo);
	}
	if(len&&show_buff){
		if(WARN_ON(len>ATBM_SHOW_MSG_MAX_SIZE))
			len = ATBM_SHOW_MSG_MAX_SIZE;
		memset(backup_show,0,ATBM_SHOW_MSG_MAX_SIZE);
		memcpy(backup_show,show_buff,len);
		backup_show_size = len;
	}
	atbm_module_muxunlock();
	atbm_modulefs_unlock();
	if(show_buff)
		atbm_kfree(show_buff);
	return len;
}

static void atbm_module_cmd_init(void)
{
	unsigned int index = 0;

	INIT_LIST_HEAD(&atbm_cmd_echo_ready_list);
	atbm_common_hash_list_init(atbm_cmd_hash_head,ATBM_CMD_HASHENTRIES);

	for(index = 0;index<ARRAY_SIZE(cmd_code_buff);index++){
		unsigned int hash_index = atbm_hash_index(cmd_code_buff[index].label,
								  strlen(cmd_code_buff[index].label),ATBM_CMD_HASHBITS);
		BUG_ON(strlen(cmd_code_buff[index].label) > ATBM_CMD_MAX_STRING_LEN);
		hlist_add_head(&cmd_code_buff[index].hnode,&atbm_cmd_hash_head[hash_index]);
		cmd_code_buff[index].echo_ready = false;
		atbm_store_cmd_deinit_show(&cmd_code_buff[index].echo);
		atbm_printk_debug("%s:[%s]->[%d]\n",__func__,cmd_code_buff[index].label,hash_index);
	}

	backup_show = atbm_kzalloc(ATBM_SHOW_MSG_MAX_SIZE, GFP_KERNEL);
	WARN_ON(backup_show == NULL);
	backup_show_size = 0;
}

static void atbm_module_cmd_exit(void)
{
	while (!list_empty(&atbm_cmd_echo_ready_list)) {
		struct atbm_store_cmd_code *cmd_code =
			list_first_entry(&atbm_cmd_echo_ready_list, struct atbm_store_cmd_code,
			lhead);
		if(cmd_code->show_cmd)
			cmd_code->show_cmd(cmd_code,NULL,false);
		atbm_store_cmd_echo_done(cmd_code);
		atbm_store_cmd_deinit_show(&cmd_code->echo);		
	}

	if(backup_show){
		atbm_kfree(backup_show);
	}
	backup_show = NULL;
	backup_show_size = 0;
}
static void atbm_module_firmware_caps_show(struct atbm_module_show *show_buff,struct atbm_common *hw_priv)
{
	#define WSM_CAP(cap)  !!(hw_priv->wsm_caps.firmwareCap&cap)
	
	atbm_module_show_put(show_buff,LIGHT"Firmare Cap:"NORMAL ENTER);
	atbm_module_show_put(show_buff,"PRIVATE_IE  [%d]\n" ,WSM_CAP(CAPABILITIES_ATBM_PRIVATE_IE)); 
	atbm_module_show_put(show_buff,"NVR_IPC     [%d]\n" ,WSM_CAP(CAPABILITIES_NVR_IPC));  
	atbm_module_show_put(show_buff,"NO_CONFIRM  [%d]\n" ,WSM_CAP(CAPABILITIES_NO_CONFIRM));
	atbm_module_show_put(show_buff,"SDIO_PATCH  [%d]\n" ,WSM_CAP(CAPABILITIES_SDIO_PATCH));
	atbm_module_show_put(show_buff,"NO_BACKOFF  [%d]\n" ,WSM_CAP(CAPABILITIES_NO_BACKOFF));
	atbm_module_show_put(show_buff,"CFO         [%d]\n" ,WSM_CAP(CAPABILITIES_CFO));  
	atbm_module_show_put(show_buff,"AGC         [%d]\n" ,WSM_CAP(CAPABILITIES_AGC));  
	atbm_module_show_put(show_buff,"TXCAL       [%d]\n" ,WSM_CAP(CAPABILITIES_TXCAL));
	atbm_module_show_put(show_buff,"CTS_BUG     [%d]\n" ,WSM_CAP(CAPABILITIES_CTS_BUG));
	atbm_module_show_put(show_buff,"MONITOR     [%d]\n" ,WSM_CAP(CAPABILITIES_MONITOR));  
	atbm_module_show_put(show_buff,"CUSTOM      [%d]\n" ,WSM_CAP(CAPABILITIES_CUSTOM));
	atbm_module_show_put(show_buff,"SMARTCONFIG [%d]\n" ,WSM_CAP(CAPABILITIES_SMARTCONFIG));
	atbm_module_show_put(show_buff,"ETF         [%d]\n" ,WSM_CAP(CAPABILITIES_ETF));
	atbm_module_show_put(show_buff,"LMAC_RATECTL[%d]\n" ,WSM_CAP(CAPABILITIES_LMAC_RATECTL));  
	atbm_module_show_put(show_buff,"LMAC_TPC    [%d]\n" ,WSM_CAP(CAPABILITIES_LMAC_TPC));  
	atbm_module_show_put(show_buff,"LMAC_TEMPC  [%d]\n" ,WSM_CAP(CAPABILITIES_LMAC_TEMPC));  
	atbm_module_show_put(show_buff,"USE_IPC     [%d]\n" ,WSM_CAP(CAPABILITIES_USE_IPC));
	atbm_module_show_put(show_buff,"OUTER_PA    [%d]\n" ,WSM_CAP(CAPABILITIES_OUTER_PA));
	atbm_module_show_put(show_buff,"HW_CHECKSUM [%d]\n" ,WSM_CAP(CAPABILITIES_HW_CHECKSUM));
	atbm_module_show_put(show_buff,"MULTI_RX    [%d]\n" ,WSM_CAP(CAPABILITIES_SINGLE_CHANNEL_MULTI_RX));
	atbm_module_show_put(show_buff,"USB_RECOVERY_BUG      [%d]\n" ,WSM_CAP(CAPABILITIES_USB_RECOVERY_BUG)); 	
	atbm_module_show_put(show_buff,"POWER_CONSUMPTION     [%d]\n" ,WSM_CAP(CAPABILITIES_POWER_CONSUMPTION));
	atbm_module_show_put(show_buff,"RSSI_DECIDE_TXPOWER   [%d]\n" ,WSM_CAP(CAPABILITIES_RSSI_DECIDE_TXPOWER));
	atbm_module_show_put(show_buff,"RTS_LONG_DUR          [%d]\n" ,WSM_CAP(CAPABILITIES_RTS_LONG_DURATION));
	atbm_module_show_put(show_buff,"TX_CFO_PPM_CORRECTION [%d]\n" ,WSM_CAP(CAPABILITIES_TX_CFO_PPM_CORRECTION));
	atbm_module_show_put(show_buff,"NOISE_SET_DCXO        [%d]\n" ,WSM_CAP(CAPABILITIES_NOISE_SET_DCXO));
}

static void atbm_module_driver_caps_show(struct atbm_module_show *show_buff,struct atbm_common *hw_priv)
{
	atbm_module_show_put(show_buff,LIGHT"Driver Cap:"NORMAL ENTER);
#ifdef USB_BUS
	atbm_module_show_put(show_buff,"HIF_TYPE    [%s]\n","USB");
#endif
#ifdef SDIO_BUS
	atbm_module_show_put(show_buff,"HIF_TYPE    [%s]\n","SDIO");
#endif 
#ifdef SPI_BUS
	atbm_module_show_put(show_buff,"HIF_TYPE    [%s]\n","SPI");
#endif 
#ifdef ATBM_NOT_SUPPORT_40M_CHW
	atbm_module_show_put(show_buff,"HW_CHW      [%s]\n","40M");
#else
	atbm_module_show_put(show_buff,"HW_CHW      [%s]\n","20M");
#endif
#ifdef CONFIG_ATBM_5G_PRETEND_2G
	atbm_module_show_put(show_buff,"BAND_SUPPORT[%s]\n","5G and 2G");
#else
	atbm_module_show_put(show_buff,"BAND_SUPPORT[%s]\n","only 2G");
#endif
	
}
static ssize_t atbm_module_show_system_info(struct kobject *kobj,
			     struct kobj_attribute *attr, char *buf)
{
	struct atbm_module_show sys_show;
	struct atbm_common *hw_priv = NULL;
	
	atbm_show_init(&sys_show,buf);
	
	atbm_module_muxlock();
	if(atbm_hw_priv_dereference() == NULL){
		atbm_module_show_put(&sys_show,"system info not exit,please plug chip\n");
		goto exit;
	}
	hw_priv = atbm_hw_priv_dereference();
	atbm_module_show_put(&sys_show,LIGHT"DriverVer   [%d]"NORMAL ENTER ,DRIVER_VER);
	atbm_module_show_put(&sys_show,LIGHT"FirmwareVer [%d]"NORMAL ENTER ,hw_priv->wsm_caps.firmwareVersion);
	atbm_module_firmware_caps_show(&sys_show,hw_priv);
	atbm_module_driver_caps_show(&sys_show,hw_priv);
exit:
	atbm_module_muxunlock();

	return sys_show.show_count;
}
static ssize_t atbm_module_show_backup_info(struct kobject *kobj,
			     struct kobj_attribute *attr, char *buf)
{
	ssize_t size = 0;
	
	atbm_modulefs_lock();
	atbm_module_muxlock();
	if(backup_show && backup_show_size){
		size = backup_show_size;
		if(WARN_ON(size > ATBM_SHOW_MSG_MAX_SIZE))
			size = ATBM_SHOW_MSG_MAX_SIZE;
		memcpy(buf,backup_show,ATBM_SHOW_MSG_MAX_SIZE);
	}
	atbm_module_muxunlock();
	atbm_modulefs_unlock();

	return size;
}
static struct kobject *atbm_module_kobj = NULL;

static struct kobj_attribute atbm_module_common_attr  = __ATTR(atbm_cmd, 0644,atbm_module_cmd_show,atbm_module_cmd_store);
static struct kobj_attribute atbm_module_sysinfo_attr = __ATTR(atbm_sys,  0444,atbm_module_show_system_info, NULL);
static struct kobj_attribute atbm_module_common_backup_attr = __ATTR(atbm_sys_backup,  0444,atbm_module_show_backup_info, NULL);

static struct attribute *atbm_module_attribute_group[]= {
	&atbm_module_common_attr.attr,
	&atbm_module_common_backup_attr.attr,
	&atbm_module_sysinfo_attr.attr,
	NULL,
};
static struct attribute_group atbm_module_attr_group = {
	.attrs = atbm_module_attribute_group,
};

int atbm_module_attribute_init(void)
{
	int error;
	struct kobject *parent = atbm_module_parent;
	
	atbm_module_kobj = kobject_create_and_add("atbmfs",parent);
	if (!atbm_module_kobj){
		return -EINVAL;
	}
	error = sysfs_create_group(atbm_module_kobj, &atbm_module_attr_group);
	if (error)
		kobject_put(atbm_module_kobj);
	atbm_modulefs_lock_int();
	atbm_module_cmd_init();
	return error;
}
void atbm_module_attribute_exit(void)
{
	if(atbm_module_kobj == NULL)
		return;
	sysfs_remove_group(atbm_module_kobj, &atbm_module_attr_group);
	kobject_put(atbm_module_kobj);
	atbm_modulefs_lock();
	atbm_module_cmd_exit();
	atbm_modulefs_unlock();
	atbm_modulefs_lock_release();
}
