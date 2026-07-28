#
#makefile for build atbm_wifi.ko
#
###############################################################################
#
# when release to customer ,the CUSTOMER_SUPPORT_USED must set to y!!!!!!!!!!!!!
#
###############################################################################
CUSTOMER_SUPPORT_USED=y
###############################################################################
#PLATFORM_XUNWEI    		1
#PLATFORM_SUN6I					2
#PLATFORM_FRIENDLY			3
#PLATFORM_SUN6I_64			4
#PLATFORM_HI3798M				5
#PLATFORM_HI3518E				6
#PLATFORM_X86PC         7
#PLATFORM_AMLOGIC				8
#PLATFORM_AMLOGIC_905X	9
#PLATFORM_ROCKCHIP      10
#PLATFORM_MSTAR					11
#PLATFORM_CDLINUX				12
#PLATFORM_AMLOGIC_S805	13
#PLATFORM_HIS_LINUX_3_4				14
#PLATFORM_ROCKCHIP_3229				15
#PLATFORM_ROCKCHIP_3229_ANDROID8		16
#PLATFORM_HS_IPC				17
#PLATFORM_SIGMASTAR                           18
#PLATFORM_HI3516EV200                         19
#PLATFORM_XUNWEI_2G                            20
#PLATFORM_NVT98517       21
#PLATFORM_INGENIC_T40  22
#PLATFORM_INGENIC_T41  23
export
platform ?=PLATFORM_INGENIC_T41
#Android
#Linux
sys ?= linux
#arch:arm or arm64 or mips(NVT98517)
arch ?= mips
#export 
#ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=$(platform)

ifeq ($(CUSTOMER_SUPPORT_USED),y)
MAKEFILE_SUB ?= Makefile.build.customer
else
MAKEFILE_SUB ?= Makefile.build
endif


ifeq ($(platform),PLATFORM_INGENIC_T41)
#KERDIR:=/wifi_prj/staff/zhouzhanchao/iTop4412_Kernel_3.0/
#KERDIR:=/home/xzq/svn_nvt_sdk/new_ipc_sdk/sdk_2.0/98517/6032i/NA51023_BSP_v1.1.1/linux-kernel/OUTPUT
#KERDIR:=/wifi_prj/staff/wangsiyao/baichuan/linux-kernel/OUTPUT/
#CROSS_COMPILE:=/wifi_prj/staff/wangsiyao/baichuan/mipsel-24kec-linux-uclibc-4.9-2017.07/usr/bin/mipsel-24kec-linux-uclibc-
#KERDIR:=/home/chenhao/Ingenic/T41/Zeratul_T41_Release_20220914/Software/tools/toolchain/gcc_720/mips-gcc720-glibc229-r5.1.4/bin/mips-linux-gnu-
KERDIR:=/home/chenhao/Ingenic/T41/Zeratul_T41_Release_20221130/Software/os/kernel-4.4.94
CROSS_COMPILE:=/home/chenhao/Ingenic/T41/mips-gcc720-glibc226/bin/mips-linux-uclibc-gnu-
arch = mips
endif

ifeq ($(platform),PLATFORM_INGENIC_T31)
KERDIR:=/usr/lchome/zouchunlai/T31/Zeratul_T31_Release_20210730/Zeratul_Release_20210730/os/kernel
CROSS_COMPILE:=mips-linux-uclibc-gnu-
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=22
arch = mips
endif


ifeq ($(KERNELRELEASE),)
export DRIVER_PATH ?= $(shell pwd)
ifeq ($(platform),PLATFORM_HS_IPC)
KERDIR:=/wifi_prj/staff/jilechang/HS_IPC_1115/kernel
CROSS_COMPILE:=/wifi_prj/staff/jilechang/HS_IPC_1115/opt/arm-anykav200-crosstool/usr/bin/arm-anykav200-linux-uclibcgnueabi-
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=17
arch = arm
endif

