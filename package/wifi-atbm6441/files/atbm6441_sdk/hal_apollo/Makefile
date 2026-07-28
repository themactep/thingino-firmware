#CONFIG_TX_NO_CONFIRM
#CONFIG_USB_AGGR_URB_TX
#CONFIG_TX_NO_CONFIRM
#
# ��������ѡ��ͬ��ģʽ��CONFIG_USB_AGGR_URB_TX ������ʱһ����Ҫ����CONFIG_USE_DMA_ADDR_BUFFER
# 1> CONFIG_USB_AGGR_URB_TX + CONFIG_TX_NO_CONFIRM��ÿ��urb ���Ͷ��txframe ���Ҳ���Ҫconfirm����Ҫ��lmac��NO_NEED_CONFIRM �꣬����ratecontrol��lmac ʵ��
# 2> CONFIG_USB_AGGR_URB_TX ÿ��urb ���Ͷ��txframe ������Ҫconfirm����Ҫ�ر�lmac��NO_NEED_CONFIRM ��
# 3> ���к궼�����壬ÿ��urb ����һ��txframe ������Ҫconfirm������urbֱ��ʹ��skbbuffer����Ҫ�ر�lmac��NO_NEED_CONFIRM ��
# 4> ����CONFIG_USE_DMA_ADDR_BUFFER��ÿ��urb ����һ��txframe ������Ҫconfirm������urbֱ��DMAbuffer����Ҫ�����ݴ�skb copy��DMAbuffer����Ҫ�ر�lmac��NO_NEED_CONFIRM �꣬
# 5> ����CONFIG_USE_DMA_ADDR_BUFFER+ CONFIG_TX_NO_CONFIRM��ÿ��urb ����һ��txframe ���Ҳ���Ҫconfirm������urbֱ��DMAbuffer����Ҫ�����ݴ�skb copy��DMAbuffer����Ҫ��lmac��NO_NEED_CONFIRM �꣬����ratecontrol��lmac ʵ��
# 6> ����CONFIG_TX_NO_CONFIRM��ÿ��urb ����һ��txframe ���Ҳ���Ҫconfirm������urbֱ��ʹ��skbbuffer����Ҫ��lmac��NO_NEED_CONFIRM �꣬����ratecontrol��lmac ʵ��
#
##���ڵ�����+cpuǿ�İ���ʹ�� ģʽ1 ���� ģʽ2
##���ڵ��ȿ�+cpu���İ���ʹ�� ģʽ3 ���� ģʽ6
## Ĭ��ʹ��ģʽ 3
#####################################################################################################################################################################################################################
##ָ�������ļ�·�����������ļ�����ʱʹ�������ļ��е�dcxoֵ��ʹ��efuse�е�dcxo�������ļ��е�delta_gainΪ����ֵ������ļ���������ֱ��ʹ��efuse�е�����
ATBM_CONFIG_FILE="/atbm_txpwer_dcxo_cfg.txt"
ifneq ($(IF1NAME),)
ccflags-y += -DCONFIG_IF1NAME=\"$(IF1NAME)\"
endif
ifneq ($(IF2NAME),)
ccflags-y += -DCONFIG_IF2NAME=\"$(IF2NAME)\"
endif		
ATBM_MODULES_NAME ?= $(MODULES_NAME)
ifneq ($(FW),)
ccflags-y += -DCONFIG_FW_NAME=\"$(FW)\"
endif
ccflags-y += $(ATBM_WIFI__EXT_CCFLAGS)

ccflags-y += -DATBM_WIFI_QUEUE_LOCK_BUG
ccflags-y += -DATBM_CHANGE_AP_TIMESTAMP_TO_BOOTTIME
ccflags-y += -DATBM_USE_SAVED_FW
ccflags-y += -DATBM_APOLLO_SUSPEND_RESUME_FILTER_ENABLE
ccflags-y += -DCONFIG_ATBM_IOCTRL
ccflags-y += -DOPER_CLOCK_USE_SEM
ccflags-y += -DEXIT_MODULE_RESET_USB=0
ccflags-y += -DATBM_VIF_LIST_USE_RCU_LOCK
ccflags-y += -DATBM_SUPPORT_SMARTCONFIG 

ifeq ($(platform),PLATFORM_AMLOGIC_S805)
ccflags-y += -DCONFIG_ATBM_APOLLO_USE_GPIO_IRQ
endif
ifeq ($(platform),PLATFORM_AMLOGIC)
#ccflags-y += -DCONFIG_ATBM_APOLLO_USE_GPIO_IRQ
endif

