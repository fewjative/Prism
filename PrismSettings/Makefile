ARCHS = armv7 arm64
include theos/makefiles/common.mk

BUNDLE_NAME = PrismSettings
PrismSettings_FILES = PrismSettings.mm
PrismSettings_INSTALL_PATH = /Library/PreferenceBundles
PrismSettings_FRAMEWORKS = UIKit
PrismSettings_PRIVATE_FRAMEWORKS = Preferences Social
PrismSettings_LIBRARIES = colorpicker

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/PrismSettings.plist$(ECHO_END)

include $(THEOS_MAKE_PATH)/aggregate.mk
