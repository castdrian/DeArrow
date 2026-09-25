ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
FINALPACKAGE = 1
INSTALL_TARGET_PROCESSES = YouTube

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DeArrow

DeArrow_FILES = $(shell find sources -name "*.x*" -o -name "*.m*")
DeArrow_FRAMEWORKS = UIKit Foundation ImageIO UserNotifications
DEARROW_VERSION := $(shell sed -n 's/^Version: //p' control)
DeArrow_CFLAGS = -Wno-deprecated-declarations -Wno-nullability-completeness -Wno-objc-method-access -fobjc-arc -Iheaders -DPACKAGE_VERSION='@"$(DEARROW_VERSION)"'

FORMAT_OBJC_FILES := $(shell find headers sources -type f \( -name "*.h" -o -name "*.m" \))
FORMAT_GO_FILES := $(shell find scripts tools -type f -name "*.go")

include $(THEOS_MAKE_PATH)/tweak.mk

.PHONY: test verify-architecture release-dry-run format format-check check

test:
	go test ./...
	go vet ./...
	mkdir -p .theos
	xcrun --sdk macosx clang -fobjc-arc -Iheaders sources/Metadata.m tests/metadata_runtime_test.m -framework Foundation -o .theos/metadata-runtime-test
	.theos/metadata-runtime-test
	xcrun --sdk macosx clang -fobjc-arc -Iheaders sources/HookSupport.m tests/hook_abi_runtime_test.m -framework Foundation -o .theos/hook-abi-runtime-test
	.theos/hook-abi-runtime-test
	xcrun --sdk macosx clang -fobjc-arc -Iheaders sources/ImageSetterSupport.m tests/image_setter_runtime_test.m -framework Foundation -o .theos/image-setter-runtime-test
	.theos/image-setter-runtime-test

verify-architecture:
	go run ./scripts/dearrow-tools verify-architecture

release-dry-run:
	go run ./scripts/dearrow-tools release-dry-run

format:
	clang-format -i $(FORMAT_OBJC_FILES)
	gofmt -w $(FORMAT_GO_FILES)

format-check:
	clang-format --dry-run --Werror --style=file $(FORMAT_OBJC_FILES)
	test -z "$(shell gofmt -l $(FORMAT_GO_FILES))"

check: format-check test verify-architecture release-dry-run