ifeq ($(platform),PLATFORM_ROCKCHIP_3229_ANDROID8)
ifeq ($(sys),Android)
KERDIR:=/wifi_prj/staff/zhouzhanchao/rk3328_box_oreo_release_v1.0.0_20180319/kernel
CROSS_COMPILE:=/wifi_prj/staff/zhouzhanchao/rk3328_box_oreo_release_v1.0.0_20180319/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-
else
#KERDIR:=/wifi_prj/staff/zhouzhanchao/iTop4412_Kernel_3.0/
KERDIR:=/wifi_prj/wuping/project/linux/iTop4412_Kernel_3.0/
CROSS_COMPILE:=/usr/local/arm/arm-2009q3/bin/arm-none-linux-gnueabi-
endif
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=10
arch = arm64
endif

ifeq ($(platform),PLATFORM_ROCKCHIP_3229)
ifeq ($(sys),Android)
KERDIR:=/wifi_prj/staff/zhouzhanchao/rockchip_3229_kernel/kernel/
CROSS_COMPILE:=/wifi_prj/staff/zhouzhanchao/rockchip_3229_kernel/prebuilts/gcc/linux-x86/arm/arm-eabi-4.6/bin/arm-eabi-
else
#KERDIR:=/wifi_prj/staff/zhouzhanchao/iTop4412_Kernel_3.0/
KERDIR:=/wifi_prj/wuping/project/linux/iTop4412_Kernel_3.0/
CROSS_COMPILE:=/usr/local/arm/arm-2009q3/bin/arm-none-linux-gnueabi-
endif
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=10
endif
ifeq ($(platform),PLATFORM_HIS_LINUX_3_4)
KERDIR:=/wifi_prj/staff/zhouzhanchao/his_liux3_4/linux-3.4.y/
CROSS_COMPILE:=/wifi_prj/staff/zhouzhanchao/his_liux3_4/arm-hisiv300-linux/bin/arm-hisiv300-linux-uclibcgnueabi-
arch = arm
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=14
endif
ifeq ($(platform),PLATFORM_MSTAR)
ifeq ($(sys),Linux)
KERDIR:=/wifi_prj/staff/zhouzhanchao/mstar/linux3.18_i3/
CROSS_COMPILE:=/wifi_prj/staff/zhouzhanchao/mstar/arm-linux-gnueabihf-4.8.3-201404/bin/arm-linux-gnueabihf-
else
#KERDIR:=/wifi_prj/staff/zhouzhanchao/iTop4412_Kernel_3.0/
KERDIR:=/wifi_prj/wuping/project/linux/iTop4412_Kernel_3.0/
CROSS_COMPILE:=/usr/local/arm/arm-2009q3/bin/arm-none-linux-gnueabi-
endif
export
arch = arm
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=11
endif

ifeq ($(platform),PLATFORM_SIGMASTAR)
ifeq ($(sys),Linux)
KERDIR:=/wifi_prj/staff/futianhuang/sigma_star/linux-3.18/
CROSS_COMPILE:=/wifi_prj/staff/futianhuang/sigma_star/arm-linux-gnueabihf-4.8.3-201404/bin/arm-linux-gnueabihf-
else
#KERDIR:=/wifi_prj/staff/zhouzhanchao/iTop4412_Kernel_3.0/
#KERDIR:=/wifi_prj/wuping/project/linux/iTop4412_Kernel_3.0/
#CROSS_COMPILE:=/usr/local/arm/arm-2009q3/bin/arm-none-linux-gnueabi-
endif
export
arch = arm
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=18
endif


ifeq ($(platform),PLATFORM_ROCKCHIP)
ifeq ($(sys),Android)
KERDIR:=/wifi_prj/staff/zhouzhanchao/rockchip_new/kernel1/
CROSS_COMPILE:=/wifi_prj/staff/zhouzhanchao/rockchip_new/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-
else
#KERDIR:=/wifi_prj/staff/zhouzhanchao/iTop4412_Kernel_3.0/
KERDIR:=/wifi_prj/wuping/project/linux/iTop4412_Kernel_3.0/
CROSS_COMPILE:=/usr/local/arm/arm-2009q3/bin/arm-none-linux-gnueabi-
endif
export
arch = arm64
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=10 
endif