#if used sdio download firmware
# ccflags-y += -DWIFI_FW_DOWNLOAD  # firmware is in MCU NVM
# Extra IE for probe response from upper layer is needed in P2P GO
# For offloading probe response to FW, the extra IE must be included
# in the probe response template
ccflags-y += -DCONFIG_ATBM_APOLLO_DEBUG
###################################################################
#ATBM_SUSPEND_REMOVE_INTERFACE
#before enter suspend state ,remove all interface
###################################################################
ccflags-$(PMRELODDFW) += -DATBM_SUSPEND_REMOVE_INTERFACE
###################################################################
#ATBM_PM_USE_EARLYSUSPEND
#early suspend enbale
###################################################################
ccflags-$(EARLYSUSPEND) += -DATBM_PM_USE_EARLYSUSPEND
###################################################################
#ATBM_ALLOC_MEM_DEBUG
#debug mem leakage
###################################################################
ccflags-$(MEM_DEBUG) += -DATBM_ALLOC_MEM_DEBUG
###################################################################
#ATBM_ALLOC_SKB_DEBUG
#debug skb leakage
###################################################################
ccflags-$(SKB_DEBUG) += -DATBM_ALLOC_SKB_DEBUG
####################################################################
#CONFIG_TX_NO_CONFIRM      
#enable tx noconfirm
####################################################################
ccflags-y += -DCONFIG_TX_NO_CONFIRM
####################################################################

#ccflags-y += -DCONFIG_ATBM_APOLLO_BH_DEBUG
#ccflags-y += -DCONFIG_ATBM_APOLLO_WSM_DEBUG
#ccflags-y += -DCONFIG_ATBM_APOLLO_WSM_DUMPS
#ccflags-y += -DCONFIG_ATBM_APOLLO_WSM_DUMPS_SHORT
#ccflags-y += -DCONFIG_ATBM_APOLLO_TXRX_DEBUG
#ccflags-y += -DCONFIG_ATBM_APOLLO_TX_POLICY_DEBUG
#ccflags-y += -DCONFIG_ATBM_APOLLO_STA_DEBUG
#ccflags-y += -DCONFIG_ATBM_APOLLO_DUMP_ON_ERROR
#ccflags-y += -DCONFIG_ATBM_APOLLO_ITP
ccflags-y += -DCONFIG_ATBM_APOLLO_TESTMODE
# use the mac addr in file :"/data/.mac.info"
ccflags-y += -DCUSTOM_FEATURE_MAC
ccflags-y += -DCONFIG_ATBMWIFI_WDT
# use the txpower and dcxo value in file :"$(ATBM_CONFIG_FILE)",when file exist
ccflags-y += -DCONFIG_TXPOWER_DCXO_VALUE=\"$(ATBM_CONFIG_FILE)\"
#PLATFORM_XUNWEI
#PLATFORM_SUN6I
#PLATFORM_FRIENDLY
#PLATFORM_SUN6I_64
#ccflags-y += -DATBM_WIFI_PLATFORM=PLATFORM_HIS
ifeq ($(CONFIG_ARESB),y)
ccflags-y += -DPROJ_TYPE=ARES_B
ccflags-$(CHECKSUM) += -DCHKSUM_HW_SUPPORT
ccflags-y += -DDPLL_CLOCK=DPLL_CLOCK_24M
endif

ifeq ($(CONFIG_HERA),y)
ccflags-y += -DPROJ_TYPE=HERA
#ccflags-y += -DCHKSUM_HW_SUPPORT
ccflags-y += -DDPLL_CLOCK=DPLL_CLOCK_24M
endif

ifeq ($(CONFIG_FPGA),y)
#ccflags-y += -DDCXO_USE_SMU_REG
ccflags-y += -DSDIO_CHANGE=1
#ccflags-y += -DRESET_CHANGE
#ccflags-y += -DTEST_DCXO_CONFIG=1
endif
#if TEST_DCXO_CONFIG is not config,DCXO_TYPE is not used
#if TEST_DPLL_CONFIG is not config,DPLL_CLOCK is not used

