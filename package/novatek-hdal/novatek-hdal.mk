################################################################################
#
# novatek-hdal
#
################################################################################

NOVATEK_HDAL_SITE = $(call qstrip,$(BR2_PACKAGE_NOVATEK_HDAL_BLOBS))
NOVATEK_HDAL_SITE_METHOD = local
NOVATEK_HDAL_LICENSE = PROPRIETARY
NOVATEK_HDAL_DEPENDENCIES = linux

ifeq ($(BR2_PACKAGE_NOVATEK_HDAL)$(NOVATEK_HDAL_SITE),y)
$(error BR2_PACKAGE_NOVATEK_HDAL_BLOBS is empty: set it in user/<camera>/local.fragment)
endif

NOVATEK_HDAL_SENSOR = $(call qstrip,$(BR2_SENSOR_1_NAME))
NOVATEK_HDAL_MODDIR = $(TARGET_DIR)/lib/modules/$(LINUX_VERSION_PROBED)

# Stock's load order (S10_SysInit2). The *_id_list masks are what stock
# passes on NA51084-class chips such as the NT98529.
define NOVATEK_HDAL_MODULES_D
	printf '%s\n' \
		kwrap kdrv_builtin kdrv_comm kdrv_gfx2d kdrv_videocapture \
		kdrv_videoprocess kflow_common nvt_videosprite kflow_videocapture \
		kflow_videoprocess kdrv_afn_neon kdrv_afn nvt_gfx \
		"nvt_sen_$(NOVATEK_HDAL_SENSOR) sen_cfg_path=/etc/sensor/sen_$(NOVATEK_HDAL_SENSOR).cfg" \
		kdrv_h26x nvt_vencrc kflow_videoenc \
		"nvt_isp isp_id_list=0x1B" "nvt_awb awb_id_list=0x1B" \
		"nvt_iq iq_id_list=0x1B" "nvt_ae ae_id_list=0x1B" \
		> $(TARGET_DIR)/etc/modules.d/30-hdal
endef

define NOVATEK_HDAL_INSTALL_TARGET_CMDS
	$(INSTALL) -d $(NOVATEK_HDAL_MODDIR)/hdal $(TARGET_DIR)/etc/modules.d $(TARGET_DIR)/etc/sensor
	$(INSTALL) -D -m 0644 $(@D)/vos/kwrap/kwrap.ko $(NOVATEK_HDAL_MODDIR)/vos/kwrap/kwrap.ko
	cd $(@D)/hdal && for m in \
		kdrv_builtin/kdrv_builtin.ko comm/kdrv_comm.ko kdrv_gfx2d/kdrv_gfx2d.ko \
		kdrv_videocapture/kdrv_videocapture.ko kdrv_videoprocess/kdrv_videoprocess.ko \
		kflow_common/kflow_common.ko kflow_gfx/videosprite/nvt_videosprite.ko \
		kflow_videocapture/kflow_videocapture.ko kflow_videoprocess/kflow_videoprocess.ko \
		kdrv_gfx2d/kdrv_affine/affine_neon/kdrv_afn_neon.ko kdrv_gfx2d/kdrv_affine/kdrv_afn.ko \
		kflow_gfx/nvt_gfx.ko kdrv_videocodec/kdrv_h26x.ko nvt_vencrc/nvt_vencrc.ko \
		kflow_videoenc/unit/kflow_videoenc.ko isp/nvt_isp.ko awb/nvt_awb.ko iq/nvt_iq.ko ae/nvt_ae.ko \
		sen_$(NOVATEK_HDAL_SENSOR)/nvt_sen_$(NOVATEK_HDAL_SENSOR).ko; do \
		$(INSTALL) -D -m 0644 $$m $(NOVATEK_HDAL_MODDIR)/hdal/$$m || exit 1; \
	done
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/lib $(@D)/lib/*.so
	$(INSTALL) -m 0644 $(@D)/sensor/sen_$(NOVATEK_HDAL_SENSOR).cfg $(TARGET_DIR)/etc/sensor/
	$(NOVATEK_HDAL_MODULES_D)
	$(INSTALL) -D -m 0755 $(NOVATEK_HDAL_PKGDIR)/files/S10debugfs $(TARGET_DIR)/etc/init.d/S10debugfs
endef

$(eval $(generic-package))
