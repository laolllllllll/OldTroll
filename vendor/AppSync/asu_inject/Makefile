include $(THEOS)/makefiles/common.mk

TOOL_NAME = asu_inject
asu_inject_FILES = asu_inject.c
asu_inject_CFLAGS += -fvisibility=hidden -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0
asu_inject_INSTALL_PATH = /usr/libexec/oldtroll
asu_inject_CODESIGN_FLAGS = -S../entitlements.plist

include $(THEOS_MAKE_PATH)/tool.mk
