include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OldTrollAppSync-installd

OldTrollAppSync-installd_FILES = AppSyncUnified-installd.x dump.cpp cdhash.m
OldTrollAppSync-installd_CFLAGS += -fvisibility=hidden -Wno-unused-private-field -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0
OldTrollAppSync-installd_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