#
#xunwei platform params
#
ifeq ($(platform),PLATFORM_XUNWEI)
ifeq ($(sys),Android)
#KERDIR:=/wifi_prj/zhouzhanchao/android4_4_2/iTop4412_Kernel_3.0/
KERDIR:=/wifi_prj/wuping/project/android4_4_2/iTop4412_Kernel_3.0
CROSS_COMPILE:=/usr/local/arm/arm-2009q3/bin/arm-none-linux-gnueabi-
else
#KERDIR:=/wifi_prj/wuping/project/linux/iTop4412_Kernel_3.0/
KERDIR:=/wifi_prj/staff/panxuqiang/wifi_prj/iTop4412_Kernel_3.0/
#KERDIR:=/wifi_prj/staff/zhouzhanchao/iTop4412_Kernel_3.0/
CROSS_COMPILE:=/usr/local/arm/arm-2009q3/bin/arm-none-linux-gnueabi-
#KERDIR:=/wifi_prj/staff/jilechang/XUNWEI/iTop4412_Kernel_3.0/
#CROSS_COMPILE:=/wifi_prj/staff/jilechang/XUNWEI/arm-2009q3/bin/arm-none-linux-gnueabi-

endif
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=1
endif
ifeq ($(platform),PLATFORM_XUNWEI_2G)
ifeq ($(sys),Android)
#KERDIR:=/wifi_prj/zhouzhanchao/android4_4_2/iTop4412_Kernel_3.0/
KERDIR:=/wifi_prj/wuping/project/android4_4_2/iTop4412_Kernel_3.0
CROSS_COMPILE:=/usr/local/arm/arm-2009q3/bin/arm-none-linux-gnueabi-
else
#KERDIR:=/wifi_prj/wuping/project/linux/iTop4412_Kernel_3.0/
#KERDIR:=/wifi_prj/staff/panxuqiang/wifi_prj/iTop4412_Kernel_3.0/
#KERDIR:=/wifi_prj/staff/zhouzhanchao/iTop4412_Kernel_3.0/
#CROSS_COMPILE:=/usr/local/arm/arm-2009q3/bin/arm-none-linux-gnueabi-
KERDIR:=/wifi_prj/staff/jilechang/XUNWEI/iTop4412_Kernel_3.0/
CROSS_COMPILE:=/wifi_prj/staff/jilechang/XUNWEI/arm-2009q3/bin/arm-none-linux-gnueabi-

endif
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=20
endif

#
#allwinner 32 platform params
#
ifeq ($(platform),PLATFORM_SUN6I)
ifeq ($(sys),Android)
KERDIR:=/wifi_prj/staff/zhouzhanchao/android4_4_SIN/Source/lichee/linux-3.3
CROSS_COMPILE:=/wifi_prj/staff/zhouzhanchao/android4_4_SIN/Source/lichee/brandy/gcc-linaro/bin/arm-linux-gnueabi-
else
KERDIR:=/wifi_prj/staff/wangzhiguang/Linux_sun6i/lichee/linux-3.3/
#KERDIR:=/wifi_prj/staff/panxuqiang/wifi_prj/branch/linux_sun6i/
CROSS_COMPILE:=/wifi_prj/staff/wangzhiguang/Linux_sun6i/lichee/buildroot/output/external-toolchain/bin/arm-linux-gnueabi-
endif
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=2
endif

