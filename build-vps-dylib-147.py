"""build-vps-dylib-147.py — VPS 交叉编译 xnower.dylib（v1.4.147）
v1.4.147 = follow 手势触发根因修复（2026-09-04，146 诊断实锤）：
  146 gr_fire 实测：FollowPromptView 手势 _targets=4 非真空，但 target 全
  Swift/TikTok element 类（TapGesHandler/AWEPlayInteractionUserAvatarElement/
  TTKFeedInteractionTouchEventHelper），_action ivar KVC 读 nil → 手动
  performSelector 从未执行（老代码 v1.4.95 起对 Swift 手势空转 = follow 点不动根因）。
  修复：遍历 _targets 时优先对 target 元素（_UIGestureRecognizerTarget 实例）调
  iOS 私有方法 _sendActionWithGestureRecognizer:（系统标准分发路径，内部处理
  SEL/UIAction 任意 action，不依赖 _action ivar 可读性）；手动 KVC 解析降级兜底；
  gr_fire 触发轨迹加 sentBySystem 字段上报（装机后区分主/兜底路径命中）。
  继承 146：ctx_probe servicesCount（HID CopyServices 返回 1 → 非沙盒死路确认）
  + _gestureInfo SEL 记录 + 导航 bug 修复 + 143c 遗产（cookie_dump/net_like）。
"""
import paramiko, os, sys

HOST = '192.129.210.52'
USER = 'root'
REMOTE = '/root/xnow-build'
SDK = '/opt/theos/sdks/iPhoneOS16.5.sdk'
LD = '/usr/lib/llvm-16/bin/ld64.lld'
VERSION = '147'
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
