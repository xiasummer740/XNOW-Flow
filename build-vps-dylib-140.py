"""build-vps-dylib-140.py — VPS 交叉编译 xnower.dylib（v1.4.140）
v1.4.140 = net_socket 探针：fishhook POSIX socket + TLS 双层钩子抓 TikTok 真实请求明文。
  背景：net_classes 实锤 TikTok 43.7.0 纯 Swift 网络栈（Pumbaa + SwiftNIO），ObjC 层不可 hook。
  SwiftNIO 逃不掉底层 C 函数（connect/send/recv/write + SSL_write/SSL_read），fishhook 全可拦截。
  TLS 层拿到的是解密后明文 → 能看到完整 HTTP 请求（URL/headers/签名参数）。
  本脚本新增：上传/编译支持 .c 文件（fishhook.c）。
"""
import paramiko, os, sys

HOST = '192.129.210.52'
USER = 'root'
REMOTE = '/root/xnow-build'
SDK = '/opt/theos/sdks/iPhoneOS16.5.sdk'
LD = '/usr/lib/llvm-16/bin/ld64.lld'
VERSION = '140'
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
    if f.endswith(('.m', '.h', '.c', '.plist')):  # v1.4.140 加 .c（fishhook.c）
        sftp.put(os.path.join(src_dir, f), f"{REMOTE}/{f}")
sftp.close()
print("  uploaded")

# 2. Compile all .m except MinimalTester
print("[2] Compile...")
CFLAGS = f"-target arm64-apple-ios16.5 -isysroot {SDK} -fobjc-arc -O2 -Wno-everything -DNDEBUG -c"
SRCS = sorted([f for f in os.listdir(src_dir)
               if f.endswith('.m') and f != 'MinimalTester.m'] +
              [f for f in os.listdir(src_dir) if f.endswith('.c')])  # v1.4.140 编译 fishhook.c
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
ssh.close()
print("=== Done ===")