ccflags-y += -DCONFIG_ATBM_APOLLO_SUPPORT_SGI
ifeq ($(USB_BUS),y)
ccflags-y += -DUSB_BUS
ccflags-y += -DUSB_USE_TASTLET_TXRX
ccflags-y += -DUSB_BUS_BUG
#ccflags-y += -DCONFIG_WSM_CMD_XMIT_DIRECTLY
#ccflags-y += -DCONFIG_USB_DATA_XMIT_DIRECTLY
#ccflags-y += -DCONFIG_USE_DMA_ADDR_BUFFER
#ccflags-y += -DCONFIG_USB_AGGR_URB_TX
#ccflags-y += -DCONFIG_TX_NO_CONFIRM
#ccflags-y += -DATBM_IPC_ASSOC
#ccflags-y += -DATBM_PRIVATE_IE
#ccflags-y += -DSIGMASTAR_FILTER_MACADDR_ONLY
#ccflags-y += -DCONFIG_ATBM_5G_PRETEND_2G
endif
ifeq ($(TX_NO_CONFIRM),y)
#ccflags-y += -DCONFIG_USE_DMA_ADDR_BUFFER
ccflags-y += -DCONFIG_USB_AGGR_URB_TX
ccflags-y += -DCONFIG_TX_NO_CONFIRM
endif
ifeq ($(SDIO_BUS),y)
#ccflags-y += -DMCAST_FWDING
#ccflags-y += -DRESET_CHANGE
ccflags-y += -DSDIO_BUS
#ccflags-y += -DATBM_SDIO_TXRX_ENHANCE
#ccflags-y += -DATBM_WSM_SDIO_TX_MULT
#ccflags-y += -DRESET_CHIP
ifeq ($(CONFIG_ATBM_SDIO_ATCMD),y)
ccflags-y += -DCONFIG_ATBM_SDIO_ATCMD
endif
endif
ifeq ($(SPI_BUS),y)
ccflags-y += -DSPI_BUS
endif
ccflags-y += -DPS_SETUP
MODFLAGS =-DMODULE -fno-pic 
CFLAGS_MODULE =$(MODFLAGS)

ifeq ($(CONFIG_ATBM_APOLLO_DEBUGFS),y)
ccflags-y  += -DCONFIG_ATBM_APOLLO_DEBUGFS
endif
#ccflags-y  += -DCONFIG_ATBM_APOLLO_DEBUG
ccflags-y += -DCONFIG_MAC80211_ATBM_RC_DEFAULT_MINSTREL
#ccflags-y += -DMINSTREL_SAMPLE_SKIP_LOW_RATE_HT
#ccflags-y += -DMINSTREL_SAMPLE_SKIP_LOW_RATE

ccflags-y  += -DPROBE_RESP_EXTRA_IE
#ccflags-y  += -DIPV6_FILTERING
#ccflags-y += -DCONFIG_ATBM_APOLLO_TESTMODE
#ccflags-y += -DCONFIG_NL80211_TESTMODE
ccflags-y += -DCONFIG_MAC80211_ATBM_ROAMING_CHANGES
ifeq ($(CONFIG_MAC80211_ATBM_DEBUGFS),y)
ccflags-y  += -DCONFIG_MAC80211_ATBM_DEBUGFS
endif
CFLAGS_driver-trace.o := -I$(src)

# objects for PID algorithm

ccflags-y  += -I$(PWD)/os/linux


$(ATBM_MODULES_NAME)-y += \
		fwio.o \
		wsm.o \
		main.o \
		iface.o \
		util.o module_fs.o \
		atbm_ioctl.o

ifneq ($(CONFIG_ATBM_SDIO_ATCMD),y)
$(ATBM_MODULES_NAME)-y += \
		sta_info.o \
		txrx.o  \
		agg-rx.o \
		rx.o		
endif

ifeq ($(USB_BUS),y)
$(ATBM_MODULES_NAME)-y += apollo_usb.o atbm_platform.o hwio_usb.o bh_usb.o
else ifeq ($(SDIO_BUS),y)
$(ATBM_MODULES_NAME)-y += apollo_sdio.o atbm_platform.o hwio_sdio.o bh_sdio.o dcxo_dpll.o
else ifeq ($(SPI_BUS),y)
$(ATBM_MODULES_NAME)-y += apollo_spi.o atbm_platform.o hwio_spi.o bh_spi.o
endif
$(ATBM_MODULES_NAME)-$(CONFIG_PM)		+= pm.o
$(ATBM_MODULES_NAME)-$(MEM_DEBUG)       += ieee80211_atbm_mem.o
$(ATBM_MODULES_NAME)-$(SKB_DEBUG)       += ieee80211_atbm_skb.o

obj-$(CONFIG_ATBM_APOLLO) += $(ATBM_MODULES_NAME).o

ccflags-y += -D__CHECK_ENDIAN__
ccflags-y += -DLINUX_OS
MODFLAGS =-DMODULE -fno-pic
CFLAGS_MODULE =$(MODFLAGS)

