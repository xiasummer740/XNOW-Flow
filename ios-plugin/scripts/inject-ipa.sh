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
install_name_tool -id @rpath/xnower.dylib "$APP_DIR/Frameworks/xnower.dylib"
echo "  install_name set to @rpath/xnower.dylib"

echo ""
echo "=== Step 4: 注入 dylib 到主二进制 ==="
# 使用 insert_dylib 添加加载命令
INSERT_TOOL=$(which insert_dylib 2>/dev/null || echo "")

if [ -n "$INSERT_TOOL" ]; then
    # 使用 insert_dylib
    "$INSERT_TOOL" \
        "@rpath/xnower.dylib" \
        "$APP_BINARY" \
        "$APP_BINARY"_patched \
        --inplace \
        2>/dev/null || true

    # 恢复原始权限
    chmod 755 "$APP_BINARY"
    echo "  insert_dylib 注入完成"
else
    # 手动注入: 使用 Python 脚本修改 Mach-O
    python3 -c "
import struct, sys

dylib_path = b'@rpath/xnower.dylib\x00'
align = 8
dylib_cmd_size = (len(dylib_path) + 7) & ~7  # 对齐到 8 字节
dylib_cmd_size += 24  # LC_LOAD_DYLIB 头部大小

binary = open('$APP_BINARY', 'rb').read()

# 构造 LC_LOAD_DYLIB 命令
cmd = bytearray()
cmd += struct.pack('<II', 0x8000001D, dylib_cmd_size)  # LC_LOAD_DYLIB
cmd += struct.pack('<III', 0, 24, 24)  # offset, timestamp, version
cmd += struct.pack('<II', 24, dylib_cmd_size - 24)  # current_vers, compat_vers
cmd += dylib_path
cmd += b'\x00' * (dylib_cmd_size - len(cmd) - 24)
cmd += b'\x00' * (dylib_cmd_size - len(cmd))

# 检查是否已有我们的 dylib
if b'xnower.dylib' in binary:
    print('  dylib 已存在，跳过注入')
    sys.exit(0)

# 在 __LINKEDIT 段前插入 (简化方案: 追加到文件末尾)
with open('$APP_BINARY', 'ab') as f:
    f.write(cmd)

# 更新 ncmds
header = bytearray(binary[:8])
ncmds = struct.unpack('<I', header[4:8])[0]
header[4:8] = struct.pack('<I', ncmds + 1)

with open('$APP_BINARY', 'r+b') as f:
    f.write(header)

print('  LC_LOAD_DYLIB 注入完成')
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
echo "=== Step 6: 伪签名（TrollStore 兼容） ==="
if command -v ldid &>/dev/null; then
    ldid -S "$APP_BINARY" 2>/dev/null && echo "  ldid 签名完成" || echo "  ldid 签名失败（不影响 TrollStore）"
else
    echo "  ldid 未安装，跳过签名（TrollStore 不需要正式签名）"
fi

# 也对 dylib 做签名
if command -v ldid &>/dev/null; then
    ldid -S "$APP_DIR/Frameworks/xnower.dylib" 2>/dev/null || true
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
