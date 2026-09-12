ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
INSTALL_TARGET_PROCESSES = YouTube

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DeArrow

DeArrow_FILES = sources/Tweak.x sources/NodeIntegration.m sources/IntegrationSupport.m sources/Metadata.m sources/BrandingRecord.m sources/BrandingClient.m sources/Preferences.m sources/TitleIntegration.m sources/ThumbnailIntegration.m sources/SettingsIntegration.m sources/SettingsViewController.m
DeArrow_FRAMEWORKS = UIKit Foundation
DEARROW_VERSION := $(shell sed -n 's/^Version: //p' control)
DeArrow_CFLAGS = -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-objc-method-access -fobjc-arc -Iheaders -DPACKAGE_VERSION='@"$(DEARROW_VERSION)"'

include $(THEOS_MAKE_PATH)/tweak.mk
