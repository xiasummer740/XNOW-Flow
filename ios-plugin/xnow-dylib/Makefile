SDK ?= $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
MIN_IOS ?= 14.0
ARCH ?= arm64
CC = $(shell xcrun --sdk iphoneos --find clang 2>/dev/null)

CFLAGS = -arch $(ARCH) -isysroot $(SDK) -miphoneos-version-min=$(MIN_IOS) \
         -fobjc-arc -O2 -Wall -Wextra \
         -Wno-unused-parameter -Wno-deprecated-declarations \
         -Wno-objc-designated-initializers -dynamiclib -DNDEBUG

FRAMEWORKS = -framework Foundation -framework UIKit \
             -framework CoreGraphics -framework CFNetwork -framework WebKit

SRCS = XNOWER.m WsClient.m CommandEngine.m DeviceStatus.m \
       TikTokHooks.m XNFloatingPanel.m AccountManager.m

OUTPUT = xnower.dylib
BUILD_DIR = build

.PHONY: all dylib clean

all: dylib

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/$(OUTPUT): $(BUILD_DIR) $(SRCS) Config.plist
	$(CC) $(CFLAGS) $(FRAMEWORKS) $(SRCS) \
		-o $(BUILD_DIR)/$(OUTPUT) \
		-install_name @executable_path/Frameworks/$(OUTPUT)
	@echo "=== Build Success ==="
	@file $(BUILD_DIR)/$(OUTPUT)
	@echo "Size: $$(wc -c < $(BUILD_DIR)/$(OUTPUT)) bytes"
	-cp Config.plist $(BUILD_DIR)/xnower-config.plist
	@echo "=== Post-process disabled for raw analysis ==="

dylib: $(BUILD_DIR)/$(OUTPUT)

clean:
	rm -rf $(BUILD_DIR)
	@echo "Cleaned"
