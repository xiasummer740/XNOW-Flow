#!/bin/bash
# inject-ipa.sh — 将 xnower.dylib 注入到 TikTok IPA
# 用法: ./inject-ipa.sh <输入IPA> <dylib路径> <输出IPA>
#
# 依赖: unzip, zip, install_name_tool (macOS), ldid (可选)
# 在 GitHub Actions macOS runner 上运行

set -euo pipefail

if [ $# -lt 3 ]; then
    echo "用法: $0 <输入IPA> <dylib路径> <输出IPA>"
    echo "示例: $0 TikTok.ipa xnower.dylib TikTok_XNOW.ipa"
    exit 1
fi

INPUT_IPA="$1"
DYLIB_PATH="$2"
OUTPUT_IPA="$3"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "=== Step 1: 解压 IPA ==="
unzip -q "$INPUT_IPA" -d "$TMPDIR/extracted"
PAYLOAD="$TMPDIR/extracted/Payload"

# 找到 .app 目录
APP_DIR=$(find "$PAYLOAD" -name "*.app" -type d | head -1)
if [ -z "$APP_DIR" ]; then
    echo "错误: 在 Payload 中未找到 .app 目录"
    exit 1
fi
echo "  App 路径: $APP_DIR"

# 找到主二进制
APP_BINARY=$(find "$APP_DIR" -maxdepth 1 -type f \
    | file -f - 2>/dev/null \
    | grep "Mach-O" \
    | cut -d: -f1 \
    | head -1)

if [ -z "$APP_BINARY" ]; then
    # 回退: 使用和 .app 同名的文件
    APP_NAME=$(basename "$APP_DIR" .app)
    APP_BINARY="$APP_DIR/$APP_NAME"
fi
echo "  主二进制: $(basename "$APP_BINARY")"

echo ""
echo "=== Step 2: 复制 dylib 到 Frameworks ==="
mkdir -p "$APP_DIR/Frameworks"
cp "$DYLIB_PATH" "$APP_DIR/Frameworks/xnower.dylib"
chmod 755 "$APP_DIR/Frameworks/xnower.dylib"
echo "  Copied to Frameworks/xnower.dylib"

echo ""
echo "=== Step 3: 修改加载路径 ==="
# 使用 @executable_path/Frameworks/ 确保 dyld 能找到 dylib
# @rpath 需要主二进制有正确的 runpath，而 @executable_path 是绝对的
install_name_tool -id @executable_path/Frameworks/xnower.dylib "$APP_DIR/Frameworks/xnower.dylib"
echo "  install_name set to @executable_path/Frameworks/xnower.dylib"

echo ""
echo "=== Step 4: 注入 dylib 到主二进制 ==="
# 使用 insert_dylib 添加加载命令
INSERT_TOOL=$(which insert_dylib 2>/dev/null || echo "")

if [ -n "$INSERT_TOOL" ]; then
    echo "  使用 insert_dylib 注入..."
    # 先备份原始二进制
    cp "$APP_BINARY" "$APP_BINARY.bak"
    if "$INSERT_TOOL" \
        "@executable_path/Frameworks/xnower.dylib" \
        "$APP_BINARY" \
        "$APP_BINARY"_patched \
        --inplace \
        --overwrite; then
        chmod 755 "$APP_BINARY"
        echo "  insert_dylib 注入完成"
    else
        echo "  insert_dylib 失败，切换到 Python 注入"
        cp "$APP_BINARY.bak" "$APP_BINARY"
        USE_PYTHON=1
    fi
    rm -f "$APP_BINARY.bak"
fi

if [ -z "$INSERT_TOOL" ] || [ "${USE_PYTHON:-0}" = "1" ]; then
    # 手动注入: 使用 Python 脚本修改 Mach-O
    # 注意: 对于 FAT 二进制（多架构），需要分别处理每个 slice
    python3 -c "
import struct, sys, os

dylib_path = b'@executable_path/Frameworks/xnower.dylib\x00'
align = 8
dylib_cmd_size = (len(dylib_path) + 7) & ~7  # 对齐到 8 字节
dylib_cmd_size += 24  # LC_LOAD_DYLIB 头部大小 (cmd+cmdsize+4个uint32)

binary_path = '$APP_BINARY'
binary = open(binary_path, 'rb').read()

# 检查是否已有我们的 dylib
if b'xnower.dylib' in binary:
    print('  dylib 已存在，跳过注入')
    sys.exit(0)

# 判断 Mach-O 类型
magic = struct.unpack('<I', binary[:4])[0]
MH_MAGIC_64 = 0xFEEDFACF
MH_MAGIC = 0xFEEDFACE
FAT_MAGIC = 0xBEBAFECA
FAT_MAGIC_64 = 0xBEBAFECB

if magic == FAT_MAGIC or magic == FAT_MAGIC_64:
    print('  FAT binary detected, patching first slice (arm64)')
    # FAT header: magic(4) + nfat_arch(4)
    arch_offset = 8
    # arm64 slice 偏移
    arch_count = struct.unpack('<I', binary[4:8])[0]
    if arch_count < 1:
        print('  ERROR: no arch in FAT binary')
        sys.exit(1)
    # 读第一个 arch 的偏移
    if magic == FAT_MAGIC_64:
        slice_off = struct.unpack('<Q', binary[arch_offset + 8:arch_offset + 16])[0]
    else:
        slice_off = struct.unpack('<I', binary[arch_offset + 8:arch_offset + 12])[0]
    # 读取该 slice 的 mach_header_64
    slice_header = binary[slice_off:slice_off + 32]
else:
    slice_off = 0
    slice_header = binary[:32]

if magic != FAT_MAGIC and magic != FAT_MAGIC_64 and magic != MH_MAGIC_64:
    print('  WARNING: expected arm64 Mach-O, trying as MH_MAGIC_64 anyway')

# 解析 mach_header_64
# offset: 0=magic, 4=cputype, 8=cpusubtype, 12=filetype,
#         16=ncmds, 20=sizeofcmds, 24=flags, 28=reserved
ncmds = struct.unpack('<I', slice_header[16:20])[0]
sizeofcmds = struct.unpack('<I', slice_header[20:24])[0]

print('  ncmds: {}, sizeofcmds: {}, cmd_size: {}'.format(ncmds, sizeofcmds, dylib_cmd_size))

# 构造 LC_LOAD_DYLIB 命令
cmd = bytearray()
cmd += struct.pack('<II', 0x8000001D, dylib_cmd_size)  # LC_LOAD_DYLIB
cmd += struct.pack('<III', 0, 24, 24)  # offset(拉伸后进行), timestamp, version
cmd += struct.pack('<II', 24, dylib_cmd_size - 24)  # current_vers, compat_vers
cmd += dylib_path
cmd += b'\x00' * (dylib_cmd_size - len(cmd))

# 追加到文件末尾
with open(binary_path, 'ab') as f:
    f.write(cmd)

# 更新 mach_header_64 在同一切片的偏移
new_ncmds = ncmds + 1
new_sizeofcmds = sizeofcmds + dylib_cmd_size

with open(binary_path, 'r+b') as f:
    if slice_off == 0:
        # 非 FAT: 直接更新文件开头
        f.seek(0)
    else:
        f.seek(slice_off)
    f.write(struct.pack('<II', new_ncmds, new_sizeofcmds))

print('  LC_LOAD_DYLIB 注入完成 (ncmds: {} -> {}, sizeofcmds: {} -> {})'.format(
    ncmds, new_ncmds, sizeofcmds, new_sizeofcmds))
"
fi

echo ""
echo "=== Step 5: 嵌入配置 ==="
# 复制配置 plist（可被 NSUserDefaults 读取）
CONFIG_PLIST_DIR="$(dirname "$DYLIB_PATH")/../xnower-config.plist"
if [ -f "$CONFIG_PLIST_DIR" ]; then
    cp "$CONFIG_PLIST_DIR" "$APP_DIR/xnower-config.plist"
    echo "  Config plist embedded"
elif [ -f "ios-plugin/xnow-dylib/Config.plist" ]; then
    cp "ios-plugin/xnow-dylib/Config.plist" "$APP_DIR/xnower-config.plist"
    echo "  Config plist embedded (from source)"
else
    echo "  No config plist found, using defaults"
fi

echo ""
echo "=== Step 6: 代码签名 ==="
# 优先用 codesign（macOS 原生，适用于企业证书/开发证书）
if command -v codesign &>/dev/null; then
    # 为 dylib 生成简单的 entitlements
    echo '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>get-task-allow</key><true/></dict></plist>' > "$TMPDIR/entitlements.plist"

    echo "  Signing main binary with codesign..."
    codesign -f -s - --entitlements "$TMPDIR/entitlements.plist" "$APP_BINARY" 2>/dev/null && \
        echo "  ✅ 主二进制签名完成" || echo "  ⚠️ 主二进制签名失败"

    echo "  Signing dylib with codesign..."
    codesign -f -s - --entitlements "$TMPDIR/entitlements.plist" "$APP_DIR/Frameworks/xnower.dylib" 2>/dev/null && \
        echo "  ✅ dylib 签名完成" || echo "  ⚠️ dylib 签名失败"
elif command -v ldid &>/dev/null; then
    echo "  使用 ldid 伪签名（TrollStore 兼容）..."
    ldid -S "$APP_BINARY" 2>/dev/null && echo "  ✅ ldid 主二进制签名完成" || echo "  ⚠️ ldid 主二进制签名失败"
    ldid -S "$APP_DIR/Frameworks/xnower.dylib" 2>/dev/null && echo "  ✅ ldid dylib 签名完成" || echo "  ⚠️ ldid dylib 签名失败"
else
    echo "  ⚠️ 未找到签名工具 — 仅适用于 TrollStore 安装（无需正式签名）"
    echo "  对于企业证书签名，请使用 爱思助手/i4Tools 打包时自动签名"
fi

echo ""
echo "=== Step 7: 打包 IPA ==="
cd "$TMPDIR/extracted"
zip -qr "$OUTPUT_IPA" Payload/
echo "  输出 IPA: $OUTPUT_IPA"

echo ""
echo "=== 完成 ==="
echo "文件大小: $(ls -lh "$OUTPUT_IPA" | awk '{print $5}')"
echo "现在可以用 TrollStore 安装 $OUTPUT_IPA"
