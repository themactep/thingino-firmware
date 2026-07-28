#ifndef _IEEE80211_ATBM_MEM_H_
#define _IEEE80211_ATBM_MEM_H_
#if defined (ATBM_ALLOC_MEM_DEBUG)
extern void *ieee80211_atbm_kzalloc(size_t s, gfp_t gfp,const char *func);
extern void *ieee80211_atbm_kmalloc(size_t s, gfp_t gfp,const char *func);
extern void *ieee80211_atbm_kcalloc(size_t n, size_t size, gfp_t gfp,const char *func);
extern void *ieee80211_atbm_krealloc(void *p, size_t new_size, gfp_t gfp,const char *func);
extern void ieee80211_atbm_kfree(void *p);
extern void ieee80211_atbm_mem_exit(void);
extern void ieee80211_atbm_mem_int(void);


#define atbm_kzalloc(_s,_gfp)  					ieee80211_atbm_kzalloc(_s,_gfp,__func__)
#define atbm_kmalloc(_s,_gfp)  					ieee80211_atbm_kmalloc(_s,_gfp,__func__)
#define atbm_kcalloc(_n,_size,_gfp)  			ieee80211_atbm_kcalloc(_n,_size,_gfp,__func__)
#define atbm_krealloc(_p,_new_size,_gfp)		ieee80211_atbm_krealloc(_p,_new_size,_gfp,__func__)
#define atbm_kfree(_p)							ieee80211_atbm_kfree(_p)
#else
#define atbm_kzalloc(_s,_gfp)  					kzalloc(_s,_gfp)
#define atbm_kmalloc(_s,_gfp)  					kmalloc(_s,_gfp)
#define atbm_kcalloc(_n,_size,_gfp)  			kcalloc(_n,_size,_gfp)
#define atbm_krealloc(_p,_new_size,_gfp)		krealloc(_p,_new_size,_gfp)
#define atbm_kfree(_p)							kfree(_p)
#define ieee80211_atbm_mem_exit()
#define ieee80211_atbm_mem_int()
#endif

#endif  //_ATBM_P2P_H_

