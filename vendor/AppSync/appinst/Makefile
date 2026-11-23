include $(THEOS)/makefiles/common.mk

TOOL_NAME = appinst
appinst_FILES = appinst.m
appinst_CCFLAGS += -std=c++11 -stdlib=libc++ -fobjc-arc -fvisibility=hidden -Wno-unused-property-ivar -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0
appinst_CFLAGS += -fobjc-arc -fvisibility=hidden -Wno-unused-property-ivar -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0
appinst_FRAMEWORKS = Foundation
appinst_PRIVATE_FRAMEWORKS = MobileCoreServices
appinst_LIBRARIES = objc
appinst_INSTALL_PATH = /usr/libexec/oldtroll
appinst_CODESIGN_FLAGS = -Sappinst_entitlements.plist

include $(THEOS_MAKE_PATH)/tool.mk
