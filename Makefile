APPLICATION_NAME = PebbleActivator

PebbleActivator_FILES = main.m
PebbleActivator_FRAMEWORKS = UIKit MobileCoreServices StoreKit PebbleKit PebbleVendor ExternalAccessory CoreGraphics CoreMotion CoreBluetooth MessageUI
PebbleActivator_LIBRARIES = activator z
PebbleActivator_CFLAGS = -F./  -std=c99
PebbleActivator_LDFLAGS = -F./ -ObjC -dead_strip

TARGET = :clang
TARGET_IPHONEOS_DEPLOYMENT_VERSION := 5.0

ARCHS = armv7

include framework/makefiles/common.mk
include framework/makefiles/application.mk

activator/build/activator.pbw: activator/src/activator.c
	( cd activator; ./waf build )

internal-stage:: activator/build/activator.pbw
	$(ECHO_NOTHING)rsync -a activator/build/activator.pbw $(THEOS_STAGING_DIR)/Applications/PebbleActivator.app/ $(FW_RSYNC_EXCLUDES)$(ECHO_END)

internal-after-install::
	install.exec "killall -9 PebbleActivator || true; sleep 1; activator activate cmd com.apple.rpetrich.pebbleactivator"

clean::
	( cd activator; ./waf clean )
