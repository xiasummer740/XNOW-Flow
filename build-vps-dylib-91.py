#!/usr/bin/env python3
"""build-vps-dylib-91.py — VPS 交叉编译 xnower.dylib（v1.4.91）
v1.4.91 修复：评论区 overlay 打开后无关闭机制 → 设备困死在评论区。
新增 close_overlay 命令 + _closeCommentPanel（点右上角 X 关面板）+ _gotoHomeFeed 自动先关 overlay。
复用 v1.4.90 流程；密码从 .env.local 读。
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

# 2. Fix XNWindowHelper.h（scene-based 取 keyWindow，同 vps-build-xnower.py）
print("[2] Fix XNWindowHelper.h...")
sftp = ssh.open_sftp()
sftp.put(os.path.join(PROJECT, '.tmp-fix_xn.py'), f"{REMOTE}/fix_xn.py")
sftp.close()
run(f"cd {REMOTE} && python3 fix_xn.py", 30)

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
        f"-framework WebKit -framework Security -framework Photos "
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
local_dir = os.path.join(PROJECT, 'build-artifacts-ci', 'xnower-91')
os.makedirs(local_dir, exist_ok=True)
local_dylib = os.path.join(local_dir, 'xnower.dylib')
sftp = ssh.open_sftp()
sftp.get(f"{REMOTE}/xnower.dylib", local_dylib)
sftp.close()
print(f"  ✅ {local_dylib} ({os.path.getsize(local_dylib)} bytes)")
ssh.close()
print("=== Done ===")
