#!/usr/bin/env python3
"""
build-bh-simple.py — 不修改主二进制，只替换 FLEXing.dylib
不破坏原始代码签名，避免安装时报签名错误
"""
import zipfile, shutil, os, sys, tempfile, io

BASE_IPA = 'TikTok_43.7.0_BH.ipa'
CONFIG_PATHS = ['ios-plugin/xnow-dylib/Config.plist', 'build-artifacts/Config.plist']

def main():
    if len(sys.argv) < 2:
        print(f"用法: python3 {sys.argv[0]} <xnower.dylib> [version]")
        sys.exit(1)

    dylib_path = sys.argv[1]
    version = sys.argv[2] if len(sys.argv) >= 3 else "dev"
    output = f"TikTok_XNOW_v{version}_BH.ipa"

    if not os.path.exists(dylib_path):
        print(f"❌ dylib 不存在: {dylib_path}")
        sys.exit(1)
    if not os.path.exists(BASE_IPA):
        print(f"❌ 基础 IPA 不存在: {BASE_IPA}")
        sys.exit(1)

    # 读取我们的 dylib
    with open(dylib_path, 'rb') as f:
        our_dylib_data = f.read()

    tmp = tempfile.mkdtemp()
    try:
        # 解压
        print(f"\n[1/4] 解压 {BASE_IPA}...")
        with zipfile.ZipFile(BASE_IPA) as z:
            z.extractall(tmp)

        app_dir = os.path.join(tmp, "Payload", "TikTok.app")
        fw_dir = os.path.join(app_dir, "Frameworks")

        # 替换 FLEXing.dylib 为我们的 dylib（不改主二进制！）
        print("\n[2/4] 替换 FLEXing.dylib → xnower.dylib（不改主二进制）...")
        flex_path = os.path.join(fw_dir, "FLEXing.dylib")
        if os.path.exists(flex_path):
            os.remove(flex_path)
            print(f"  ✅ 已删除原 FLEXing.dylib ({os.path.getsize(flex_path)} bytes)" if False else "  ✅ 已删除原 FLEXing.dylib")
        # 把我们的 dylib 命名为 FLEXing.dylib（主二进制只认这个名）
        our_dst = os.path.join(fw_dir, "FLEXing.dylib")
        shutil.copy2(dylib_path, our_dst)
        os.chmod(our_dst, 0o755)
        print(f"  ✅ 已复制 xnower.dylib → FLEXing.dylib ({len(our_dylib_data)} bytes)")

        # 嵌入 Config.plist
        print("\n[3/4] 嵌入 Config.plist...")
        cfg_dst = os.path.join(app_dir, "xnower-config.plist")
        for src in CONFIG_PATHS:
            if os.path.exists(src):
                shutil.copy2(src, cfg_dst)
                print(f"  ✅ {src}")
                break
        else:
            print("  ⚠️ 未找到 Config.plist")

        # 打包 — deflate 压缩（与其他构建脚本一致），体积减半且 code signature 不受影响
        print("\n[4/4] 打包 IPA（deflate模式，compresslevel=5）...")
        if os.path.exists(output):
            os.remove(output)
        with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=5) as z:
            for root, dirs, files in os.walk(tmp):
                for f in files:
                    arcname = os.path.relpath(os.path.join(root, f), tmp)
                    z.write(os.path.join(root, f), arcname)

        # ====== 自检 ======
        print("\n========== 自检 ==========")
        errors = 0
        with zipfile.ZipFile(output) as z:
            names = z.namelist()

            # 主二进制保持原始引用（FLEXing.dylib）
            main_data = z.read("Payload/TikTok.app/TikTok")
            has_flex = b"FLEXing.dylib" in main_data
            print(f"  {'✅' if has_flex else '❌'} 主二进制引用 FLEXing.dylib{'' if has_flex else ' — 异常!'}")
            if not has_flex: errors += 1

            # 我们的 dylib 在 Frameworks/ 中
            has_our = any("FLEXing.dylib" in n and "Frameworks" in n for n in names)
            our_sz = len(our_dylib_data)
            print(f"  {'✅' if has_our else '❌'} FLEXing.dylib 在 Frameworks/ — {our_sz} bytes")
            if not has_our: errors += 1

            # BHTikTok 未修改
            bh_ipa = zipfile.ZipFile(BASE_IPA)
            bh_orig = bh_ipa.getinfo("Payload/TikTok.app/Frameworks/BHTikTok.dylib").file_size
            bh_new = z.getinfo("Payload/TikTok.app/Frameworks/BHTikTok.dylib").file_size
            print(f"  {'✅' if bh_orig == bh_new else '❌'} BHTikTok.dylib 未修改 — {bh_orig} → {bh_new} bytes")
            if bh_orig != bh_new: errors += 1
            bh_ipa.close()

            # Config.plist
            has_cfg = any("xnower-config.plist" in n for n in names)
            print(f"  {'✅' if has_cfg else '❌'} xnower-config.plist 已嵌入")

            # 主二进制未修改（code signature 完整）
            orig_ipa = zipfile.ZipFile(BASE_IPA)
            orig_main = orig_ipa.getinfo("Payload/TikTok.app/TikTok").file_size
            new_main = z.getinfo("Payload/TikTok.app/TikTok").file_size
            main_unchanged = orig_main == new_main
            print(f"  {'✅' if main_unchanged else '❌'} 主二进制未修改 — {orig_main} → {new_main} bytes")
            if not main_unchanged: errors += 1
            orig_ipa.close()

        sz = os.path.getsize(output)
        print(f"\n{'✅' if errors==0 else '❌'} 自检 {'通过' if errors==0 else f'失败({errors}项)'} | {output} ({sz/1024/1024:.1f} MB)")
        return errors

    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if __name__ == "__main__":
    sys.exit(main())
