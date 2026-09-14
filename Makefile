ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
INSTALL_TARGET_PROCESSES = YouTube

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DeArrow

DeArrow_FILES = $(shell find sources -name "*.x*" -o -name "*.m*")
DeArrow_FRAMEWORKS = UIKit Foundation
DEARROW_VERSION := $(shell sed -n 's/^Version: //p' control)
DeArrow_CFLAGS = -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-objc-method-access -fobjc-arc -Iheaders -DPACKAGE_VERSION='@"$(DEARROW_VERSION)"'

include $(THEOS_MAKE_PATH)/tweak.mk

.PHONY: test verify-architecture release-dry-run

test:
	go test ./...

verify-architecture:
	go run ./scripts/dearrow-tools verify-architecture

release-dry-run:
	go run ./scripts/dearrow-tools release-dry-run
