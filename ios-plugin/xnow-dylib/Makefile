# Makefile — XNOW iOS dylib
# 在 macOS 上用 clang 编译注入 TikTok 的 dylib
# 用法: make dylib (编译 dylib)
#       make release (编译 + 裁剪 + 伪签名)
#       make clean (清理)

SDK ?= $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
MIN_IOS ?= 14.0
ARCH ?= arm64
CC = $(shell xcrun --sdk iphoneos --find clang 2>/dev/null)

CFLAGS = -arch $(ARCH) \
         -isysroot $(SDK) \
         -miphoneos-version-min=$(MIN_IOS) \
         -fobjc-arc \
         -O2 \
         -Wall \
         -Wextra \
         -Wno-unused-parameter \
         -Wno-deprecated-declarations \
         -Wno-objc-designated-initializers \
         -dynamiclib \
         -DNDEBUG

# iOS 16 兼容: 需用 Xcode 14 编译（不启用链式 fixup）
# Xcode 15+ 默认启用链式 fixup，iOS 16 重签后 dyld 不兼容
# 工作流已设置 DEVELOPER_DIR 指向 Xcode 14.3.1

FRAMEWORKS = -framework Foundation \
             -framework UIKit \
             -framework CoreGraphics \
             -framework CFNetwork \
             -framework WebKit

SRCS = XNOWER.m \
       WsClient.m \
       CommandEngine.m \
       DeviceStatus.m \
       TikTokHooks.m \
       XNFloatingPanel.m \
       AccountManager.m

OUTPUT = xnower.dylib
BUILD_DIR = build

.PHONY: all dylib release strip sign clean info

all: dylib

dylib: $(BUILD_DIR)/$(OUTPUT)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/$(OUTPUT): $(BUILD_DIR) $(SRCS) Config.plist
	$(CC) $(CFLAGS) $(LDFLAGS) $(FRAMEWORKS) $(SRCS) \
		-o $(BUILD_DIR)/$(OUTPUT) \
		-install_name @rpath/$(OUTPUT)
	@echo ""
	@echo "=== Build Success ==="
	@file $(BUILD_DIR)/$(OUTPUT)
	@echo "Size: $$(wc -c < $(BUILD_DIR)/$(OUTPUT)) bytes"
	# 复制配置 plist 到产物目录
	cp Config.plist $(BUILD_DIR)/xnower-config.plist

# 去除调试符号
strip: $(BUILD_DIR)/$(OUTPUT)
	strip -S $(BUILD_DIR)/$(OUTPUT)
	@echo "Stripped: $$(wc -c < $(BUILD_DIR)/$(OUTPUT)) bytes"

# 伪签名（TrollStore 需要 ldid）
sign: $(BUILD_DIR)/$(OUTPUT)
	@if command -v ldid &>/dev/null; then \
		ldid -S $(BUILD_DIR)/$(OUTPUT) && echo "ldid sign OK"; \
	else \
		echo "ldid not installed, skip fake-sign"; \
	fi

release: dylib strip sign
	@echo "=== Release ready: $(BUILD_DIR)/$(OUTPUT) ==="

clean:
	rm -rf $(BUILD_DIR)
	@echo "Cleaned"

info:
	@echo "SDK:  $(SDK)"
	@echo "CC:   $(CC)"
	@echo "Arch: $(ARCH)"
	@echo "iOS:  $(MIN_IOS)"