#
#allwinner 64 platform params
#
ifeq ($(platform),PLATFORM_SUN6I_64)
ifeq ($(sys),Android)
KERDIR:=/wifi_prj/staff/zhouzhanchao/android6_0_SIN/cqa64_android_v6.0/lichee/linux-3.10/
CROSS_COMPILE:=/wifi_prj/staff/zhouzhanchao/android6_0_SIN/cqa64_android_v6.0/lichee/out/sun50iw1p1/android/common/buildroot/external-toolchain/bin/aarch64-linux-gnu-
else
KERDIR:=/wifi_prj/staff/panxuqiang/64bi_driver/cqa64_linux_qt5.3.2/lichee/linux-3.10/
CROSS_COMPILE:=/wifi_prj/staff/panxuqiang/64bi_driver/cqa64_linux_qt5.3.2/lichee/brandy/armv8_toolchain/gcc-linaro-aarch64-linux-gnu-4.9-2014.09_linux/bin/aarch64-linux-gnu-
endif
arch:=arm64
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=4
endif

#
#HI3798M platform params
#
ifeq ($(platform),PLATFORM_HI3798M)
ifeq ($(sys),Android)
KERDIR:=/ssd-home/zhouzhanchao/Hi3798M-60-2/Hi3798M-60/out/target/product/Hi3798MV100/obj/KERNEL_OBJ/
CROSS_COMPILE:=/opt/hisi-linux/x86-arm/arm-hisiv200-linux/target/bin/arm-hisiv200-linux-
else
#KERDIR:=/wifi_prj/staff/panxuqiang/64bi_driver/cqa64_linux_qt5.3.2/lichee/linux-3.10/
endif
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=5
endif

ifeq ($(platform),PLATFORM_PCX86)
KERDIR:=/kernel/linux-lts-utopic-3.16.0/
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=7
arch:=x86
MAKEFILE_SUB = Makefile.build.local
endif
ifeq ($(platform),PLATFORM_AMLOGIC)
ifeq ($(sys),Android)
#KERDIR:=/wifi_prj/staff/zhouzhanchao/amlogic/release_s905_l/out/target/product/p200/obj/KERNEL_OBJ/
KERDIR:=/wifi_prj/staff/mengxuehong/s905l/S905L/out/target/product/p201_iptv/obj/KERNEL_OBJ/
CROSS_COMPILE:=/ssd-home/mengxuehong/buildTool1/gcc-linaro-aarch64-linux-gnu-4.9-2014.09_linux/bin/aarch64-linux-gnu-
else
#KERDIR:=/wifi_prj/staff/panxuqiang/64bi_driver/cqa64_linux_qt5.3.2/lichee/linux-3.10/
endif
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=8
arch:=arm64
endif


ifeq ($(platform),PLATFORM_AMLOGIC_S805)
ifeq ($(sys),Android)
KERDIR:=/wifi_prj/staff/zhouzhanchao/s805_env/KERNEL_OBJ/
CROSS_COMPILE:=/wifi_prj/staff/zhouzhanchao/s805_env/opt/gcc-linaro-arm-linux-gnueabihf/bin/arm-linux-gnueabihf-
else
#KERDIR:=/wifi_prj/staff/panxuqiang/64bi_driver/cqa64_linux_qt5.3.2/lichee/linux-3.10/
endif
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=8
arch:=arm
endif

ifeq ($(platform),PLATFORM_AMLOGIC_905X)
ifeq ($(sys),Android)
KERDIR=/wifi_prj/staff/mengxuehong/mengxuehong/aml0804/n-amlogic_0804/out/target/product/p281/obj/KERNEL_OBJ
#KERDIR:=/wifi_prj/staff/mengxuehong/mengxuehong/amlogic_sdk/release_s905_l/out/target/product/p201/obj/KERNEL_OBJ/
CROSS_COMPILE:=/wifi_prj/staff/mengxuehong/mengxuehong/amlogic_sdk/buildTool/gcc-linaro-aarch64-linux-gnu-4.9-2014.09_linux/bin/aarch64-linux-gnu-
else
#KERDIR:=/wifi_prj/staff/panxuqiang/64bi_driver/cqa64_linux_qt5.3.2/lichee/linux-3.10/
endif
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=9
arch:=arm64
endif

