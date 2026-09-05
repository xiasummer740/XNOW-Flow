"""build-vps-dylib-149.py — VPS 交叉编译 xnower.dylib（v1.4.149）
v1.4.149 = 148 全量验证暴露的 2 项修复（2026-09-05）：
  A4 账号池同步：backup_account 成功后主动上报 status(current_account) →
    XNURLProtocol sendMessage（带 X-Device-Secret 直连 POST /ws/{device_id}，poll 同款可达通道，
    148 起 HTTP poll 模式 heartbeat/wsClientDidConnect 从不触发）→ 后端 _upsert_account。
  open_tab 非 home tab 假成功盲区：profile/inbox/friends class_no_match → acc_id_tap/坐标触摸
    撞触摸墙 → 无条件 success。改为触摸兜底标 reached=NO → handler 诚实返回 status=failed；
    class_no_match 时枚举 dump tab bar 真实 VC 类名（取证下版直切）。home 路径不动。
  继承 148 全部（follow 方向 D / cookie_dump / net_like）。
  磁盘清理：编译完即清 VPS REMOTE 残留（祥哥要求 VPS 不占太多磁盘）。
"""
import paramiko, os, sys

HOST = '192.129.210.52'
USER = 'root'
REMOTE = '/root/xnow-build'
SDK = '/opt/theos/sdks/iPhoneOS16.5.sdk'
LD = '/usr/lib/llvm-16/bin/ld64.lld'
VERSION = "149"
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

# 0. Clean remote build dir（防残留兜底）
print("[0] Clean remote build dir...")
run(f"rm -rf {REMOTE}/*", 30)

# 1. Upload sources
print("[1] Upload sources...")
sftp = ssh.open_sftp()
src_dir = os.path.join(PROJECT, 'ios-plugin', 'xnow-dylib')
run(f"mkdir -p {REMOTE}", 30)
for f in os.listdir(src_dir):
    if f.endswith(('.m', '.h', '.c', '.plist')):
        sftp.put(os.path.join(src_dir, f), f"{REMOTE}/{f}")
sftp.close()
print("  uploaded")

# 2. Compile all .m except MinimalTester
print("[2] Compile...")
CFLAGS = f"-target arm64-apple-ios16.5 -isysroot {SDK} -fobjc-arc -O2 -Wno-everything -DNDEBUG -c"
SRCS = sorted([f for f in os.listdir(src_dir)
               if f.endswith('.m') and f != 'MinimalTester.m'] +
              [f for f in os.listdir(src_dir) if f.endswith('.c')])
failed = False
for src in SRCS:
    obj = src.rsplit('.', 1)[0] + '.o'
    out, ec = run(f"cd {REMOTE} && clang-16 {CFLAGS} {src} -o {obj} 2>&1", 120)
    ok = 'error:' not in out.lower() and ec == 0
    print(f"  {'OK' if ok else 'FAIL'}: {src}")
    if not ok: failed = True
if failed:
    print("❌ 编译失败"); sys.exit(1)

# 3. Link
print("[3] Link...")
OBJS = ' '.join([s.rsplit('.', 1)[0] + '.o' for s in SRCS])
LINK = (f"cd {REMOTE} && {LD} -arch arm64 -dylib -platform_version ios 16.5 16.5 "
        f"-o xnower.dylib {OBJS} -lSystem -lobjc -framework Foundation -framework UIKit "
        f"-framework CoreGraphics -framework QuartzCore -framework CFNetwork "
        f"-framework WebKit -framework Security -framework Photos -framework AVFoundation "
        f"-framework IOKit "
        f"-syslibroot {SDK} -install_name @executable_path/Frameworks/xnower.dylib")
out, ec = run(LINK, 120)
if ec != 0:
    print("❌ 链接失败"); sys.exit(1)

# 4. Convert private cmds -> standard
print("[4] Convert private cmds...")
sftp = ssh.open_sftp()
sftp.put(os.path.join(PROJECT, '.tmp-convert_cmds.py'), f"{REMOTE}/convert_cmds.py")
sftp.close()
run(f"cd {REMOTE} && python3 convert_cmds.py", 30)

# 5. Download
print("[5] Download...")
local_dir = os.path.join(PROJECT, 'build-artifacts-ci', f'xnower-{VERSION}')
os.makedirs(local_dir, exist_ok=True)
local_dylib = os.path.join(local_dir, 'xnower.dylib')
sftp = ssh.open_sftp()
sftp.get(f"{REMOTE}/xnower.dylib", local_dylib)
sftp.close()
print(f"  ✅ {local_dylib} ({os.path.getsize(local_dylib)} bytes)")

# 6. Clean VPS build dir（祥哥要求：不占太多 VPS 磁盘）
print("[6] Clean VPS build dir...")
run(f"rm -rf {REMOTE}", 30)
ssh.close()
print("=== Done ===")
