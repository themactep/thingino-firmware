#ifndef DBG_EVENT_H
#define DBG_EVENT_H
#ifdef DBG_EVENT_LOG
void ELOG_INIT(void);
void ELOG_Add(u8 id,u32 data);
void ELOG_Stop(void);
void ELOG_Start(void);
void ELOG_Show(void);
void ELOG_Clear(void);
#define EELOG_INIT()			ELOG_INIT()
#define EELOG_Add( id, data)  	ELOG_Add( id, data)
#define EELOG_Stop()			ELOG_Stop()
#define EELOG_Start()			ELOG_Start()
#define EELOG_Show()			ELOG_Show()
#define EELOG_Clear()			ELOG_Clear()
#else
#define EELOG_INIT()			
#define EELOG_Add( id, data)  	
#define EELOG_Stop()			
#define EELOG_Start()			
#define EELOG_Show()			
#define EELOG_Clear()			
#endif
enum{
	USB_RX_EVENT_BASE=0x10,
	USB_TX_EVENT_BASE=0x20,
	SDIO_RX_EVENT_BASE=0x30,
	SDIO_TX_EVENT_BASE=0x40,
	USB_HAL_EVENT_BASE=0X50,
	USB_MAC80211_EVENT_BASE=0x60,
	SDIO_HAL_EVENT_BASE=0X70,
	SDIO_MAC80211_EVENT_BASE=0x80

};
enum {
	USB_BH_RX_EVENT=USB_RX_EVENT_BASE,
	USB_BH_RX_EVENT1=USB_RX_EVENT_BASE+1,
	USB_BH_RX_EVENT2=USB_RX_EVENT_BASE+2,
	USB_BH_RX_EVENT3=USB_RX_EVENT_BASE+3

};
enum {
	USB_BH_TX_EVENT=USB_TX_EVENT_BASE,
	USB_BH_TX_EVENT1=USB_TX_EVENT_BASE+1,
	USB_BH_TX_EVENT2=USB_TX_EVENT_BASE+2,
	USB_BH_TX_EVENT3=USB_TX_EVENT_BASE+3

};
#endif //DBG_EVENT_H

