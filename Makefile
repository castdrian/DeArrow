ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
INSTALL_TARGET_PROCESSES = YouTube

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DeArrow

DeArrow_FILES = Tweak.x NodeIntegration.m IntegrationSupport.m Metadata.m BrandingRecord.m BrandingClient.m Preferences.m TitleIntegration.m ThumbnailIntegration.m SettingsIntegration.m SettingsViewController.m
DeArrow_FRAMEWORKS = UIKit Foundation
PACKAGE_VERSION := $(shell grep '^Version:' control | cut -d' ' -f2)
DeArrow_CFLAGS = -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-objc-method-access -fobjc-arc -DPACKAGE_VERSION='@"$(PACKAGE_VERSION)"'

include $(THEOS_MAKE_PATH)/tweak.mk
