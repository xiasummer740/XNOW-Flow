#!/usr/bin/env python3
"""build-vps-dylib-117.py — VPS 交叉编译 xnower.dylib（v1.4.117）
v1.4.117 = 备份账号国家不显示修复（祥哥 2026-08-19 反馈「Outshine/@outshine83 显示了但国家没用」）：
  ① _extractCountryFromDict 多键位提取：region/country/display_region/country_code/
    region_code/ip_location/location/area + 类型安全（NSNull/非字符串跳过）。
  ② 同 uid 多缓存择优 _betterCandidate：带国家的 > 资料分高的（仅 uid 已匹配的同账号，
    不误选他人）；无 uid 兜底仍按完整度（防误抓视频作者）。
  ③ 备份成功也上报证据：命中 dict 顶层 key 名 + 提取国家（不含值）→ server.log 可核实
    国家是否提取到/真实字段名，据此精准修复不盲猜。
  ④ 面板国家 code→中文名显示（_countryDisplayName），未知 code 原样显示。
沿用 v1.4.116：深度递归 + uid_tt 消歧 + dump_login 诊断 + 失败自诊断。
沿用 v1.4.93：源码即产物 + XNWindowHelper.h 好版本自检。
"""
import paramiko, os, sys

HOST = '192.129.210.52'
USER = 'root'
REMOTE = '/root/xnow-build'
SDK = '/opt/theos/sdks/iPhoneOS16.5.sdk'
LD = '/usr/lib/llvm-16/bin/ld64.lld'
PROJECT = os.path.dirname(os.path.abspath(__file__))

def _load_env():
    env = {}
    with open(os.path.join(PROJECT, '.env.local'), encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, _, v = line.partition('=')
                env[k.strip()] = v.strip()
    return env

PWD = _load_env().get('XNW_VPS_PASSWORD', '')
if not PWD:
    print('❌ 未读到 XNW_VPS_PASSWORD'); sys.exit(1)

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(HOST, 22, USER, PWD, timeout=15)

def run(cmd, timeout=180):
    _, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    ec = stdout.channel.recv_exit_status()
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')
    tail = '\n'.join(out.strip().split('\n')[-12:])
    if tail.strip():
        print(f"  {tail}")
    if err.strip() and ec != 0:
        for line in err.strip().split('\n')[-6:]:
            print(f"  ERR: {line}")
    return out, ec

# 1. Upload sources
print("[1] Upload sources...")
sftp = ssh.open_sftp()
src_dir = os.path.join(PROJECT, 'ios-plugin', 'xnow-dylib')
run(f"mkdir -p {REMOTE}", 30)
for f in os.listdir(src_dir):
    if f.endswith(('.m', '.h', '.plist')):
        sftp.put(os.path.join(src_dir, f), f"{REMOTE}/{f}")
sftp.close()
print("  uploaded")

# 2. Guard: 确认 VPS 上 XNWindowHelper.h 是好版本（源码即产物）
print("[2] Guard XNWindowHelper.h (好版本自检)...")
out, ec = run(f"grep -c 'XN_IS_OVERLAY' {REMOTE}/XNWindowHelper.h", 30)
ok_good = out.strip() != '0'
out, ec = run(f"grep -c 'isKeyWindow) return w' {REMOTE}/XNWindowHelper.h", 30)
ok_notbad = out.strip() == '0'
if not (ok_good and ok_notbad):
    print(f"  ❌ XNWindowHelper.h 不是好版本 (好版本={ok_good}, 坏特征串存在={not ok_notbad})")
    sys.exit(1)
print("  ✅ 好版本确认（源码即产物）")

# 3. Compile all .m except MinimalTester
print("[3] Compile...")
CFLAGS = f"-target arm64-apple-ios16.5 -isysroot {SDK} -fobjc-arc -O2 -Wno-everything -DNDEBUG -c"
SRCS = sorted([f for f in os.listdir(src_dir) if f.endswith('.m') and f != 'MinimalTester.m'])
failed = False
for src in SRCS:
    obj = src.replace('.m', '.o')
    out, ec = run(f"cd {REMOTE} && clang-16 {CFLAGS} {src} -o {obj} 2>&1", 120)
    ok = 'error:' not in out.lower() and ec == 0
    print(f"  {'OK' if ok else 'FAIL'}: {src}")
    if not ok: failed = True
if failed:
    print("❌ 编译失败"); sys.exit(1)

# 4. Link
print("[4] Link...")
OBJS = ' '.join([s.replace('.m', '.o') for s in SRCS])
LINK = (f"cd {REMOTE} && {LD} -arch arm64 -dylib -platform_version ios 16.5 16.5 "
        f"-o xnower.dylib {OBJS} -lSystem -lobjc -framework Foundation -framework UIKit "
        f"-framework CoreGraphics -framework QuartzCore -framework CFNetwork "
        f"-framework WebKit -framework Security -framework Photos -framework AVFoundation "
        f"-framework IOKit "
        f"-syslibroot {SDK} -install_name @executable_path/Frameworks/xnower.dylib")
out, ec = run(LINK, 120)
if ec != 0:
    print("❌ 链接失败"); sys.exit(1)

# 5. Convert private cmds -> standard
print("[5] Convert private cmds...")
sftp = ssh.open_sftp()
sftp.put(os.path.join(PROJECT, '.tmp-convert_cmds.py'), f"{REMOTE}/convert_cmds.py")
sftp.close()
run(f"cd {REMOTE} && python3 convert_cmds.py", 30)

# 6. Download
print("[6] Download...")
local_dir = os.path.join(PROJECT, 'build-artifacts-ci', 'xnower-117')
os.makedirs(local_dir, exist_ok=True)
local_dylib = os.path.join(local_dir, 'xnower.dylib')
sftp = ssh.open_sftp()
sftp.get(f"{REMOTE}/xnower.dylib", local_dylib)
sftp.close()
print(f"  ✅ {local_dylib} ({os.path.getsize(local_dylib)} bytes)")
ssh.close()
print("=== Done ===")
