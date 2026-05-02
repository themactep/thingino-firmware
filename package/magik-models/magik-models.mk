MAGIK_MODELS_SITE_METHOD = git
MAGIK_MODELS_SITE = https://github.com/gtxaspec/magik_models
MAGIK_MODELS_SITE_BRANCH = main
MAGIK_MODELS_VERSION = 292baa3
MAGIK_MODELS_INSTALL_TARGET = YES
MAGIK_MODELS_INSTALL_STAGING = NO

MAGIK_MODELS_LICENSE = Proprietary
MAGIK_MODELS_LICENSE_FILES =

define MAGIK_MODELS_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/usr/share/models
	$(if $(BR2_PACKAGE_MAGIK_MODELS_YOLOV5), \
		$(INSTALL) -m 0644 $(@D)/Txx/jzdl/magik_model_yolov5.bin \
			$(TARGET_DIR)/usr/share/models/;)
	$(if $(BR2_PACKAGE_MAGIK_MODELS_PERSONDET), \
		$(INSTALL) -m 0644 $(@D)/Txx/jzdl/magik_model_persondet.bin \
			$(TARGET_DIR)/usr/share/models/;)
	$(if $(BR2_PACKAGE_MAGIK_MODELS_FACEDET), \
		$(INSTALL) -m 0644 $(@D)/Txx/jzdl/magik_model_facedet.bin \
			$(TARGET_DIR)/usr/share/models/;)
endef

$(eval $(generic-package))