ifeq ($(platform),PLATFORM_HI3516EV200)
KERDIR:=/wifi_prj/staff/panxuqiang/wifi_prj/Hi3516EV200_SDK_V1.0.0.2/osdrv/opensource/kernel/linux-4.9.y
CROSS_COMPILE:=/opt/hisi-linux/x86-arm/arm-himix100-linux/bin/arm-himix100-linux-
export 
arch = arm
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=19
#ATBM_WIFI__EXT_CCFLAGS += -mcpu=cortex-a7 -mfloat-abi=softfp -mfpu=neon-vfpv4 -fno-aggressive-loop-optimizations
endif

ifeq ($(platform),PLATFORM_PCX86)
all:install

install:
	@echo "make PLATFORM_PCX86"
	$(MAKE) all -f Makefile.build.local KDIR=$(KERDIR)
clean:
	$(MAKE) -f Makefile.build.local KDIR=$(KERDIR) clean
else
all:install tools_install

install:
	@echo "make PLATFORM_CROSS=$(platform)"
	$(MAKE) all -f $(MAKEFILE_SUB) ARCH=$(arch)  CROSS_COMPILE=$(CROSS_COMPILE) KDIR=$(KERDIR) SYS=$(sys) PLAT=$(platform) -j8
clean:
	$(MAKE) -f $(MAKEFILE_SUB) KDIR=$(KERDIR) ARCH=$(arch) clean
strip:	
	$(MAKE) -f $(MAKEFILE_SUB) KDIR=$(KERDIR) ARCH=$(arch) SYS=$(sys) PLAT=$(platform) strip
#get_ver:
#	$(MAKE) -f $(MAKEFILE_SUB) KDIR=$(KERDIR) ARCH=$(arch) SYS=$(sys) PLAT=$(platform) get_ver
tools_install:
	$(MAKE) tools_install -f $(MAKEFILE_SUB) ARCH=$(arch)  CROSS_COMPILE=$(CROSS_COMPILE) KDIR=$(KERDIR) SYS=$(sys) PLAT=$(platform) -j8
#power_install:
#	$(MAKE) power_install -f $(MAKEFILE_SUB) ARCH=$(arch)  CROSS_COMPILE=$(CROSS_COMPILE) KDIR=$(KERDIR) SYS=$(sys) PLAT=$(platform) -j8

buid_config:
	$(MAKE) -C atbm_kconf mconf -f Makefile
menuconfig:buid_config
	@./atbm_kconf/mconf ./atbm_kconf/Kconfig
endif
else
ifeq ($(platform),PLATFORM_XUNWEI)
export 
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=1
endif
ifeq ($(platform),PLATFORM_SUN6I)
export 
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=2
endif
ifeq ($(platform),PLATFORM_SUN6I_64)
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=4
endif
ifeq ($(platform),PLATFORM_HI3798M)
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=5
endif
ifeq ($(platform),PLATFORM_AMLOGIC)
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=8
endif
ifeq ($(platform),PLATFORM_AMLOGICi_905X)
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=9
endif
ifeq ($(platform),PLATFORM_ROCKCHIP)
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=10
endif
ifeq ($(platform),PLATFORM_MSTAR)
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=11
endif
ifeq ($(platform),PLATFORM_CDLINUX)
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=12
endif
ifeq ($(platform),PLATFORM_AMLOGIC_S805)
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=13
endif
ifeq ($(platform),PLATFORM_ROCKCHIP_3229)
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=10
endif
ifeq ($(platform),PLATFORM_NVT98517)
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=14
endif
ifeq ($(platform),PLATFORM_INGENIC_T41)
export
ATBM_WIFI__EXT_CCFLAGS = -DATBM_WIFI_PLATFORM=23
endif
export 
include $(src)/Makefile.build.kernel
#obj-y += wifi_sdio/
endif



