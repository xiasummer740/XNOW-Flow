SDK ?= $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)
MIN_IOS ?= 14.0
ARCH ?= arm64
CC = $(shell xcrun --sdk iphoneos --find clang 2>/dev/null)
LD = $(shell xcrun --sdk iphoneos --find ld 2>/dev/null)

CFLAGS = -arch $(ARCH) -isysroot $(SDK) -miphoneos-version-min=$(MIN_IOS) \
         -fobjc-arc -O2 -Wall -Wextra \
         -Wno-unused-parameter -Wno-deprecated-declarations \
         -Wno-objc-designated-initializers -DNDEBUG

FRAMEWORKS = -framework Foundation -framework UIKit \
             -framework CoreGraphics -framework CFNetwork -framework WebKit

SRCS = XNOWER.m WsClient.m CommandEngine.m DeviceStatus.m \
       TikTokHooks.m XNFloatingPanel.m AccountManager.m
OBJS = $(SRCS:.m=.o)
OUTPUT = xnower.dylib
BUILD_DIR = build

.PHONY: all dylib objects clean info

all: dylib

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Compile .m to .o with -c flag (no linking)
objects: $(BUILD_DIR) $(SRCS)
	$(CC) -c $(CFLAGS) $(SRCS)

# Link with explicit NO-CHAINED-FIXUPS attempt
$(BUILD_DIR)/$(OUTPUT): $(BUILD_DIR) objects Config.plist
	@echo "=== Linking (trying classic ld64 approach) ==="
	# Try linking with ldid-classic or no_chained_fixups via various methods
	$(CC) -dynamiclib $(CFLAGS) \
		-Xlinker -no_chained_fixups \
		-o $(BUILD_DIR)/$(OUTPUT) \
		*.o $(FRAMEWORKS) \
		-install_name @executable_path/Frameworks/$(OUTPUT) \
		2>/dev/null || \
	$(CC) -dynamiclib $(CFLAGS) \
		-Wl,-no_chained_fixups \
		-o $(BUILD_DIR)/$(OUTPUT) \
		*.o $(FRAMEWORKS) \
		-install_name @executable_path/Frameworks/$(OUTPUT) \
		2>/dev/null || \
	$(CC) -dynamiclib $(CFLAGS) \
		-o $(BUILD_DIR)/$(OUTPUT) \
		*.o $(FRAMEWORKS) \
		-install_name @executable_path/Frameworks/$(OUTPUT) \
		-Wl,-no_fixup_chains \
		2>/dev/null || \
	$(CC) -dynamiclib $(CFLAGS) \
		-o $(BUILD_DIR)/$(OUTPUT) \
		*.o $(FRAMEWORKS) \
		-install_name @executable_path/Frameworks/$(OUTPUT)
	@echo "=== Build complete ==="
	@file $(BUILD_DIR)/$(OUTPUT)
	@echo "Size: $$(wc -c < $(BUILD_DIR)/$(OUTPUT)) bytes"
	-cp Config.plist $(BUILD_DIR)/xnower-config.plist
	python3 ../scripts/strip-chained-fixups.py $(BUILD_DIR)/$(OUTPUT)

clean:
	rm -rf $(BUILD_DIR) *.o
