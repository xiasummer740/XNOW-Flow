"""build-vps-dylib-148.py — VPS 交叉编译 xnower.dylib（v1.4.148）
v1.4.148 = follow 方向 D：profile UIControl 路径（2026-09-04，祥哥拍板）
  145/146/147 三次证伪：feed AWE FollowPromptView = TikTok 自研 AWE 框架纯手势
  element（_handlers 空 / _targets 4 Swift target + _action nil /
  _sendActionWithGestureRecognizer 不响应，sentBySystem 全 False）→ 合成触发不可达死角。
  修复：_performFollowVerified 两轮 feed 失败后 → _followViaProfileFromLabel:：
  从 label "Follow xxx" 提取 username → snssdk1233://user/xxx 深链进作者主页
  （_performOpenProfile: 已有，collect_fans 同链路验证过）→ profile 页找
  TUXButton/UIControl follow 按钮 sendActions + _safeTapAtPoint（like 已验证
  UIControl 可点）→ 2s 验收 label 变 Following/已关注 或按钮消失。
  已关注防护：profile 按钮已是 Following/已关注 → 直接判成功（防 feed 已点成功
  误判后再点变取消）。btnClass/验收上报 state_diag。
  继承 147：_sendActionWithGestureRecognizer + sentBySystem + ctx_probe servicesCount
  + 导航 bug 修复 + 143c 遗产（cookie_dump/net_like）。
"""
import paramiko, os, sys

HOST = '192.129.210.52'
USER = 'root'
REMOTE = '/root/xnow-build'
SDK = '/opt/theos/sdks/iPhoneOS16.5.sdk'
LD = '/usr/lib/llvm-16/bin/ld64.lld'
VERSION = '148'
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
ssh.close()
print("=== Done ===")
