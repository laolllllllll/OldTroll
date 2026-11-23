export ARCHS = armv7
export TARGET = iphone:clang:latest:6.0
export ADDITIONAL_CFLAGS = -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0

# Cydia accepts gzip-compressed debs and macOS ships gzip but not lzma.
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += vendor/AppSync/AppSyncUnified-installd
SUBPROJECTS += vendor/AppSync/AppSyncUnified-FrontBoard
SUBPROJECTS += vendor/AppSync/appinst
SUBPROJECTS += vendor/AppSync/asu_inject

include $(THEOS_MAKE_PATH)/aggregate.mk

APPLICATION_NAME = OldTroll

OldTroll_FILES = $(wildcard OldTroll/*.m)
OldTroll_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
OldTroll_CFLAGS = -fobjc-arc -Wall -Wno-deprecated-declarations -Wno-unused-parameter -target armv7-apple-ios6.0 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0
OldTroll_LDFLAGS = -Xlinker -dead_strip -target armv7-apple-ios6.0 -lgcc_s.1 -Wl,-U,_objc_msgSend_stret

include $(THEOS_MAKE_PATH)/application.mk

TOOL_NAME = oldtroll_helper
oldtroll_helper_FILES = helper/main.c
oldtroll_helper_LDFLAGS = -target armv7-apple-ios6.0 -lgcc_s.1
oldtroll_helper_INSTALL_PATH = /usr/bin
oldtroll_helper_CFLAGS = -Wall -target armv7-apple-ios6.0 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0

include $(THEOS_MAKE_PATH)/tool.mk

# GitHub's web uploader does not preserve the executable bit. Normalise the
# maintainer scripts and bundled command-line tools before packing the deb.
before-package::
	chmod 755 "$(THEOS_STAGING_DIR)/DEBIAN/postinst" 2>/dev/null || true
	chmod 755 "$(THEOS_STAGING_DIR)/DEBIAN/prerm" 2>/dev/null || true
	chmod 755 "$(THEOS_STAGING_DIR)/usr/libexec/oldtroll/"* 2>/dev/null || true
	mkdir -p "$(THEOS_STAGING_DIR)/usr/libexec/oldtroll/appsync"
	for name in OldTrollAppSync-installd.dylib OldTrollAppSync-installd.plist OldTrollAppSync-FrontBoard.dylib OldTrollAppSync-FrontBoard.plist; do \
		if [ -e "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/$$name" ]; then \
			mv "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/$$name" "$(THEOS_STAGING_DIR)/usr/libexec/oldtroll/appsync/$$name"; \
		fi; \
	done

after-install::
	install.exec "chmod 6755 /usr/bin/oldtroll_helper && killall -9 SpringBoard 2>/dev/null || true"
