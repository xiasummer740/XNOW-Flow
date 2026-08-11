#!/usr/bin/env python3
"""
build-bh-ipa.py — BH版 IPA 构建脚本（含自检）
用法: python3 build-bh-ipa.py <dylib_path> <version>

步骤:
  1. 解压 TikTok_43.7.0_BH.ipa
  2. Patch 主二进制: FLEXing.dylib → xnower.dylib
  3. 复制 xnower.dylib 到 Frameworks/
  4. 嵌入 Config.plist
  5. 打包并自检

自检项目:
  ✅ 主二进制有 xnower.dylib
  ✅ 主二进制无 FLEXing.dylib
  ✅ BHTikTok.dylib 未修改
  ✅ xnower.dylib 在 Frameworks/ 中
  ✅ Config.plist 已嵌入
"""
import zipfile, shutil, os, sys, tempfile, plistlib

BASE_IPA = 'TikTok_43.7.0_BH.ipa'
CONFIG_PATHS = ['ios-plugin/xnow-dylib/Config.plist', 'build-artifacts/Config.plist']

def check(label, cond, detail=""):
    mark = "✅" if cond else "❌"
    print(f"  {mark} {label}" + (f" — {detail}" if detail else ""))

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

    tmp = tempfile.mkdtemp()
    try:
        # 1. 解压
        print(f"\n[1/5] 解压 {BASE_IPA}...")
        with zipfile.ZipFile(BASE_IPA) as z:
            z.extractall(tmp)

        app_dir = os.path.join(tmp, "Payload", "TikTok.app")
        fw_dir = os.path.join(app_dir, "Frameworks")

        # 2. Patch 主二进制（注意: bytearray.replace 返回新对象，要赋值！）
        print("\n[2/5] Patch 主二进制 (FLEXing.dylib → xnower.dylib)...")
        main_path = os.path.join(app_dir, "TikTok")
        data = open(main_path, "rb").read()
        old_count = data.count(b"FLEXing.dylib")
        if old_count == 0:
            print("  ⚠️ 未找到 FLEXing.dylib，可能已 patch 过")
        else:
            data = data.replace(b"FLEXing.dylib", b"xnower.dylib\x00")
            open(main_path, "wb").write(data)
            print(f"  ✅ 已替换 {old_count} 处")

        # 3. 复制 dylib
        print("\n[3/5] 复制 xnower.dylib...")
        os.makedirs(fw_dir, exist_ok=True)
        dst = os.path.join(fw_dir, "xnower.dylib")
        shutil.copy2(dylib_path, dst)
        os.chmod(dst, 0o755)

        # 4. 嵌入 Config.plist
        print("\n[4/5] 嵌入 Config.plist...")
        cfg_dst = os.path.join(app_dir, "xnower-config.plist")
        for src in CONFIG_PATHS:
            if os.path.exists(src):
                shutil.copy2(src, cfg_dst)
                # 写入构建版本号（浮窗主菜单显示用）
                try:
                    with open(cfg_dst, "rb") as cf:
                        cfg = plistlib.load(cf)
                    cfg["XNOWER_BuildVersion"] = version
                    with open(cfg_dst, "wb") as cf:
                        plistlib.dump(cfg, cf)
                    print(f"  ✅ {src} (version={version})")
                except Exception as e:
                    print(f"  ⚠️ 写版本号失败({e})，仍用原配置")
                break
        else:
            print("  ⚠️ 未找到 Config.plist")

        # 5. 打包
        print("\n[5/5] 打包 IPA...")
        if os.path.exists(output):
            os.remove(output)
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=5) as z:
            for root, dirs, files in os.walk(tmp):
                for f in files:
                    z.write(os.path.join(root, f), os.path.relpath(os.path.join(root, f), tmp))

        # ====== 自检 ======
        print("\n========== 自检 ==========")
        errors = 0
        with zipfile.ZipFile(output) as z:
            main_data = z.read("Payload/TikTok.app/TikTok")

            has_xnower = b"xnower.dylib" in main_data
            xnower_pos = main_data.find(b"xnower.dylib")
            check("主二进制包含 xnower.dylib",
                  has_xnower,
                  f"在 0x{xnower_pos:x}" if has_xnower else "")
            if b"xnower.dylib" not in main_data:
                errors += 1

            check("主二进制不含 FLEXing.dylib",
                  b"FLEXing.dylib" not in main_data)
            if b"FLEXing.dylib" in main_data:
                errors += 1

            # BHTikTok 未修改
            bh_ipa = zipfile.ZipFile(BASE_IPA)
            bh_orig = bh_ipa.getinfo("Payload/TikTok.app/Frameworks/BHTikTok.dylib").file_size
            bh_new = z.getinfo("Payload/TikTok.app/Frameworks/BHTikTok.dylib").file_size
            check("BHTikTok.dylib 未修改",
                  bh_orig == bh_new,
                  f"{bh_orig} → {bh_new} bytes")
            if bh_orig != bh_new:
                errors += 1
            bh_ipa.close()

            # xnower.dylib 存在
            xnower_size = z.getinfo("Payload/TikTok.app/Frameworks/xnower.dylib").file_size
            check("xnower.dylib 在 Frameworks/",
                  True,
                  f"{xnower_size} bytes")

            # Config.plist 存在
            check("xnower-config.plist 已嵌入",
                  any("xnower-config.plist" in n.filename for n in z.infolist()))

        sz = os.path.getsize(output)
        print(f"\n{'✅' if errors==0 else '❌'} 自检 {'通过' if errors==0 else f'失败({errors}项)'} | {output} ({sz/1024/1024:.1f} MB)")
        return errors

    finally:
        shutil.rmtree(tmp, ignore_errors=True)

if __name__ == "__main__":
    sys.exit(main())
